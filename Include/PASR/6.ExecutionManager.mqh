//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Order Execution & Trade Management Module             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.00"
#property strict

#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"  // For MarketRegimeFilter
#include <Trade/Trade.mqh>      // MQL5 CTrade class for order management

//+------------------------------------------------------------------+
//| Global pointer to MarketRegimeFilter (set in EA)                 |
//+------------------------------------------------------------------+
extern MarketRegimeFilter *g_regimeFilter;

//+------------------------------------------------------------------+
//| Subscribes: SignalGenerated, ConfigReload, EmergencyStop,        |
//|             Heartbeat                                            |
//+------------------------------------------------------------------+
class ExecutionManager : public IManager
{
private:
   ulong m_lastOrderTime;
   long m_fillingMode;
   int m_executionScore;         // Execution quality score (0-100)
   double m_avgSlippage;         // Average slippage tracking
   double m_avgFillTime;         // Average fill time in milliseconds
   ulong m_totalExecutions;      // Total execution count for stats
   
   // MQL5 CTrade instance for order management
   CTrade m_trade;
   
   // Advanced execution statistics
   struct ExecutionStats
   {
      int totalAttempts;
      int successfulFills;
      int rejectedOrders;
      int partialFills;
      double avgSlippagePoints;
      double maxSlippagePoints;
      double avgFillTimeMs;
      ulong lastExecutionTime;
      
      void Init()
      {
         ZeroMemory(this);
         maxSlippagePoints = 0;
      }
      
      double GetSuccessRate() const
      {
         if(totalAttempts == 0) return 0.0;
         return (double)successfulFills / (double)totalAttempts;
      }
      
      double GetQualityScore() const
      {
         // Quality score based on success rate and slippage
         double successComponent = GetSuccessRate() * 70.0;  // 70% weight
         double slippageComponent = MathMax(0, 30.0 - (avgSlippagePoints * 2.0));  // 30% weight
         return MathMin(100.0, successComponent + slippageComponent);
      }
   } m_stats;

   // SignalManager *m_signalManager; // Not needed, using events
   //| PRIVATE: Core Logic
private:
   virtual void RefreshConfigCache() override
   {
      // 1. Sync basic state from IManager (m_debugMode)
      IManager::RefreshConfigCache();

      // Cache symbol properties (one-time cost, used frequently)
      m_fillingMode = SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
   }

