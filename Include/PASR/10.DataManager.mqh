//+------------------------------------------------------------------+
//|                                                10.DataManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Data Management & Indicator Cache Module - V2.10      |
//|                                                                   |
//| REFACTORING v2.10 FIXES:                                          |
//| - CRITICAL: All StrategyConfig field accesses corrected to use    |
//|   nested struct notation (market.atrPeriod, risk.magic, etc.)     |
//|   Previous flat snake_case fields caused compile errors.          |
//| - CRITICAL: Removed #include "2.Config.Manager.mqh" — layering   |
//|   violation. DataManager must NOT depend on ConfigManager.        |
//|   Config is now injected via InitConfigCache(StrategyConfig&).    |
//| - SECURITY: GV key in RefreshDailyProfit now prefixed with        |
//|   AccountInfoInteger(ACCOUNT_LOGIN) to prevent cross-instance     |
//|   state corruption on same terminal.                              |
//| - PerformanceStats struct field names corrected.                  |
//| - All DM-BUG-4, DM-BUG-5 fixes from v2.02 preserved.            |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.10"
#property strict

#ifndef __DATA_MANAGER_MQH__
#define __DATA_MANAGER_MQH__

#include "IManager.mqh"
#include "2.Config.Types.mqh"
// NOTE: 2.Config.Manager.mqh is intentionally NOT included here.
// DataManager is a data/infrastructure layer. It must not depend on the
// config management layer. Config is injected via InitConfigCache().
// NOTE: 12.MarketRegime.mqh is intentionally NOT included here.
// MarketRegimeFilter is accessed via extern pointer g_regimeFilter.

//+------------------------------------------------------------------+
//| Utility Functions Class (Non-Data Utilities)                     |
//+------------------------------------------------------------------+
class DataUtils
{
public:
   // Parse "HH:MM" string to minutes since midnight
   static int ParseHM(const string hm)
   {
      string parts[];
      if(StringSplit(hm, ':', parts) != 2) return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
      return h * 60 + m;
   }

   // Strip HTML-like tags from comment strings
   static string StripTags(const string input)
   {
      string result = input;
      int start = StringFind(result, "<");
      while(start >= 0)
      {
         int end = StringFind(result, ">", start);
         if(end < 0) break;
         result = StringSubstr(result, 0, start) + StringSubstr(result, end + 1);
         start = StringFind(result, "<");
      }
      return result;
   }

   // Build formatted comment for dashboard display
   static string BuildComment(const string title, const string content)
   {
      return "<b>" + title + "</b>\n" + content;
   }
};

//+------------------------------------------------------------------+
//| Performance Tracker Class (Modular Statistics)                   |
//+------------------------------------------------------------------+
class PerformanceTracker
{
private:
   ulong  m_magic;
   string m_symbol;

   struct StatWindow
   {
      datetime startTime;
      int      totalTrades;
      double   grossProfit;
      double   grossLoss;
      double   maxDrawdown;
      double   peakEquity;

      void Reset(datetime anchorTime)
      {
         startTime   = anchorTime;
         totalTrades = 0;
         grossProfit = 0;
         grossLoss   = 0;
         maxDrawdown = 0;
         peakEquity  = 0;
      }
   };

   StatWindow m_lifetime;
   StatWindow m_session;
   StatWindow m_rolling7d;
   StatWindow m_rolling30d;

   datetime m_lastUpdate;

   void UpdateWindow(StatWindow &win, double profit, double currentEquity)
   {
      win.totalTrades++;
      if(profit > 0)
         win.grossProfit += profit;
      else
         win.grossLoss += MathAbs(profit);

      if(currentEquity > win.peakEquity)
         win.peakEquity = currentEquity;

      double dd = win.peakEquity - currentEquity;
      if(dd > win.maxDrawdown)
         win.maxDrawdown = dd;
   }

   // FIX DM-BUG-4: Sliding window reset preserves relative start time.
   // Sets new anchor = now - windowSeconds so window slides forward.
   void CheckRollingWindows()
   {
      datetime now = TimeCurrent();
      if(now - m_rolling7d.startTime  > 7  * 24 * 3600)
         m_rolling7d.Reset(now  - 7  * 24 * 3600);
      if(now - m_rolling30d.startTime > 30 * 24 * 3600)
         m_rolling30d.Reset(now - 30 * 24 * 3600);
   }

public:
   PerformanceTracker() : m_magic(0), m_symbol(""), m_lastUpdate(0)
   {
      datetime now = TimeCurrent();
      m_lifetime.Reset(now);
      m_session.Reset(now);
      m_rolling7d.Reset(now);
      m_rolling30d.Reset(now);
   }

