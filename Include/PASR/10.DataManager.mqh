//+------------------------------------------------------------------+
//|                                                 DataManager.mqh  |
//|                                       Copyright 2026, Agsicentre |
//|            Data Management & Indicator Cache Module              |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "1.00"
#property strict

#ifndef __DATA_MANAGER_MQH__
#define __DATA_MANAGER_MQH__

#include "IManager.mqh"

class DataManager : public IManager
{
private:
   int m_atrHandle;
   int m_fractalHandle;

   struct CachedData
   {
      datetime barTime;
      double atr;
      double fractalsUp[];
      double fractalsDown[];
      bool dirty;
   } m_cache;

   PositionScanResult m_scanCache;
   PerformanceStats m_perfStats;
   double m_realizedDailyProfit;
   double m_dayStartBalance;
   datetime m_lastProfitUpdateDay;
   datetime m_lastScanTime;
   int m_lastHistoryCount;
   int m_consecutiveLosses; 
   datetime m_lastLossTime;

public:
   DataManager() : IManager("DataManager", 10),
                   m_atrHandle(INVALID_HANDLE), m_fractalHandle(INVALID_HANDLE),
                   m_realizedDailyProfit(0),
                   m_dayStartBalance(0), m_lastProfitUpdateDay(0), m_lastScanTime(0),
                   m_consecutiveLosses(0),
                   m_lastLossTime(0)
   {
      m_cache.barTime = 0;
      m_cache.atr = 0;
      m_cache.dirty = true;
      ArraySetAsSeries(m_cache.fractalsUp, true);
      ArraySetAsSeries(m_cache.fractalsDown, true);
      ZeroMemory(m_scanCache);
      m_lastHistoryCount = -1;
   }