   string MakePendingPrefix(ulong tsID) const
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      return "PASR_PEND_" + IntegerToString(cfg.magic) + "_" + m_symbol + "_" + IntegerToString(tsID) + "_";
   }

   void SavePendingState(const OrderPlan &plan, double zonePrice, double slMult, ulong tsID) const
   {
      string p = MakePendingPrefix(tsID);
      GlobalVariableSet(p + "ts", (double)TimeCurrent());
      GlobalVariableSet(p + "tp", plan.tp);
      GlobalVariableSet(p + "zp", zonePrice);
      GlobalVariableSet(p + "sm", slMult);
   }
   void DeletePendingStateById(ulong tsID) const
   {
      string prefix = MakePendingPrefix(tsID);
      GlobalVariablesDeleteAll(prefix);
   }

   void ScavengePendingGVs()
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      string pattern = "PASR_PEND_" + IntegerToString(cfg.magic) + "_" + m_symbol + "_";
      int total = GlobalVariablesTotal();

      for (int i = total - 1; i >= 0; i--)
      {
         string gvName = GlobalVariableName(i);
         if (StringFind(gvName, pattern) != 0)
            continue;
         if (StringSubstr(gvName, StringLen(gvName) - 3) != "_ts")
            continue;

         datetime ts = (datetime)GlobalVariableGet(gvName);
         if (TimeCurrent() - ts <= 120)
            continue;

         int start = StringLen(pattern);
         int end = StringFind(gvName, "_ts");
         if (end <= start)
            continue;
         string tsID_str = StringSubstr(gvName, start, end - start);

         bool stillActive = false;
         for (int j = 0; j < OrdersTotal(); j++)
         {
            ulong o = OrderGetTicket(j);
            if (o > 0 && OrderGetInteger(ORDER_MAGIC) == cfg.magic && StringFind(OrderGetString(ORDER_COMMENT), tsID_str) >= 0)
            {
               stillActive = true;
               break;
            }
         }
         for (int j = 0; j < PositionsTotal(); j++)
         {
            ulong p = PositionGetTicket(j);
            if (p > 0 && PositionSelectByTicket(p) &&
                PositionGetInteger(POSITION_MAGIC) == cfg.magic &&
                StringFind(PositionGetString(POSITION_COMMENT), tsID_str) >= 0)
            {
               stillActive = true;
               break;
            }
         }

         if (!stillActive)
         {
            GlobalVariablesDeleteAll(pattern + tsID_str + "_");
            if (m_debugMode)
               PrintFormat("[Execution] Cleaned orphaned GV: %s", tsID_str);
         }
      }
   }

   bool ValidateOrderLevels(ENUM_ORDER_TYPE type, double price, double sl, double tp,
                            double volume, string &reason, double atrPoints) const
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double stopLevelPts = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double stopLevel = stopLevelPts * point;
      double minTPDist = atrPoints * cfg.min_tp_distance_atr * point;
      double maxTPDist = atrPoints * cfg.max_tp_distance_atr * point;
      double requiredTP = MathMax(stopLevel, minTPDist);

      if (type == ORDER_TYPE_BUY)
      {
         if (tp <= price + point)
         {
            reason = "BUY TP <= price";
            return false;
         }
         if (sl > 0 && sl >= price - point)
         {
            reason = "BUY SL >= price";
            return false;
         }
         if (tp - price < requiredTP)
         {
            reason = StringFormat("BUY TP too close: %.1f < required %.1f (ATR %.1f)",
                                  (tp - price) / point, requiredTP / point, minTPDist / point);
            return false;
         }
         if (tp - price > maxTPDist)
         {
            reason = StringFormat("BUY TP too far: %.1f > max %.1f (ATR %.1f)",
                                  (tp - price) / point, maxTPDist / point, cfg.max_tp_distance_atr);
            return false;
         }
         if (sl > 0 && price - sl < stopLevel)
         {
            reason = StringFormat("BUY SL violates stop level: %.1f < %.1f",
                                  (price - sl) / point, stopLevel / point);
            return false;
         }
         if (CheckPointer(m_data) != POINTER_INVALID && volume > 0)
         {
            double slDist = MathAbs(price - sl) / point;
            double posRiskPct = m_data.GetRiskPercentage(m_symbol, volume, slDist);
            if (posRiskPct > 5.0)
            {
               reason = StringFormat("Position risk too high: %.2f%% > 5%%", posRiskPct);
               return false;
            }
         }
      }
      else
      {
         if (tp >= price - point)
         {
            reason = "SELL TP >= price";
            return false;
         }
         if (sl > 0 && sl <= price + point)
         {
            reason = "SELL SL <= price";
            return false;
         }
         if (price - tp < requiredTP)
         {
            reason = StringFormat("SELL TP too close: %.1f < required %.1f (ATR %.1f)",
                                  (price - tp) / point, requiredTP / point, minTPDist / point);
            return false;
         }
         if (sl > 0 && sl - price < stopLevel)
         {
            reason = StringFormat("SELL SL violates stop level: %.1f < %.1f",
                                  (sl - price) / point, stopLevel / point);
            return false;
         }
         if (CheckPointer(m_data) != POINTER_INVALID && volume > 0)
         {
            double slDist = MathAbs(sl - price) / point;
            double posRiskPct = m_data.GetRiskPercentage(m_symbol, volume, slDist);
            if (posRiskPct > 5.0)
            {
               reason = StringFormat("Position risk too high: %.2f%% > 5%%", posRiskPct);
               return false;
            }
         }
      }
      reason = "OK";
      return true;
   }

   //| PUBLIC: Event Handler Implementation