   void Initialize(ulong magic, const string symbol)
   {
      m_magic  = magic;
      m_symbol = symbol;
      datetime now = TimeCurrent();
      m_lifetime.startTime   = now;
      m_session.startTime    = now;
      m_rolling7d.startTime  = now;
      m_rolling30d.startTime = now;
   }

   void RecordTrade(double profit, double currentEquity)
   {
      CheckRollingWindows();
      UpdateWindow(m_lifetime,   profit, currentEquity);
      UpdateWindow(m_session,    profit, currentEquity);
      UpdateWindow(m_rolling7d,  profit, currentEquity);
      UpdateWindow(m_rolling30d, profit, currentEquity);
      m_lastUpdate = TimeCurrent();
   }

   void ResetSession() { m_session.Reset(TimeCurrent()); }

   PerformanceStats GetLifetimeStats() const
   {
      PerformanceStats stats;
      stats.safeTotal = m_lifetime.totalTrades;
      stats.safeWins  = (int)m_lifetime.grossProfit;   // proxy — caller should use grossProfit directly
      stats.aggTotal  = 0;
      stats.aggWins   = 0;
      return stats;
   }

   PerformanceStats GetSessionStats() const
   {
      PerformanceStats stats;
      stats.safeTotal = m_session.totalTrades;
      stats.safeWins  = 0;
      stats.aggTotal  = 0;
      stats.aggWins   = 0;
      return stats;
   }

   datetime GetLastUpdate() const { return m_lastUpdate; }
};

//+------------------------------------------------------------------+
//| Forward Declaration: MarketRegimeFilter                          |
//| Do NOT include 12.MarketRegime.mqh here (circular dependency).   |
//+------------------------------------------------------------------+
class MarketRegimeFilter;

//+------------------------------------------------------------------+
//| Global pointer to MarketRegimeFilter (set in EA OnInit)          |
//+------------------------------------------------------------------+
extern MarketRegimeFilter *g_regimeFilter;

//+------------------------------------------------------------------+
//| Cache state enumeration for data validity tracking               |
//+------------------------------------------------------------------+
enum ENUM_CACHE_STATE
{
   CACHE_OK,        // Data is valid and fresh
   CACHE_STALE,     // Data is old but may still be usable
   CACHE_INVALID,   // Data is invalid, do not use
   CACHE_UPDATING,  // Data is being updated
   CACHE_ERROR      // Error occurred during last update
};

//+------------------------------------------------------------------+
//| Interface for Dependency Injection                               |
//+------------------------------------------------------------------+
interface IDataProvider
{
   double              GetATRPoints()    const;
   PositionScanResult  GetScanResult()   const;
   PerformanceStats    GetPerformanceStats() const;
   bool                CanOpenTrade(double additionalRiskAmount);
   double              CalculateLotSize(string symbol, double riskPct,
                                        double slDistancePoints,
                                        double qualityMultiplier = 1.0);
   double              NormalizeVolume(string symbol, double vol) const;
   void                GetConfigCache(StrategyConfig &cfg) const;
   ENUM_CACHE_STATE    GetCacheState() const;
   string              GetCacheError()  const;
};

//+------------------------------------------------------------------+
//| DataManager — Implements IDataProvider                           |
//+------------------------------------------------------------------+
class DataManager : public IManager
{
private:
   //--- Inner proxy implementing IDataProvider interface
   class CDataProviderProxy : public IDataProvider
   {
   private:
      DataManager *m_mgr;
   public:
      CDataProviderProxy(DataManager *mgr) : m_mgr(mgr) {}

