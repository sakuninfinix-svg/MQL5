//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Order Execution & Trade Management Module             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"  // For MarketRegimeFilter

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
      return "PASR_PEND_" + IntegerToString(m_data.GetConfigCache().magic) + "_" + m_symbol + "_" + IntegerToString(tsID) + "_";
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
      const ConfigSnapshot cfg = m_data.GetConfigCache();
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
      const ConfigSnapshot cfg = m_data.GetConfigCache();
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
      const ConfigSnapshot cfg = m_data.GetConfigCache();
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
      const ConfigSnapshot cfg = m_data.GetConfigCache();
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
      GlobalVariablesDeleteAll("PASR_PEND_" + IntegerToString(m_data.GetConfigCache().magic) + "_" + m_symbol + "_");
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
   }

   //| PUBLIC: Integration & Backward Compatible Methods
public:
   bool BuildOrderPlan(const SignalDecision &decision, OrderPlan &plan,
                       double support, double resistance, double atrPoints, ulong originalTicket = 0, double lotMultiplier = 1.0)
   {
      const ConfigSnapshot cfg = m_data.GetConfigCache();
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
      const ConfigSnapshot cfg = m_data.GetConfigCache();
      if (plan.lot <= 0 || plan.entry <= 0 || plan.atrUsed <= 0)
      {
         if (m_debugMode)
            Print("[Exec Open] Abort: Invalid parameters.");
         return 0;
      }

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);

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

      // SLIPPAGE MITIGATION: Dynamic deviation based on volatility and spread
      double currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double atrPrice = plan.atrUsed * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      // Calculate dynamic deviation: base 10 points + ATR-based adjustment + spread buffer
      double deviationPoints = 10.0;
      if(atrPrice > 0)
      {
         // Add 20% of ATR as slippage buffer in volatile markets
         deviationPoints += (atrPrice * 0.2) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      }
      // Add spread compensation
      deviationPoints += currentSpread / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      // Cap maximum deviation to prevent excessive slippage
      int maxDeviation = cfg.max_slippage_points > 0 ? cfg.max_slippage_points : 50;
      int finalDeviation = (int)MathMin(deviationPoints, maxDeviation);

      request.action = TRADE_ACTION_DEAL;
      request.symbol = m_symbol; // Use m_symbol
      request.magic = cfg.magic;
      request.volume = plan.lot;
      request.price = plan.entry;
      request.sl = plan.brokerSL;
      request.tp = plan.tp;
      request.deviation = finalDeviation;  // DYNAMIC SLIPPAGE CONTROL
      request.type_time = ORDER_TIME_GTC;

      // Use cached filling mode with fallback strategy
      if ((m_fillingMode & SYMBOL_FILLING_FOK) != 0)
         request.type_filling = ORDER_FILLING_FOK;  // Try FOK first (all-or-nothing)
      else if ((m_fillingMode & SYMBOL_FILLING_IOC) != 0)
         request.type_filling = ORDER_FILLING_IOC;  // Then IOC (immediate-or-cancel)
      else
         request.type_filling = ORDER_FILLING_RETURN;  // Fallback to RETURN

      ulong tsID = GetTickCount64() % 10000000000;
      request.comment = plan.comment + "#".String(tsID);

      SavePendingState(plan, zonePrice, slMult, tsID);
      
      // EXECUTION WITH RETRY LOGIC
      int retryCount = 0;
      const int MAX_RETRIES = 2;
      bool success = false;
      
      while(retryCount < MAX_RETRIES && !success)
      {
         if(OrderSendAsync(request, result))
         {
            // Check if request was accepted by server
            if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
            {
               success = true;
               break;
            }
            else
            {
               // Log rejection reason
               if(m_debugMode)
                  PrintFormat("[Exec Open] Request rejected: Retcode=%d, Comment=%s", 
                              result.retcode, result.comment);
            }
         }
         else
         {
            int err = GetLastError();
            if(m_debugMode)
               PrintFormat("[Exec Async] OrderSend failed (attempt %d/%d): Error %d", 
                           retryCount + 1, MAX_RETRIES, err);
         }
         
         retryCount++;
         if(retryCount < MAX_RETRIES)
         {
            // Brief delay before retry (100ms)
            Sleep(100);
            // Refresh prices for retry
            MqlTick tick;
            if(SymbolInfoTick(m_symbol, tick))
            {
               request.price = (plan.type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
            }
         }
      }
      
      if(!success)
      {
         DeletePendingStateById(tsID);
         if(m_debugMode)
            PrintFormat("[Exec Open] Failed after %d retries. Last retcode: %d", 
                        retryCount, result.retcode);
         return 0;
      }

      if (m_debugMode)
         PrintFormat("[Exec Async] Request sent: %s %.2f @ %.5f | Deviation: %d pts | ID: %d",
                     EnumToString(plan.type), plan.lot, request.price, finalDeviation, tsID);

      return tsID;
   }
};

#endif