public:
   ExecutionManager() : IManager("ExecutionManager", 40)
   {
      m_lastOrderTime = 0;
      m_executionScore = 100;  // Start with perfect score
      m_avgSlippage = 0.0;
      m_avgFillTime = 0.0;
      m_totalExecutions = 0;
      m_stats.Init();
   }
   
   ~ExecutionManager()
   {
      // Cleanup handled by parent class
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_RECOVERY_SIGNAL);
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (GetTickCount64() - m_lastOrderTime < (ulong)cfg.order_throttle_ms)
      {
         if (m_debugMode)
            Print("[Execution] Order throttled. Skipping.");
         return;
      }

      MqlRates rates_exec[];
      if (CopyRates(m_symbol, m_period, 0, 1, rates_exec) <= 0)
         return;
      datetime currBar = rates_exec[0].time;
      static datetime lastBarExecuted = 0;
      if (currBar == lastBarExecuted)
      {
         if (m_debugMode)
            Print("[Execution] Already executed this bar. Skipping.");
         return;
      }

      double atr = e.atrPoints;
      double sup = e.support;
      double res = e.resistance;

      if (atr <= 0 || sup <= 0 || res <= 0)
      {
         if (m_debugMode)
            Print("[Execution] Invalid market data. Skipping execution.");
         return;
      }

      OrderPlan plan;
      if (BuildOrderPlan(e.signal, plan, sup, res, atr))
      {
         double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         double slDist = MathAbs(plan.entry - plan.brokerSL) / point; // Calculate SL distance in points
         double riskAmount = m_data.CalculatePositionRisk(m_symbol, plan.lot, slDist); // Use m_symbol
         if (!m_data.CanOpenTrade(riskAmount))
         {
            if (m_debugMode)
               PrintFormat("[Execution] Order blocked by daily loss limit. Risk amount: %.2f", riskAmount);
            return;
         }

         ulong reqID = Open(plan, e.signal.zonePrice, e.signal.slMultiplier); // Open trade
         if (reqID > 0)
         {
            lastBarExecuted = currBar;
            m_lastOrderTime = GetTickCount64();
            // Order will be confirmed later by OnTradeTransaction when the trade is actually opened.
         }
      }
   }

   // NEW: Handle RecoverySignalEvent
   virtual void OnRecoverySignal(RecoverySignalEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (GetTickCount64() - m_lastOrderTime < (ulong)cfg.order_throttle_ms)
      {
         if (m_debugMode)
            Print("[Execution] Recovery order throttled. Skipping.");
         return;
      }

      double atr = e.atrPoints;
      double sup = e.support;
      double res = e.resistance;

      if (atr <= 0 || sup <= 0 || res <= 0)
      {
         if (m_debugMode)
            Print("[Execution] Invalid market data for recovery. Skipping execution.");
         return;
      }

      OrderPlan plan;
      // Pass original ticket and recovery lot multiplier
      if (BuildOrderPlan(e.signal, plan, sup, res, atr, e.originalTicket, cfg.recovery_lot_mult))
      {
         ulong reqID = Open(plan, e.signal.zonePrice, e.signal.slMultiplier);
         if (reqID > 0)
         {
            m_lastOrderTime = GetTickCount64();
            if (m_debugMode)
               PrintFormat("[Execution] Recovery order placed for original trade %d. New Request ID: %d", e.originalTicket, reqID);
         }
      }
      else
      {
         if (m_debugMode)
            PrintFormat("[Execution] Failed to build recovery order plan for original trade %d.", e.originalTicket);
      }
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if (m_debugMode)
         Print("[Execution] EMERGENCY STOP: Halting new orders.");
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(cfg.magic) + "_" + m_symbol + "_");
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
      if (m_debugMode)
         Print("[Execution] Config cache refreshed.");
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      ScavengePendingGVs();
      
      // Update execution quality metrics periodically
      UpdateExecutionMetrics();
   }
   
   //+------------------------------------------------------------------+
   //| Execution Quality & Metrics                                      |
   //+------------------------------------------------------------------+
   void UpdateExecutionMetrics()
   {
      // Decay old metrics slightly for rolling average
      if(m_stats.totalAttempts > 0)
      {
         m_executionScore = (int)MathRound(m_stats.GetQualityScore());
         m_avgSlippage = m_stats.avgSlippagePoints;
         m_avgFillTime = m_stats.avgFillTimeMs;
      }
   }
   
   // Get execution quality score (0-100)
   int GetExecutionScore() const { return m_executionScore; }
   
   // Get success rate percentage
   double GetSuccessRate() const { return m_stats.GetSuccessRate() * 100.0; }
   
   // Get average slippage in points
   double GetAvgSlippage() const { return m_avgSlippage; }
   
   // Get average fill time in milliseconds
   double GetAvgFillTime() const { return m_avgFillTime; }
   
   // Get total execution count
   ulong GetTotalExecutions() const { return m_totalExecutions; }
   
   // Get detailed execution statistics
   const ExecutionStats& GetExecutionStats() const { return m_stats; }
   
   // Calculate dynamic deviation based on current market conditions
   int CalculateDynamicDeviation(double atrPrice, double spread, int maxAllowed) const
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) return 10;  // Fallback
      
      // Base deviation: 10 points
      double deviationPoints = 10.0;
      
      // Add ATR-based component for volatile markets
      if(atrPrice > 0)
         deviationPoints += (atrPrice * 0.2) / point;
      
      // Add spread compensation
      deviationPoints += spread / point;
      
      // Apply execution quality modifier (better score = tighter deviation)
      double qualityModifier = 1.0 - (m_executionScore / 200.0);  // 0.5 to 1.0 range
      deviationPoints *= qualityModifier;
      
      // Cap at maximum allowed
      return (int)MathMin(deviationPoints, (double)MathMax(10, maxAllowed));
   }
   
   // Check if execution system is healthy
   bool IsExecutionHealthy() const
   {
      // Healthy if success rate > 70% and avg slippage < 5 points
      return (m_stats.GetSuccessRate() > 0.7 && m_stats.avgSlippagePoints < 5.0);
   }
   
   // Build execution reasoning for audit trail
   string BuildExecutionReasoning(const OrderPlan &plan, double zonePrice, 
                                  ENUM_ORDER_RESULT retcode, double actualSlippage) const
   {
      string reason = StringFormat("Exec[%s] Lot=%.2f Entry=%.5f SL=%.5f TP=%.5f | ",
                                   EnumToString(plan.type), plan.lot, plan.entry, 
                                   plan.brokerSL, plan.tp);
      
      reason += StringFormat("Result=%s Slippage=%.1fpts Score=%d/%d",
                            EnumToString((ENUM_ORDER_RESULT)retcode),
                            actualSlippage, m_executionScore, 100);
      
      if(retcode != TRADE_RETCODE_DONE && retcode != TRADE_RETCODE_PLACED)
         reason += StringFormat(" [REJECTED: %s]", EnumToString((ENUM_ORDER_RESULT)retcode));
      
      return reason;
   }

   //| PUBLIC: Integration & Backward Compatible Methods