   ~DataManager()
   {
      if (m_atrHandle != INVALID_HANDLE)
         IndicatorRelease(m_atrHandle);
      if (m_fractalHandle != INVALID_HANDLE)
         IndicatorRelease(m_fractalHandle);
   }

   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;
      m_data = GetPointer(this); 
      return ResetIndicators();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_HEARTBEAT);
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      ResetIndicators();
   }

   bool ResetIndicators()
   {
      m_atrHandle = iATR(m_symbol, m_period, CFG.market.atrPeriod);
      m_fractalHandle = iFractals(m_symbol, m_period);
      if (m_atrHandle == INVALID_HANDLE || m_fractalHandle == INVALID_HANDLE)
         return false;
      UpdateIndicators();
      return true;
   }

   void UpdateIndicators()
   {
      MqlRates rates[];
      if (CopyRates(m_symbol, m_period, 0, 1, rates) <= 0)
         return;
      datetime currentBar = rates[0].time;
      if (m_cache.barTime == currentBar && !m_cache.dirty)
         return;
      if (!SeriesInfoInteger(m_symbol, m_period, SERIES_SYNCHRONIZED))
         return;
      double atrBuf[1];
      if (CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) > 0 && atrBuf[0] > 0)
      {
         m_cache.atr = atrBuf[0] / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if (CopyBuffer(m_fractalHandle, 0, 0, 100, m_cache.fractalsUp) < 100) return;
         if (CopyBuffer(m_fractalHandle, 1, 0, 100, m_cache.fractalsDown) < 100) return;

         m_cache.barTime = currentBar;
         m_cache.dirty = false;
      }
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      UpdateIndicators();
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      UpdateAccountState();
   }

   // --- Getters & Business Logic ---
   double GetATRPoints() const { return m_cache.atr; }
   void MarkDirty() { m_cache.dirty = true; }
   PositionScanResult GetScanResult() const { return m_scanCache; }
   PerformanceStats GetPerformanceStats() const { return m_perfStats; }
   double GetDayStartBalance() const { return m_dayStartBalance; }
   int GetConsecutiveLosses() const { return m_consecutiveLosses; }
   datetime GetLastLossTime() const { return m_lastLossTime; }

   // --- Consolidated Risk Logic ---
   bool CanOpenTrade(double additionalRiskAmount)
   {
      double maxDailyLoss = AccountInfoDouble(ACCOUNT_EQUITY) * (CFG.risk.maxDailyLoss / 100.0);
      return (MathAbs(m_realizedDailyProfit) + additionalRiskAmount) < maxDailyLoss;
   }

   double CalculateLotSize(string symbol, double riskPct, double slDistancePoints, double qualityMultiplier = 1.0)
   {
      if (slDistancePoints <= 0) return 0.0;
      double lot = 0.0;
      if (CFG.risk.autoLot)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

         if (tickValue <= 0 || tickSize <= 0 || equity <= 0) return 0.0;
         double riskMoney = equity * (riskPct / 100.0);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double lossPerLot = (slDistancePoints * point / tickSize) * tickValue;

         if (lossPerLot > 0) lot = riskMoney / lossPerLot;
      }
      else lot = CFG.risk.lot;

      lot *= qualityMultiplier;
      return NormalizeVolume(symbol, lot);
   }

   double CalculatePositionRisk(string symbol, double volume, double slDistancePoints)
   {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if (tickValue <= 0 || tickSize <= 0 || volume <= 0) return 0.0;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return (slDistancePoints * point / tickSize) * tickValue * volume;
   }

   bool ValidateTradeDistances(double slDist, double tpDist, double atrPoints, string &reason)
   {
      if (slDist <= 0)
      {
         reason = "Invalid SL distance";
         return false;
      }

      double minSL = 10.0; 
      if (slDist < minSL)
      {
         reason = StringFormat("SL too close (%.1f < %.1f)", slDist, minSL);
         return false;
      }

      if (tpDist > 0)
      {
         double minTP = atrPoints * CFG.exit.minTPDistATR;
         if (tpDist < minTP)
         {
            reason = "TP too close to entry (Min ATR)";
            return false;
         }
      }
      return true;
   }

   double GetRiskPercentage(string symbol, double volume, double slDistancePoints)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if (equity <= 0) return 0.0;

      double riskMoney = CalculatePositionRisk(symbol, volume, slDistancePoints);
      return (riskMoney / equity) * 100.0;
   }

   void RefreshDailyProfit()
   {
      string gvName = "PASR_PROFIT_" + m_symbol + "_" + (string)CFG.risk.magic;
      datetime times[];
      if (CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0)
         return;
      datetime today = times[0];
      if (HistorySelect(today, TimeCurrent() + 1))
      {
         double dailySum = 0;
         for (int i = 0; i < HistoryDealsTotal(); i++)
         {
            ulong t = HistoryDealGetTicket(i);
            if (t > 0 && HistoryDealGetInteger(t, DEAL_MAGIC) == CFG.risk.magic && (HistoryDealGetString(t, DEAL_SYMBOL) == m_symbol))
            {
               dailySum += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
            }
         }
         m_realizedDailyProfit = dailySum;
      }
      GlobalVariableSet(gvName, m_realizedDailyProfit);
   }

   void ResetDailyAnchor()
   {
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      datetime times[];
      if (CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0)
         return;
      datetime today = times[0];
      RefreshDailyProfit();
      m_dayStartBalance = currentBalance - m_realizedDailyProfit;
      m_lastProfitUpdateDay = today;
   }

   void UpdateAccountState() 
   {
      if (TimeCurrent() - m_lastScanTime < 1 && m_lastScanTime > 0)
         return;
      datetime times[];
      if (CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0)
         return;
      datetime today = times[0];
      if (today != m_lastProfitUpdateDay)
      {
         ResetDailyAnchor();
         m_consecutiveLosses = 0; 
      }
      else
         RefreshDailyProfit();

      UpdatePerformanceStats();
      PositionScanResult temp;
      ZeroMemory(temp);
      temp.dailyRealized = m_realizedDailyProfit;
      double floatingTotal = 0;

      for (int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if (ticket <= 0 || PositionGetInteger(POSITION_MAGIC) != CFG.risk.magic || (PositionGetString(POSITION_SYMBOL) != m_symbol))
            continue;
         floatingTotal += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         temp.normalCount++;
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            temp.buyCount++;
         else
            temp.sellCount++;
      }

      for (int i = 0; i < OrdersTotal(); i++)
      {
         ulong oTicket = OrderGetTicket(i);
         if (oTicket > 0 && OrderGetInteger(ORDER_MAGIC) == CFG.risk.magic && (OrderGetString(ORDER_SYMBOL) == m_symbol))
         {
            ENUM_ORDER_STATE oState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
            if (oState == ORDER_STATE_STARTED || oState == ORDER_STATE_PLACED)
               temp.pendingCount++;
         }
      }

      temp.floatingPnL = floatingTotal;
      temp.totalProfit = temp.dailyRealized + temp.floatingPnL;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if (MathAbs(m_dayStartBalance) > _Point) 
         temp.dailyDrawdown = ((m_dayStartBalance - equity) / m_dayStartBalance) * 100.0;

      m_scanCache = temp;
      m_lastScanTime = TimeCurrent();
   }

   double NormalizePrice(string symbol, double price) const
   {
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }

   double NormalizeVolume(string symbol, double vol) const
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      vol = MathFloor((vol + 1e-12) / (step > 0 ? step : 0.01)) * (step > 0 ? step : 0.01);
      vol = MathMax(vol, minv);
      if (maxv > 0.0)
         vol = MathMin(vol, maxv);
      return vol;
   }

   void UpdatePerformanceStats()
   {
      if (!HistorySelect(0, TimeCurrent()))
         return;

      int total = HistoryDealsTotal();
      if (total == m_lastHistoryCount) return; 
      
      m_lastHistoryCount = total;
      ZeroMemory(m_perfStats);

      for (int i = 0; i < total; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if (t <= 0 || HistoryDealGetInteger(t, DEAL_MAGIC) != CFG.risk.magic)
            continue;
         if (HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

         string comment = HistoryDealGetString(t, DEAL_COMMENT);
         if (StringFind(comment, "P_") == 0 && StringLen(comment) >= 5)
         {
            double net = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_SWAP);
            ushort modeChar = StringGetCharacter(comment, 4);
            if (modeChar == 'S')
            {
               m_perfStats.safeTotal++;
               if (net > 0)
                  m_perfStats.safeWins++;
            }
            else if (modeChar == 'A')
            {
               m_perfStats.aggTotal++;
               if (net > 0)
                  m_perfStats.aggWins++;
            }
         }
      }
   }

   void UpdateConsecutiveLosses(double netProfit)
   {
      if (netProfit < 0)
      {
         m_consecutiveLosses++;
         m_lastLossTime = TimeCurrent();
      }
      else
         m_consecutiveLosses = 0;
   }


   int ParseHM(string hhmm) const
   {
      string parts[];
      if (StringSplit(hhmm, ':', parts) != 2)
         return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      return (h >= 0 && h <= 23 && m >= 0 && m <= 59) ? (h * 60 + m) : -1;
   }

   string BuildComment(string type, int bias, ENUM_ENTRY_MODE mode) const
   {
      string b = (bias > 0) ? "+" : (bias < 0 ? "-" : "0");
      string t = (type == "BUY") ? "B" : (type == "SELL" ? "S" : type);
      string m = (mode == MODE_SAFE) ? "S" : "A";
      return "P_" + t + b + m;
   }

   string StripTags(string html) const
   {
      string res = "";
      bool inside = false;
      for (int i = 0; i < StringLen(html); i++)
      {
         ushort c = StringGetCharacter(html, i);
         if (c == '<')
            inside = true;
         else if (c == '>')
            inside = false;
         else if (!inside)
            StringAdd(res, ShortToString(c));
      }
      return res;
   }

   void DebugLog(bool enabled, string msg) const
   {
      if (enabled)
         Print("[PASR] ", msg);
   }
};

#endif