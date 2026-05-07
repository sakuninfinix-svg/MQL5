//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#ifndef __EXECUTION_MANAGER_MQH__
#define __EXECUTION_MANAGER_MQH__

#property strict
#include "mql5_vscode_fix.h"
#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "7.RiskCalculator.mqh"

//+------------------------------------------------------------------+
//| Subscribes: SignalGenerated, ConfigReload, EmergencyStop,        |
//|             Heartbeat                                            |
//+------------------------------------------------------------------+
class ExecutionManager : public IManager
{
   // PRIVATE: State & Cache                                         
private:
   RiskCalculator m_riskCalc; 
   ulong m_lastOrderTime;
   uint m_orderThrottleMs;  

   struct ExecConfigCache
   {
      bool useAutoLot;
      double riskPct;
      double lotSize;
      double qualityLotMult;
      double minTPDistanceATR;
      double atrBufferMult;
      double slBufferATR;
      double tpBufferATR;
      double maxTPDistanceATR;
      ulong magicNum;
      bool debugMode;
      ENUM_ENTRY_MODE entryMode;
      ENUM_TPSL_MODE tpslMode;
   } m_cfgCache;

   // SignalManager *m_signalManager; // Not needed, using events
   //| PRIVATE: Core Logic                                             
private:
   virtual void RefreshConfigCache() override
   {
      m_cfgCache.useAutoLot = CFG.UseAutoLot;
      m_cfgCache.riskPct = CFG.RiskPct;
      m_cfgCache.lotSize = CFG.LotSize;
      m_cfgCache.qualityLotMult = CFG.QualityLotMult;
      m_cfgCache.minTPDistanceATR = CFG.MinTPDistanceATR;
      m_cfgCache.maxTPDistanceATR = CFG.MaxTPDistanceATR;
      m_cfgCache.atrBufferMult = CFG.ATRBufferMult;
      m_cfgCache.tpslMode = CFG.TPSLMode;
      m_cfgCache.slBufferATR = CFG.SLBufferATR;
      m_cfgCache.tpBufferATR = CFG.TPBufferATR;
      m_cfgCache.magicNum = CFG.MagicNum;
      m_cfgCache.debugMode = CFG.DebugMode;
      m_cfgCache.entryMode = CFG.EntryMode;      
      // Recovery Mode
      m_riskCalc.LoadConfig();
   }

   string MakePendingPrefix(const string symbol, ulong tsID) const
   {
      return "PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + symbol + "_" + (string)tsID + "_";
   }

   void SavePendingState(const OrderPlan &plan, double zonePrice, const string symbol, ulong tsID) const
   {
      string p = MakePendingPrefix(symbol, tsID);
      string data = StringFormat("%.5f|%.2f|%.2f|%d|%.5f", zonePrice, plan.atrUsed, plan.lot, plan.type, plan.tp);
      GlobalVariableSet(p + "data", 1.0); // Flag
      GlobalVariableSet(p + "ts", (double)TimeCurrent());
   }
   void DeletePendingStateById(const string symbol, ulong tsID) const
   {
      string prefix = MakePendingPrefix(symbol, tsID);
      GlobalVariablesDeleteAll(prefix); 
   }

   void ScavengePendingGVs()
   {
      string pattern = "PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + _Symbol + "_";
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
            if (o > 0 && StringFind(OrderGetString(ORDER_COMMENT), tsID_str) >= 0)
            {
               stillActive = true;
               break;
            }
         }
         for (int j = 0; j < PositionsTotal(); j++)
         {
            ulong p = PositionGetTicket(j);
            if (p > 0 && PositionSelectByTicket(p) &&
                StringFind(PositionGetString(POSITION_COMMENT), tsID_str) >= 0)
            {
               stillActive = true;
               break;
            }
         }