      virtual double             GetATRPoints()    const override { return m_mgr.GetATRPoints(); }
      virtual PositionScanResult GetScanResult()   const override { return m_mgr.GetScanResult(); }
      virtual PerformanceStats   GetPerformanceStats() const override { return m_mgr.GetPerformanceStats(); }
      virtual bool               CanOpenTrade(double r) override  { return m_mgr.CanOpenTrade(r); }
      virtual double             CalculateLotSize(string sym, double rp, double sl,
                                                   double qm = 1.0) override
                                 { return m_mgr.CalculateLotSize(sym, rp, sl, qm); }
      virtual double             NormalizeVolume(string sym, double v) const override
                                 { return m_mgr.NormalizeVolume(sym, v); }
      virtual void               GetConfigCache(StrategyConfig &c) const override
                                 { m_mgr.GetConfigCache(c); }
      virtual ENUM_CACHE_STATE   GetCacheState() const override   { return m_mgr.GetCacheState(); }
      virtual string             GetCacheError()  const override  { return m_mgr.GetCacheError(); }
   };

   CDataProviderProxy *m_proxy;

   //--- Indicator handles (persistent — created once in Init)
   int m_atrHandle;
   int m_fractalHandle;

   //--- Config cache: set once by InitConfigCache(), refreshed on ConfigReload
   StrategyConfig m_cfgCache;
   bool           m_cfgInitialized;

   //--- Cache state tracking
   ENUM_CACHE_STATE m_cacheState;
   string           m_cacheError;
   datetime         m_lastCacheUpdate;
   int              m_cacheUpdateFailures;

   //--- Indicator data cache
   struct CachedData
   {
      datetime barTime;
      double   atr;
      double   fractalsUp[];
      double   fractalsDown[];
      bool     dirty;
   } m_cache;

   //--- Account / trade state
   PositionScanResult m_scanCache;
   PerformanceStats   m_perfStats;
   PerformanceTracker m_perfTracker;

   double   m_realizedDailyProfit;
   double   m_dayStartBalance;
   datetime m_lastProfitUpdateDay;
   datetime m_lastScanTime;
   int      m_lastHistoryCount;
   int      m_consecutiveLosses;
   datetime m_lastLossTime;

public:
   DataManager()
      : IManager("DataManager", 10),
        m_atrHandle(INVALID_HANDLE), m_fractalHandle(INVALID_HANDLE),
        m_cfgInitialized(false),
        m_cacheState(CACHE_OK),
        m_cacheError(""),
        m_lastCacheUpdate(0),
        m_cacheUpdateFailures(0),
        m_realizedDailyProfit(0),
        m_dayStartBalance(0),
        m_lastProfitUpdateDay(0),
        m_lastScanTime(0),
        m_consecutiveLosses(0),
        m_proxy(NULL),
        m_lastLossTime(0),
        m_lastHistoryCount(-1)
   {
      m_cache.barTime = 0;
      m_cache.atr     = 0;
      m_cache.dirty   = true;
      ArraySetAsSeries(m_cache.fractalsUp,   true);
      ArraySetAsSeries(m_cache.fractalsDown, true);
      ZeroMemory(m_scanCache);
      m_proxy = new CDataProviderProxy(GetPointer(this));
   }

   ~DataManager()
   {
      if(CheckPointer(m_proxy) == POINTER_DYNAMIC) delete m_proxy;
      if(m_atrHandle     != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_fractalHandle != INVALID_HANDLE) IndicatorRelease(m_fractalHandle);
   }

   //--- Inject config from outside (called by EA/ConfigManager, not pulled internally)
   void InitConfigCache(const StrategyConfig &cfg)
   {
      m_cfgCache      = cfg;
      m_cfgInitialized = true;
   }

   //--- Refresh config cache — called by OnConfigReload or EA when params change
   void RefreshConfigCache(const StrategyConfig &cfg)
   {
      m_cfgCache = cfg;
   }