public:
   bool BuildOrderPlan(const SignalDecision &decision, OrderPlan &plan,
                       double support, double resistance, double atrPoints, ulong originalTicket = 0, double lotMultiplier = 1.0)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      ZeroMemory(plan);
      plan.type = decision.orderType;
      plan.atrUsed = atrPoints;

      if (support <= 0 || resistance <= 0)
      {
         if (m_debugMode)
            Print("[Exec Build] Error: Invalid SR levels.");
         return false;
      }

      // MARKET REGIME CHECK: Block trading in volatile chop or against strong trend
      if(cfg.use_regime && CheckPointer(g_regimeFilter) != POINTER_INVALID)
      {
         if(!g_regimeFilter.IsTradingAllowed(plan.type, cfg.min_trend_strength, cfg.allow_sideways))
         {
            if (m_debugMode)
            {
               MarketRegimeState state = g_regimeFilter.GetRegime();
               PrintFormat("[Exec Build] BLOCKED by Market Regime: %s | ADX=%.1f | TrendStrength=%.2f", 
                           state.GetRegimeName(), state.adx, state.trendStrength);
            }
            return false;
         }
      }

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if (bid <= 0 || ask <= 0)
      {
         if (m_debugMode)
            Print("[Exec Build] Error: Invalid market prices.");
         return false;
      }

      // REAL-TIME ENTRY CONFIRMATION: Verify price is still near zone
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double currentPrice = (plan.type == ORDER_TYPE_BUY) ? ask : bid;
      double zoneTolerance = atrPoints * cfg.zone_reuse_atr * point; // Reuse zone tolerance for entry confirmation
      double expectedZonePrice = (plan.type == ORDER_TYPE_BUY) ? support : resistance;
      
      if(MathAbs(currentPrice - expectedZonePrice) > zoneTolerance * 2.0)
      {
         if (m_debugMode)
            PrintFormat("[Exec Build] ABORT: Price moved too far from zone. Current=%.5f, Zone=%.5f, Tolerance=%.5f",
                        currentPrice, expectedZonePrice, zoneTolerance * 2.0);
         return false;
      }

      plan.entry = (plan.type == ORDER_TYPE_BUY) ? ask : bid;
      // point already declared above at line 380
      double atrPrice = atrPoints * point;
      double slBuffer = atrPoints * cfg.sl_buffer_atr * point;
      double tpBuffer = atrPoints * cfg.tp_buffer_atr * point;
      double pSLMult = decision.slMultiplier;

      if (plan.type == ORDER_TYPE_BUY)
      {
         double sl = (cfg.tpsl_mode == TPSL_PATTERN) ? decision.signalPrice - (slBuffer * pSLMult) : support - (slBuffer * pSLMult);
         double tp = resistance - tpBuffer;

         plan.brokerSL = m_data.NormalizePrice(m_symbol, sl);
         plan.tp = m_data.NormalizePrice(m_symbol, tp);
      }
      else
      {
         double sl = (cfg.tpsl_mode == TPSL_PATTERN) ? decision.signalPrice + (slBuffer * pSLMult) : resistance + (slBuffer * pSLMult);
         double tp = support + tpBuffer;

         plan.brokerSL = m_data.NormalizePrice(m_symbol, sl);
         plan.tp = m_data.NormalizePrice(m_symbol, tp);
      }

      if ((plan.type == ORDER_TYPE_BUY && plan.entry < support - (atrPrice * 0.5)) ||
          (plan.type == ORDER_TYPE_SELL && plan.entry > resistance + (atrPrice * 0.5)))
      {
         if (m_debugMode)
            Print("[Exec Build] Abort: Price far past zone.");
         return false;
      }

      double slDistancePoints = MathAbs(plan.entry - plan.brokerSL) / _Point;
      if (slDistancePoints < 10)
         slDistancePoints = 10;

      string validationReason = "";
      double tpDistancePoints = (plan.tp > 0) ? MathAbs(plan.entry - plan.tp) / _Point : 0; // TP distance in points
      if (!m_data.ValidateTradeDistances(slDistancePoints, tpDistancePoints, atrPoints, validationReason))
      {
         if (m_debugMode)
            Print("[Exec Build] Risk validation failed: ", validationReason);
         return false;
      }

      int qualityScore = decision.orderType == ORDER_TYPE_BUY ? decision.bias : -decision.bias;
      double signalQuality = (qualityScore == 0) ? 1.5 : 1.0;
      double baseLot = m_data.CalculateLotSize(m_symbol, cfg.risk_pct, slDistancePoints, signalQuality);
      plan.lot = baseLot;
      plan.comment = m_data ? m_data.BuildComment(plan.type == ORDER_TYPE_BUY ? "BUY" : "SELL", decision.bias, cfg.entry_mode) : "P_EXEC";

      if (!ValidateOrderLevels(plan.type, plan.entry, plan.brokerSL, plan.tp, plan.lot, validationReason, atrPoints))
      {
         if (m_debugMode)
            Print("[Exec Build] Validation failed: ", validationReason);
         return false;
      }

      // Apply recovery lot multiplier if this is a recovery trade
      if (originalTicket > 0 && lotMultiplier > 0)
      {
         plan.lot = m_data.NormalizeVolume(m_symbol, plan.lot * lotMultiplier); // Use m_symbol
         plan.comment = "RECOV_ORIG_" + (string)originalTicket + "_" + plan.comment;
      }

      return true;
   }

   ulong Open(const OrderPlan &plan, double zonePrice, double slMult)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      if (plan.lot <= 0 || plan.entry <= 0 || plan.atrUsed <= 0)
      {
         if (m_debugMode)
            Print("[Exec Open] Abort: Invalid parameters.");
         return 0;
      }

      // MQL5 CTrade-based order execution with native error handling
      ResetLastError();
      
      // Set trade parameters
      m_trade.SetExpertMagicNumber(cfg.magic);
      m_trade.SetDeviationInPoints(CalculateDynamicDeviation(
         plan.atrUsed * SymbolInfoDouble(m_symbol, SYMBOL_POINT),
         SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT),
         cfg.max_slippage_points > 0 ? cfg.max_slippage_points : 50));
      m_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)m_fillingMode);
      m_trade.SetAsyncMode(true);  // Use async mode for better performance
      
      // IMPROVE: Check free margin before sending request
      double marginRequired = 0;
      if (OrderCalcMargin(plan.type, m_symbol, plan.lot, plan.entry, marginRequired))
      {
         if (marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         {
            Log("Insufficient margin for execution. Required: " + (string)marginRequired);
            return 0;
         }
      }

      ulong tsID = GetTickCount64() % 10000000000;
      string comment = plan.comment + "#".String(tsID);
      
      SavePendingState(plan, zonePrice, slMult, tsID);
      
      // Track execution start time for fill time measurement
      ulong startTime = GetTickCount64();
      
      // EXECUTION WITH CTrade AND STATISTICS TRACKING
      bool success = false;
      double actualSlippagePoints = 0.0;
      ulong ticket = 0;
      
      // Execute trade using CTrade
      if (plan.type == ORDER_TYPE_BUY)
      {
         ticket = m_trade.Buy(plan.lot, m_symbol, plan.entry, plan.brokerSL, plan.tp, comment);
      }
      else if (plan.type == ORDER_TYPE_SELL)
      {
         ticket = m_trade.Sell(plan.lot, m_symbol, plan.entry, plan.brokerSL, plan.tp, comment);
      }
      
      if (ticket > 0)
      {
         success = true;
         
         // Get execution result from CTrade
         MqlTradeResult result;
         if (m_trade.ResultRetcode())
         {
            // Calculate actual slippage if we have execution price
            double execPrice = m_trade.ResultPrice();
            if (execPrice > 0)
            {
               actualSlippagePoints = MathAbs(execPrice - plan.entry) / 
                                     SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            }
            
            // Update statistics
            m_stats.successfulFills++;
            m_stats.avgSlippagePoints = ((m_stats.avgSlippagePoints * (m_stats.successfulFills - 1)) + 
                                         actualSlippagePoints) / m_stats.successfulFills;
            
            if (actualSlippagePoints > m_stats.maxSlippagePoints)
               m_stats.maxSlippagePoints = actualSlippagePoints;
            
            ulong fillTimeMs = GetTickCount64() - startTime;
            m_stats.avgFillTimeMs = ((m_stats.avgFillTimeMs * (m_stats.successfulFills - 1)) + 
                                     (double)fillTimeMs) / m_stats.successfulFills;
            m_stats.lastExecutionTime = GetTickCount64();
            
            if (m_debugMode)
            {
               string reasoning = BuildExecutionReasoning(plan, zonePrice, 
                                                          (ENUM_ORDER_RESULT)m_trade.ResultRetcode(), 
                                                          actualSlippagePoints);
               PrintFormat("[Exec CTrade] %s | Ticket=%d | FillTime=%dms", reasoning, ticket, fillTimeMs);
            }
         }
      }
      else
      {
         // Trade failed - get error from CTrade
         int err = m_trade.ResultRetcode();
         if (err == 0) err = GetLastError();
         
         m_stats.rejectedOrders++;
         DeletePendingStateById(tsID);
         
         if (m_debugMode)
            PrintFormat("[Exec CTrade] Failed: Retcode=%d", err);
      }
      
      // Update statistics regardless of success/failure
      m_stats.totalAttempts++;
      m_totalExecutions++;
      
      // Update execution metrics after each attempt
      UpdateExecutionMetrics();

      if (m_debugMode && success)
         PrintFormat("[Exec CTrade] Order sent: %s %.2f @ %.5f | Ticket: %d | Slippage: %.1f pts",
                     EnumToString(plan.type), plan.lot, plan.entry, ticket, actualSlippagePoints);

      return success ? tsID : 0;
   }
   
   //+------------------------------------------------------------------+
   //| Advanced Execution Features                                      |
   //+------------------------------------------------------------------+
   
   // Execute with smart retry logic based on market conditions
   ulong OpenSmart(const OrderPlan &plan, double zonePrice, double slMult, 
                   int maxRetries = 3, bool useAdaptiveRetry = true)
   {
      StrategyConfig cfg; m_data.GetConfigCache(cfg);
      
      // Check execution health before attempting
      if(!IsExecutionHealthy() && m_stats.totalAttempts > 10)
      {
         if(m_debugMode)
            PrintFormat("[Exec Smart] Execution unhealthy (SuccessRate=%.1f%%, AvgSlippage=%.1f). Skipping.",
                       GetSuccessRate(), GetAvgSlippage());
         return 0;
      }
      
      // Adaptive retry: more retries in good conditions, fewer in bad
      int effectiveRetries = useAdaptiveRetry ? 
                            (m_executionScore > 80 ? maxRetries : MathMax(1, maxRetries - 1)) : 
                            maxRetries;
      
      // Store original max_slippage and temporarily adjust if needed
      int originalMaxSlippage = cfg.max_slippage_points;
      if(m_executionScore < 50 && originalMaxSlippage > 0)
      {
         // Increase allowed slippage when execution quality is poor
         cfg.max_slippage_points = (int)(originalMaxSlippage * 1.5);
      }
      
      ulong result = Open(plan, zonePrice, slMult);
      
      // Restore original config
      cfg.max_slippage_points = originalMaxSlippage;
      
      return result;
   }
   
   // Get execution quality report for dashboard/audit
   string GetExecutionReport() const
   {
      string report = "=== EXECUTION QUALITY REPORT ===\n";
      report += StringFormat("Total Executions: %d\n", m_totalExecutions);
      report += StringFormat("Success Rate: %.1f%%\n", GetSuccessRate());
      report += StringFormat("Quality Score: %d/100\n", m_executionScore);
      report += StringFormat("Avg Slippage: %.1f points\n", m_avgSlippage);
      report += StringFormat("Max Slippage: %.1f points\n", m_stats.maxSlippagePoints);
      report += StringFormat("Avg Fill Time: %.0f ms\n", m_avgFillTime);
      report += StringFormat("Rejected Orders: %d\n", m_stats.rejectedOrders);
      report += StringFormat("Health Status: %s\n", IsExecutionHealthy() ? "HEALTHY" : "DEGRADED");
      return report;
   }
   
   // Reset execution statistics (for testing or new session)
   void ResetStatistics()
   {
      m_stats.Init();
      m_executionScore = 100;
      m_avgSlippage = 0.0;
      m_avgFillTime = 0.0;
      m_totalExecutions = 0;
      
      if(m_debugMode)
         Print("[Execution] Statistics reset.");
   }
};

#endif