         if (!stillActive)
         {
            GlobalVariablesDeleteAll(pattern + tsID_str + "_");
            if (m_cfgCache.debugMode)
               PrintFormat("[Execution] Cleaned orphaned GV: %s", tsID_str);
         }
      }
   }

   bool ValidateOrderLevels(ENUM_ORDER_TYPE type, double price, double sl, double tp,
                            double volume, string &reason, double atrPoints) const
   {
      double stopLevelPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double stopLevel = stopLevelPts * _Point;
      double minTPDist = atrPoints * m_cfgCache.minTPDistanceATR * _Point;
      double maxTPDist = atrPoints * m_cfgCache.maxTPDistanceATR * _Point;
      double requiredTP = MathMax(stopLevel, minTPDist);

      if (type == ORDER_TYPE_BUY)
      {
         if (tp <= price + _Point)
         {
            reason = "BUY TP <= price";
            return false;
         }
         if (sl > 0 && sl >= price - _Point)
         {
            reason = "BUY SL >= price";
            return false;
         }
         if (tp - price < requiredTP)
         {
            reason = StringFormat("BUY TP too close: %.1f < required %.1f (ATR %.1f)",
                                  (tp - price) / _Point, requiredTP / _Point, minTPDist / _Point);
            return false;
         }
         if (tp - price > maxTPDist)
         {
            reason = StringFormat("BUY TP too far: %.1f > max %.1f (ATR %.1f)",
                                  (tp - price) / _Point, maxTPDist / _Point, CFG.MaxTPDistanceATR);
            return false;
         }
         if (sl > 0 && price - sl < stopLevel)
         {
            reason = StringFormat("BUY SL violates stop level: %.1f < %.1f",
                                  (price - sl) / _Point, stopLevel / _Point);
            return false;
         }
         if (CheckPointer(m_data) != POINTER_INVALID && volume > 0)
         {
            double slDist = MathAbs(price - sl) / _Point;
            double posRiskPct = m_riskCalc.GetRiskPercentage(volume, slDist);
            if (posRiskPct > 5.0)
            {
               reason = StringFormat("Position risk too high: %.2f%% > 5%%", posRiskPct);
               return false;
            }
         }
      }
      else
      {
         if (tp >= price - _Point)
         {
            reason = "SELL TP >= price";
            return false;
         }
         if (sl > 0 && sl <= price + _Point)
         {
            reason = "SELL SL <= price";
            return false;
         }
         if (price - tp < requiredTP)
         {
            reason = StringFormat("SELL TP too close: %.1f < required %.1f (ATR %.1f)",
                                  (price - tp) / _Point, requiredTP / _Point, minTPDist / _Point);
            return false;
         }
         if (sl > 0 && sl - price < stopLevel)
         {
            reason = StringFormat("SELL SL violates stop level: %.1f < %.1f",
                                  (sl - price) / _Point, stopLevel / _Point);
            return false;
         }
         if (CheckPointer(m_data) != POINTER_INVALID && volume > 0)
         {
            double slDist = MathAbs(sl - price) / _Point;
            double posRiskPct = m_riskCalc.GetRiskPercentage(volume, slDist);
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
      m_orderThrottleMs = (uint)CFG.OrderThrottleMs;
   }

   virtual void DeclareEvents() override
   {
      AddEvent("SignalGenerated");
      AddEvent("RecoverySignal"); // Subscribe to recovery signals
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
         return;
      if (GetTickCount64() - m_lastOrderTime < (ulong)m_orderThrottleMs)
      {
         if (m_cfgCache.debugMode)
            Print("[Execution] Order throttled. Skipping.");
         return;
      }

      datetime times[];
      if (CopyTime(_Symbol, _Period, 0, 1, times) <= 0)
         return;
      datetime currBar = times[0];
      static datetime lastBarExecuted = 0;
      if (currBar == lastBarExecuted)
      {
         if (m_cfgCache.debugMode)
            Print("[Execution] Already executed this bar. Skipping.");
         return;
      }

      double atr = e.atrPoints;
      double sup = e.support;
      double res = e.resistance;

      if (atr <= 0 || sup <= 0 || res <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[Execution] Invalid market data. Skipping execution.");
         return;
      }

      OrderPlan plan;
      if (BuildOrderPlan(e.signal, plan, sup, res, atr))
      {
         double slDist = MathAbs(plan.entry - plan.brokerSL) / _Point;
         double riskAmount = m_riskCalc.CalculatePositionRisk(plan.lot, slDist);
         if (!m_riskCalc.CanOpenTrade(riskAmount))
         {
            if (m_cfgCache.debugMode)
               PrintFormat("[Execution] Order blocked by daily loss limit. Risk amount: %.2f", riskAmount);
            return;
         }

         ulong reqID = Open(plan, e.signal.zonePrice);
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
      if (GetTickCount64() - m_lastOrderTime < (ulong)m_orderThrottleMs)
      {
         if (m_cfgCache.debugMode)
            Print("[Execution] Recovery order throttled. Skipping.");
         return;
      }

      double atr = e.atrPoints;
      double sup = e.support;
      double res = e.resistance;

      if (atr <= 0 || sup <= 0 || res <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[Execution] Invalid market data for recovery. Skipping execution.");
         return;
      }

      OrderPlan plan;
      // Pass original ticket and recovery lot multiplier
      if (BuildOrderPlan(e.signal, plan, sup, res, atr, e.originalTicket, CFG.RecoveryLotMult))
      {
         ulong reqID = Open(plan, e.signal.zonePrice);
         if (reqID > 0)
         {
            m_lastOrderTime = GetTickCount64();
            if (m_cfgCache.debugMode)
               PrintFormat("[Execution] Recovery order placed for original trade %d. New Request ID: %d", e.originalTicket, reqID);
         }
      } else {
         if (m_cfgCache.debugMode) PrintFormat("[Execution] Failed to build recovery order plan for original trade %d.", e.originalTicket);
      }
   }

   virtual void OnEmergencyStop(EmergencyStopEvent *e) override
   {
      if (m_cfgCache.debugMode)
         Print("[Execution] EMERGENCY STOP: Halting new orders.");
      GlobalVariablesDeleteAll("PASR_PEND_" + (string)m_cfgCache.magicNum + "_" + _Symbol + "_");
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
      if (m_cfgCache.debugMode)
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
      ZeroMemory(plan);
      plan.type = decision.orderType;
      plan.atrUsed = atrPoints;

      if (support <= 0 || resistance <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Build] Error: Invalid SR levels.");
         return false;
      }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if (bid <= 0 || ask <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Build] Error: Invalid market prices.");
         return false;
      }

      plan.entry = (plan.type == ORDER_TYPE_BUY) ? ask : bid;
      double atrPrice = atrPoints * _Point;
      double slBuffer = atrPoints * m_cfgCache.slBufferATR * _Point;
      double tpBuffer = atrPoints * m_cfgCache.tpBufferATR * _Point;
      double patternSLMult = decision.slMultiplier; // Get pattern-specific SL multiplier

      if (plan.type == ORDER_TYPE_BUY)
      {
         double sl = 0;
         if (m_cfgCache.tpslMode == TPSL_PATTERN)
            sl = decision.signalPrice - (slBuffer * patternSLMult);
         else
            sl = support - (slBuffer * patternSLMult);

         double tp = resistance - tpBuffer;

         plan.brokerSL = m_data ? m_data.NormalizePrice(_Symbol, sl) : NormalizeDouble(sl, _Digits);
         plan.tp = m_data ? m_data.NormalizePrice(_Symbol, tp) : NormalizeDouble(tp, _Digits);
      }
      else
      {
         double sl = 0;
         if (m_cfgCache.tpslMode == TPSL_PATTERN)
            sl = decision.signalPrice + slBuffer;
         else // TPSL_SR
            sl = resistance + (slBuffer * patternSLMult);
         
         double tp = support + tpBuffer;

         plan.brokerSL = m_data ? m_data.NormalizePrice(_Symbol, sl) : NormalizeDouble(sl, _Digits);
         plan.tp = m_data ? m_data.NormalizePrice(_Symbol, tp) : NormalizeDouble(tp, _Digits);
      }

      if ((plan.type == ORDER_TYPE_BUY && plan.entry < support - (atrPrice * 0.5)) ||
          (plan.type == ORDER_TYPE_SELL && plan.entry > resistance + (atrPrice * 0.5)))
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Build] Abort: Price far past zone.");
         return false;
      }

      double slDistancePoints = MathAbs(plan.entry - plan.brokerSL) / _Point;
      if (slDistancePoints < 10)
         slDistancePoints = 10;

      string validationReason = "";
      double tpDistancePoints = (plan.tp > 0) ? MathAbs(plan.entry - plan.tp) / _Point : 0;
      if (!m_riskCalc.ValidateDistances(slDistancePoints, tpDistancePoints, atrPoints, validationReason))
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Build] Risk validation failed: ", validationReason);
         return false;
      }

      int qualityScore = decision.orderType == ORDER_TYPE_BUY ? decision.bias : -decision.bias;
      double signalQuality = (qualityScore == 0) ? 1.5 : 1.0; // This might need adjustment for recovery signals
      double baseLot = m_riskCalc.CalculateLotSize(slDistancePoints, signalQuality);

      plan.lot = baseLot;
      plan.comment = m_data ? m_data.BuildComment(plan.type == ORDER_TYPE_BUY ? "BUY" : "SELL", decision.bias, m_cfgCache.entryMode) : "P_EXEC";

      string reason;
      if (!ValidateOrderLevels(plan.type, plan.entry, plan.brokerSL, plan.tp, plan.lot, reason, atrPoints))
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Build] Validation failed: ", reason);
         return false;
      }
      
      // Apply recovery lot multiplier if this is a recovery trade
      if (originalTicket > 0 && lotMultiplier > 0) {
         plan.lot = m_riskCalc.NormalizeVolume(_Symbol, plan.lot * lotMultiplier);
         plan.comment = "RECOV_ORIG_" + (string)originalTicket + "_" + plan.comment;
      }

      return true;
   }

   ulong Open(const OrderPlan &plan, double zonePrice)
   {
      if (plan.lot <= 0 || plan.entry <= 0 || plan.atrUsed <= 0)
      {
         if (m_cfgCache.debugMode)
            Print("[Exec Open] Abort: Invalid parameters.");
         return 0;
      }

      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.magic = m_cfgCache.magicNum;
      request.volume = plan.lot;
      request.type = plan.type;
      request.price = plan.entry;
      request.sl = plan.brokerSL;
      request.tp = plan.tp;
      request.deviation = 30;
      request.type_time = ORDER_TIME_GTC;

      long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if ((filling & SYMBOL_FILLING_IOC) != 0)
         request.type_filling = ORDER_FILLING_IOC;
      else if ((filling & SYMBOL_FILLING_FOK) != 0)
         request.type_filling = ORDER_FILLING_FOK;
      else
         request.type_filling = ORDER_FILLING_RETURN;

      ulong tsID = GetTickCount64() % 10000000000;
      request.comment = plan.comment + "#" + (string)tsID;

      SavePendingState(plan, zonePrice, _Symbol, tsID);
      if (!OrderSendAsync(request, result))
      {
         DeletePendingStateById(_Symbol, tsID);
         if (m_cfgCache.debugMode)
            PrintFormat("[Exec Async] OrderSend failed: %d", GetLastError());
         return 0;
      }

      if (m_cfgCache.debugMode)
         PrintFormat("[Exec Async] Request sent: %s %.2f @ %.5f | ID: %d",
                     EnumToString(plan.type), plan.lot, plan.entry, tsID);

      return tsID;
   }
};

#endif