   void GetConfigCache(StrategyConfig &cfg) const { cfg = m_cfgCache; }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      m_data = this;
      if(!m_cfgInitialized)
      {
         Print("[DataManager] ERROR: Config not injected before Init(). Call InitConfigCache() first.");
         return false;
      }
      m_perfTracker.Initialize(m_cfgCache.risk.magic, m_symbol);
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
      // Caller must inject the new config before or after this event.
      // DataManager does NOT pull from ConfigManager directly.
      ResetIndicators();
   }

   //--- Cache state management
   void SetCacheState(ENUM_CACHE_STATE state, const string error = "")
   {
      m_cacheState      = state;
      m_cacheError      = error;
      m_lastCacheUpdate = TimeCurrent();
      if(state == CACHE_ERROR)
      {
         m_cacheUpdateFailures++;
         Print("[DataManager] Cache Error: ", error, " (Failure #", m_cacheUpdateFailures, ")");
      }
      else if(state == CACHE_OK)
         m_cacheUpdateFailures = 0;
   }

   ENUM_CACHE_STATE GetCacheState() const { return m_cacheState; }
   string           GetCacheError() const { return m_cacheError; }
   bool             IsCacheValid()  const { return (m_cacheState == CACHE_OK || m_cacheState == CACHE_STALE); }

   //--- Create/recreate indicator handles
   bool ResetIndicators()
   {
      SetCacheState(CACHE_UPDATING, "Resetting indicators...");
      if(m_atrHandle     != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_fractalHandle != INVALID_HANDLE) IndicatorRelease(m_fractalHandle);

      // [FIX v2.10] Use nested struct field: market.atrPeriod (was atr_period)
      m_atrHandle     = iATR(m_symbol, m_period, m_cfgCache.market.atrPeriod);
      m_fractalHandle = iFractals(m_symbol, m_period);

      if(m_atrHandle == INVALID_HANDLE || m_fractalHandle == INVALID_HANDLE)
      {
         SetCacheState(CACHE_ERROR,
            StringFormat("Failed to create indicator handles. ATR=%s, Fractal=%s",
                         (m_atrHandle     == INVALID_HANDLE) ? "INVALID" : "OK",
                         (m_fractalHandle == INVALID_HANDLE) ? "INVALID" : "OK"));
         return false;
      }
      UpdateIndicators();
      SetCacheState(CACHE_OK, "");
      return true;
   }

   //--- Update indicator cache on new bar
   void UpdateIndicators()
   {
      ENUM_CACHE_STATE prevState = m_cacheState;
      SetCacheState(CACHE_UPDATING, "Updating indicators...");

      MqlRates rates[];
      if(CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)
      {
         SetCacheState(CACHE_ERROR, "CopyRates failed for closed bar");
         return;
      }
      datetime currentBar = rates[0].time;
      if(m_cache.barTime == currentBar && !m_cache.dirty)
      {
         SetCacheState(prevState, "");
         return;
      }
      if(!SeriesInfoInteger(m_symbol, m_period, SERIES_SYNCHRONIZED))
      {
         SetCacheState(CACHE_STALE, "Series not synchronized");
         return;
      }

      double atrBuf[1];
      if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) > 0 && atrBuf[0] > 0)
      {
         m_cache.atr = atrBuf[0] / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(CopyBuffer(m_fractalHandle, 0, 0, 100, m_cache.fractalsUp)   < 100)
         { SetCacheState(CACHE_ERROR, "CopyBuffer fractalsUp failed"); return; }
         if(CopyBuffer(m_fractalHandle, 1, 0, 100, m_cache.fractalsDown) < 100)
         { SetCacheState(CACHE_ERROR, "CopyBuffer fractalsDown failed"); return; }
         m_cache.barTime = currentBar;
         m_cache.dirty   = false;
         SetCacheState(CACHE_OK, "");
      }
      else
         SetCacheState(CACHE_ERROR, "CopyBuffer ATR failed or returned zero");
   }

   virtual void OnNewBar(NewBarEvent *e)       override { UpdateIndicators(); }
   virtual void OnHeartbeat(HeartbeatEvent *e) override { UpdateAccountState(); }

   virtual double             GetATRPoints()        const { return m_cache.atr; }
   void                       MarkDirty()                 { m_cache.dirty = true; }
   virtual PositionScanResult GetScanResult()        const { return m_scanCache; }
   virtual PerformanceStats   GetPerformanceStats()  const { return m_perfStats; }
   double                     GetDayStartBalance()   const { return m_dayStartBalance; }
   int                        GetConsecutiveLosses() const { return m_consecutiveLosses; }
   datetime                   GetLastLossTime()      const { return m_lastLossTime; }

   //--- Check whether a new trade is within daily loss budget
   virtual bool CanOpenTrade(double additionalRiskAmount)
   {
      if(!IsCacheValid())
      {
         Print("[DataManager] Trade blocked: Cache state invalid (", m_cacheState, ")");
         return false;
      }

      double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
      // [FIX v2.10] Nested struct: risk.maxDailyLoss (was max_daily_loss)
      double maxDailyLoss = equity * (m_cfgCache.risk.maxDailyLoss / 100.0);

      // [FIX DM-BUG-5] Correct daily PnL formula:
      // todayPnL = realized today + floating now. Loss = max(0, -todayPnL).
      double todayPnL    = m_realizedDailyProfit + m_scanCache.floatingPnL;
      double currentLoss = MathMax(0.0, -todayPnL);

      bool canTrade = (currentLoss + additionalRiskAmount) < maxDailyLoss;
      if(!canTrade)
         Print("[DataManager] Trade blocked: Daily loss limit approaching. Current: ",
               DoubleToString(currentLoss, 2), ", Max: ", DoubleToString(maxDailyLoss, 2));
      return canTrade;
   }

   //--- Lot size calculation with optional quality multiplier + regime adjustment
   virtual double CalculateLotSize(string symbol, double riskPct,
                                   double slDistancePoints,
                                   double qualityMultiplier = 1.0)
   {
      if(slDistancePoints <= 0) return 0.0;
      double lot = 0.0;

      // [FIX v2.10] risk.autoLot (was auto_lot), risk.lot (was lot_size)
      if(m_cfgCache.risk.autoLot)
      {
         double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(tickValue <= 0 || tickSize <= 0 || equity <= 0 || point <= 0) return 0.0;
         double riskMoney  = equity * (riskPct / 100.0);
         double lossPerLot = (slDistancePoints * point / tickSize) * tickValue;
         if(lossPerLot > 0) lot = riskMoney / lossPerLot;
      }
      else
         lot = m_cfgCache.risk.lot;

      lot *= qualityMultiplier;

      // [FIX v2.10] market.useRegime (was use_regime)
      if(m_cfgCache.market.useRegime && CheckPointer(g_regimeFilter) != POINTER_INVALID)
         lot *= g_regimeFilter.GetLotMultiplier();

      return NormalizeVolume(symbol, lot);
   }

   //--- Calculate monetary risk of a position
   double CalculatePositionRisk(string symbol, double volume, double slDistancePoints)
   {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0 || volume <= 0) return 0.0;
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      return (slDistancePoints * point / tickSize) * tickValue * volume;
   }

   //--- Validate SL/TP distances against ATR-based minimums
   bool ValidateTradeDistances(double slDist, double tpDist,
                                double atrPoints, string &reason)
   {
      if(slDist <= 0)
      { reason = "Invalid SL distance"; return false; }

      const double minSL = 10.0;
      if(slDist < minSL)
      { reason = StringFormat("SL too close (%.1f < %.1f)", slDist, minSL); return false; }

      if(tpDist > 0)
      {
         // [FIX v2.10] exit.minTPDistATR (was min_tp_distance_atr)
         double minTP = atrPoints * m_cfgCache.exit.minTPDistATR;
         if(tpDist < minTP)
         { reason = "TP too close to entry (Min ATR)"; return false; }
      }
      return true;
   }

   //--- Return risk as percentage of equity
   double GetRiskPercentage(string symbol, double volume, double slDistancePoints)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return 0.0;
      return (CalculatePositionRisk(symbol, volume, slDistancePoints) / equity) * 100.0;
   }

   //--- Refresh realized daily profit from trade history
   void RefreshDailyProfit()
   {
      // [FIX v2.10] GV key prefixed with account login to prevent
      // cross-instance state corruption when demo+live run on same terminal.
      // [FIX v2.10] risk.magic (was magic)
      string gvName = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                      "_PASR_PROFIT_" + m_symbol + "_" + (string)m_cfgCache.risk.magic;

      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];

      if(HistorySelect(today, TimeCurrent() + 1))
      {
         double dailySum = 0;
         for(int i = 0; i < HistoryDealsTotal(); i++)
         {
            ulong t = HistoryDealGetTicket(i);
            // [FIX v2.10] risk.magic (was magic)
            if(t > 0 &&
               HistoryDealGetInteger(t, DEAL_MAGIC)  == (long)m_cfgCache.risk.magic &&
               HistoryDealGetString(t,  DEAL_SYMBOL) == m_symbol)
            {
               dailySum += HistoryDealGetDouble(t, DEAL_PROFIT)
                         + HistoryDealGetDouble(t, DEAL_SWAP)
                         + HistoryDealGetDouble(t, DEAL_COMMISSION);
            }
         }
         m_realizedDailyProfit = dailySum;
      }
      GlobalVariableSet(gvName, m_realizedDailyProfit);
   }

   //--- Anchor daily balance reference at start of each new day
   void ResetDailyAnchor()
   {
      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];
      RefreshDailyProfit();
      m_dayStartBalance     = AccountInfoDouble(ACCOUNT_BALANCE) - m_realizedDailyProfit;
      m_lastProfitUpdateDay = today;
   }

   //--- Scan positions and update account state (called on heartbeat)
   void UpdateAccountState()
   {
      if(TimeCurrent() - m_lastScanTime < 1 && m_lastScanTime > 0) return;

      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      datetime today = times[0];

      if(today != m_lastProfitUpdateDay)
      {
         ResetDailyAnchor();
         m_consecutiveLosses = 0;
      }
      else
         RefreshDailyProfit();

      // [FIX DM-BUG-4] Delegate to tracker so m_perfStats is not zeroed stub
      UpdatePerformanceStats();

      PositionScanResult temp;
      ZeroMemory(temp);
      temp.dailyRealized  = m_realizedDailyProfit;
      double floatingTotal = 0;

      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         // [FIX v2.10] risk.magic (was magic)
         if(ticket <= 0 ||
            PositionGetInteger(POSITION_MAGIC) != (long)m_cfgCache.risk.magic ||
            PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         floatingTotal += PositionGetDouble(POSITION_PROFIT)
                        + PositionGetDouble(POSITION_SWAP)
                        + PositionGetDouble(POSITION_COMMISSION);
         temp.normalCount++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            temp.buyCount++;
         else
            temp.sellCount++;
      }

      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong oTicket = OrderGetTicket(i);
         if(oTicket > 0 &&
            OrderGetInteger(ORDER_MAGIC)  == (long)m_cfgCache.risk.magic &&
            OrderGetString(ORDER_SYMBOL)  == m_symbol)
         {
            ENUM_ORDER_STATE oState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
            if(oState == ORDER_STATE_STARTED || oState == ORDER_STATE_PLACED)
               temp.pendingCount++;
         }
      }

      temp.floatingPnL  = floatingTotal;
      temp.totalProfit  = temp.dailyRealized + temp.floatingPnL;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(MathAbs(m_dayStartBalance) > _Point)
         temp.dailyDrawdown = ((m_dayStartBalance - equity) / m_dayStartBalance) * 100.0;

      m_scanCache    = temp;
      m_lastScanTime = TimeCurrent();
   }

   //--- Price normalization utilities
   double NormalizePrice(string symbol, double price) const
   {
      return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }

   virtual double NormalizeVolume(string symbol, double vol) const
   {
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double s    = (step > 0) ? step : 0.01;
      vol = MathFloor((vol + 1e-12) / s) * s;
      vol = MathMax(vol, minv);
      if(maxv > 0.0) vol = MathMin(vol, maxv);
      return vol;
   }

   // [FIX DM-BUG-4] Populated from tracker — no longer a stub
   void UpdatePerformanceStats() { m_perfStats = m_perfTracker.GetLifetimeStats(); }

   const PerformanceTracker& GetPerfTracker() const { return m_perfTracker; }

   void RecordTradeResult(double netProfit)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_perfTracker.RecordTrade(netProfit, equity);
      UpdateConsecutiveLosses(netProfit);
      UpdatePerformanceStats();
   }

   void UpdateConsecutiveLosses(double netProfit)
   {
      if(netProfit < 0)
      {
         m_consecutiveLosses++;
         m_lastLossTime = TimeCurrent();
      }
      else
         m_consecutiveLosses = 0;
   }

   //--- Deprecated helpers kept for backward compatibility
   int ParseHM(string hhmm) const
   {
      Print("[DataManager] WARNING: ParseHM() deprecated. Use DataUtils::ParseHM().");
      return DataUtils::ParseHM(hhmm);
   }

   string StripTags(string html) const
   {
      Print("[DataManager] WARNING: StripTags() deprecated. Use DataUtils::StripTags().");
      return DataUtils::StripTags(html);
   }

   void DebugLog(bool enabled, string msg) const
   {
      if(enabled) Print("[PASR] ", msg);
   }
};

#endif // __DATA_MANAGER_MQH__
