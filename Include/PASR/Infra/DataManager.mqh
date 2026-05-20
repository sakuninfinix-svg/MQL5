//+------------------------------------------------------------------+
//|                                      Infra/DataManager.mqh      |
//|                          Copyright 2026, Agsicentre             |
//|   PASR Layer 2 — Infrastructure / Data Management               |
//|   Migrated from: 10.DataManager.mqh v2.10                       |
//|                                                                  |
//|   LAYER RULES (enforced):                                        |
//|     ✅ Depends on: Core/ only (IManager, Config.Types)           |
//|     ❌ Must NOT include: Config.Manager, SignalManager,          |
//|                          ExecutionManager, AI, UI               |
//|     ✅ Config injected via InitConfigCache() — never pulled      |
//|     ✅ GV keys prefixed with ACCOUNT_LOGIN (PASR-BUG-001 fix)   |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "3.00"
#property strict

#ifndef __INFRA_DATA_MANAGER_MQH__
#define __INFRA_DATA_MANAGER_MQH__

#include "../IManager.mqh"
#include "../2.Config.Types.mqh"
// NOTE: 2.Config.Manager.mqh intentionally NOT included (layering rule L2 > L1 only)
// NOTE: 12.MarketRegime.mqh intentionally NOT included (circular dep risk)
//       MarketRegimeFilter accessed via extern pointer g_regimeFilter (forward declared below)

//+------------------------------------------------------------------+
//| DataUtils — pure static utility functions, no state             |
//+------------------------------------------------------------------+
class DataUtils
{
public:
   static int ParseHM(const string hm)
   {
      string parts[];
      if(StringSplit(hm, ':', parts) != 2) return -1;
      int h = (int)StringToInteger(parts[0]);
      int m = (int)StringToInteger(parts[1]);
      if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
      return h * 60 + m;
   }

   static string StripTags(const string input)
   {
      string result = input;
      int start = StringFind(result, "<");
      while(start >= 0)
      {
         int end = StringFind(result, ">", start);
         if(end < 0) break;
         result = StringSubstr(result, 0, start) + StringSubstr(result, end + 1);
         start  = StringFind(result, "<");
      }
      return result;
   }

   static string BuildComment(const string title, const string content)
   {
      return "<b>" + title + "</b>\n" + content;
   }
};

//+------------------------------------------------------------------+
//| PerformanceTracker — sliding window trade statistics             |
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
         grossProfit = 0.0;
         grossLoss   = 0.0;
         maxDrawdown = 0.0;
         peakEquity  = 0.0;
      }
   };

   StatWindow m_lifetime;
   StatWindow m_session;
   StatWindow m_rolling7d;
   StatWindow m_rolling30d;
   datetime   m_lastUpdate;

   void UpdateWindow(StatWindow &win, double profit, double equity)
   {
      win.totalTrades++;
      if(profit > 0) win.grossProfit += profit;
      else           win.grossLoss   += MathAbs(profit);
      if(equity > win.peakEquity) win.peakEquity = equity;
      double dd = win.peakEquity - equity;
      if(dd > win.maxDrawdown) win.maxDrawdown = dd;
   }

   // FIX DM-BUG-4: sliding window preserves relative start time
   void CheckRollingWindows()
   {
      datetime now = TimeCurrent();
      if(now - m_rolling7d.startTime  > 7  * 86400) m_rolling7d.Reset(now  - 7  * 86400);
      if(now - m_rolling30d.startTime > 30 * 86400) m_rolling30d.Reset(now - 30 * 86400);
   }

public:
   PerformanceTracker() : m_magic(0), m_symbol(""), m_lastUpdate(0)
   {
      datetime now = TimeCurrent();
      m_lifetime.Reset(now); m_session.Reset(now);
      m_rolling7d.Reset(now); m_rolling30d.Reset(now);
   }

   void Initialize(ulong magic, const string symbol)
   {
      m_magic  = magic;
      m_symbol = symbol;
      datetime now = TimeCurrent();
      m_lifetime.Reset(now); m_session.Reset(now);
      m_rolling7d.Reset(now); m_rolling30d.Reset(now);
   }

   void RecordTrade(double profit, double equity)
   {
      CheckRollingWindows();
      UpdateWindow(m_lifetime,   profit, equity);
      UpdateWindow(m_session,    profit, equity);
      UpdateWindow(m_rolling7d,  profit, equity);
      UpdateWindow(m_rolling30d, profit, equity);
      m_lastUpdate = TimeCurrent();
   }

   void ResetSession() { m_session.Reset(TimeCurrent()); }

   PerformanceStats GetLifetimeStats() const
   {
      PerformanceStats s;
      s.safeTotal = m_lifetime.totalTrades;
      s.safeWins  = (int)m_lifetime.grossProfit;  // proxy; use grossProfit for accuracy
      s.aggTotal  = 0;
      s.aggWins   = 0;
      return s;
   }

   PerformanceStats GetSessionStats() const
   {
      PerformanceStats s;
      s.safeTotal = m_session.totalTrades;
      s.safeWins  = 0; s.aggTotal = 0; s.aggWins = 0;
      return s;
   }

   datetime GetLastUpdate() const { return m_lastUpdate; }
};

//+------------------------------------------------------------------+
//| Forward declaration — avoids circular include with MarketRegime  |
//+------------------------------------------------------------------+
class MarketRegimeFilter;
extern MarketRegimeFilter *g_regimeFilter;

//+------------------------------------------------------------------+
//| Cache state enum                                                 |
//+------------------------------------------------------------------+
enum ENUM_CACHE_STATE
{
   CACHE_OK,
   CACHE_STALE,
   CACHE_INVALID,
   CACHE_UPDATING,
   CACHE_ERROR
};

//+------------------------------------------------------------------+
//| IDataProvider interface — enables dependency injection           |
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
//| DataManager — L2 Infra, implements IDataProvider                |
//+------------------------------------------------------------------+
class DataManager : public IManager
{
private:
   //--- Inner proxy for IDataProvider interface
   class CDataProviderProxy : public IDataProvider
   {
   private:
      DataManager *m_mgr;
   public:
      CDataProviderProxy(DataManager *mgr) : m_mgr(mgr) {}
      virtual double             GetATRPoints()    const override { return m_mgr.GetATRPoints(); }
      virtual PositionScanResult GetScanResult()   const override { return m_mgr.GetScanResult(); }
      virtual PerformanceStats   GetPerformanceStats() const override { return m_mgr.GetPerformanceStats(); }
      virtual bool               CanOpenTrade(double r)  override { return m_mgr.CanOpenTrade(r); }
      virtual double             CalculateLotSize(string sym, double rp, double sl,
                                                   double qm = 1.0) override
                                 { return m_mgr.CalculateLotSize(sym, rp, sl, qm); }
      virtual double             NormalizeVolume(string sym, double v) const override
                                 { return m_mgr.NormalizeVolume(sym, v); }
      virtual void               GetConfigCache(StrategyConfig &c) const override
                                 { m_mgr.GetConfigCache(c); }
      virtual ENUM_CACHE_STATE   GetCacheState() const override { return m_mgr.GetCacheState(); }
      virtual string             GetCacheError()  const override { return m_mgr.GetCacheError(); }
   };

   CDataProviderProxy *m_proxy;

   int            m_atrHandle;
   int            m_fractalHandle;
   StrategyConfig m_cfgCache;
   bool           m_cfgInitialized;
   ENUM_CACHE_STATE m_cacheState;
   string           m_cacheError;
   datetime         m_lastCacheUpdate;
   int              m_cacheUpdateFailures;

   struct CachedData
   {
      datetime barTime;
      double   atr;
      double   fractalsUp[];
      double   fractalsDown[];
      bool     dirty;
   } m_cache;

   PositionScanResult m_scanCache;
   PerformanceStats   m_perfStats;
   PerformanceTracker m_perfTracker;
   double             m_realizedDailyProfit;
   double             m_dayStartBalance;
   datetime           m_lastProfitUpdateDay;
   datetime           m_lastScanTime;
   int                m_lastHistoryCount;
   int                m_consecutiveLosses;
   datetime           m_lastLossTime;

public:
   DataManager()
      : IManager("DataManager", 10),
        m_atrHandle(INVALID_HANDLE), m_fractalHandle(INVALID_HANDLE),
        m_cfgInitialized(false),
        m_cacheState(CACHE_OK), m_cacheError(""), m_lastCacheUpdate(0),
        m_cacheUpdateFailures(0), m_realizedDailyProfit(0.0),
        m_dayStartBalance(0.0), m_lastProfitUpdateDay(0),
        m_lastScanTime(0), m_consecutiveLosses(0),
        m_proxy(NULL), m_lastLossTime(0), m_lastHistoryCount(-1)
   {
      m_cache.barTime = 0;
      m_cache.atr     = 0.0;
      m_cache.dirty   = true;
      ArraySetAsSeries(m_cache.fractalsUp,   true);
      ArraySetAsSeries(m_cache.fractalsDown, true);
      ZeroMemory(m_scanCache);
      m_proxy = new CDataProviderProxy(GetPointer(this));
   }

   ~DataManager()
   {
      if(CheckPointer(m_proxy)       == POINTER_DYNAMIC) delete m_proxy;
      if(m_atrHandle     != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_fractalHandle != INVALID_HANDLE) IndicatorRelease(m_fractalHandle);
   }

   //--- Config injection (L1 caller must call this before Init)
   void InitConfigCache(const StrategyConfig &cfg)   { m_cfgCache = cfg; m_cfgInitialized = true; }
   void RefreshConfigCache(const StrategyConfig &cfg) { m_cfgCache = cfg; }
   void GetConfigCache(StrategyConfig &cfg) const     { cfg = m_cfgCache; }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      m_data = this;
      if(!m_cfgInitialized)
      {
         Print("[DataManager] FATAL: InitConfigCache() must be called before Init()");
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
      ResetIndicators();
   }

   //--- Cache state
   void SetCacheState(ENUM_CACHE_STATE state, const string error = "")
   {
      m_cacheState      = state;
      m_cacheError      = error;
      m_lastCacheUpdate = TimeCurrent();
      if(state == CACHE_ERROR)
      {
         m_cacheUpdateFailures++;
         PrintFormat("[DataManager] Cache Error #%d: %s", m_cacheUpdateFailures, error);
      }
      else if(state == CACHE_OK)
         m_cacheUpdateFailures = 0;
   }

   ENUM_CACHE_STATE GetCacheState() const { return m_cacheState; }
   string           GetCacheError() const { return m_cacheError; }
   bool             IsCacheValid()  const { return (m_cacheState == CACHE_OK || m_cacheState == CACHE_STALE); }

   bool ResetIndicators()
   {
      SetCacheState(CACHE_UPDATING, "Resetting indicators...");
      if(m_atrHandle     != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      if(m_fractalHandle != INVALID_HANDLE) IndicatorRelease(m_fractalHandle);
      m_atrHandle     = iATR(m_symbol, m_period, m_cfgCache.market.atrPeriod);
      m_fractalHandle = iFractals(m_symbol, m_period);
      if(m_atrHandle == INVALID_HANDLE || m_fractalHandle == INVALID_HANDLE)
      {
         SetCacheState(CACHE_ERROR, StringFormat("Indicator handles failed. ATR=%s Fractal=%s",
            m_atrHandle     == INVALID_HANDLE ? "INVALID" : "OK",
            m_fractalHandle == INVALID_HANDLE ? "INVALID" : "OK"));
         return false;
      }
      UpdateIndicators();
      SetCacheState(CACHE_OK, "");
      return true;
   }

   void UpdateIndicators()
   {
      ENUM_CACHE_STATE prevState = m_cacheState;
      SetCacheState(CACHE_UPDATING, "Updating indicators...");
      MqlRates rates[];
      if(CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)
      { SetCacheState(CACHE_ERROR, "CopyRates failed"); return; }
      datetime bar = rates[0].time;
      if(m_cache.barTime == bar && !m_cache.dirty)
      { SetCacheState(prevState, ""); return; }
      if(!SeriesInfoInteger(m_symbol, m_period, SERIES_SYNCHRONIZED))
      { SetCacheState(CACHE_STALE, "Series not synchronized"); return; }
      double atrBuf[1];
      if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) > 0 && atrBuf[0] > 0)
      {
         m_cache.atr = atrBuf[0] / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         if(CopyBuffer(m_fractalHandle, 0, 0, 100, m_cache.fractalsUp)   < 100)
         { SetCacheState(CACHE_ERROR, "CopyBuffer fractalsUp failed"); return; }
         if(CopyBuffer(m_fractalHandle, 1, 0, 100, m_cache.fractalsDown) < 100)
         { SetCacheState(CACHE_ERROR, "CopyBuffer fractalsDown failed"); return; }
         m_cache.barTime = bar;
         m_cache.dirty   = false;
         SetCacheState(CACHE_OK, "");
      }
      else SetCacheState(CACHE_ERROR, "CopyBuffer ATR failed or returned zero");
   }

   virtual void OnNewBar(NewBarEvent *e)       override { UpdateIndicators(); }
   virtual void OnHeartbeat(HeartbeatEvent *e) override { UpdateAccountState(); }

   virtual double             GetATRPoints()       const { return m_cache.atr; }
   void                       MarkDirty()                { m_cache.dirty = true; }
   virtual PositionScanResult GetScanResult()       const { return m_scanCache; }
   virtual PerformanceStats   GetPerformanceStats() const { return m_perfStats; }
   double                     GetDayStartBalance()  const { return m_dayStartBalance; }
   int                        GetConsecutiveLosses()const { return m_consecutiveLosses; }
   datetime                   GetLastLossTime()     const { return m_lastLossTime; }

   virtual bool CanOpenTrade(double additionalRiskAmount)
   {
      if(!IsCacheValid())
      { PrintFormat("[DataManager] Trade blocked: cache invalid (%d)", m_cacheState); return false; }
      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double maxLoss   = equity * (m_cfgCache.risk.maxDailyLoss / 100.0);
      // FIX DM-BUG-5: todayPnL = realized + floating; loss = max(0, -pnl)
      double todayPnL  = m_realizedDailyProfit + m_scanCache.floatingPnL;
      double curLoss   = MathMax(0.0, -todayPnL);
      bool   ok        = (curLoss + additionalRiskAmount) < maxLoss;
      if(!ok)
         PrintFormat("[DataManager] Trade blocked: dailyLoss=%.2f maxLoss=%.2f", curLoss, maxLoss);
      return ok;
   }

   virtual double CalculateLotSize(string symbol, double riskPct,
                                   double slDistancePoints, double qualityMultiplier = 1.0)
   {
      if(slDistancePoints <= 0) return 0.0;
      double lot = 0.0;
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
      else lot = m_cfgCache.risk.lot;
      lot *= qualityMultiplier;
      if(m_cfgCache.market.useRegime && CheckPointer(g_regimeFilter) != POINTER_INVALID)
         lot *= g_regimeFilter.GetLotMultiplier();
      return NormalizeVolume(symbol, lot);
   }

   double CalculatePositionRisk(string symbol, double volume, double slDistancePoints)
   {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0 || tickSize <= 0 || volume <= 0) return 0.0;
      return (slDistancePoints * SymbolInfoDouble(symbol, SYMBOL_POINT) / tickSize) * tickValue * volume;
   }

   bool ValidateTradeDistances(double slDist, double tpDist, double atrPoints, string &reason)
   {
      if(slDist <= 0)  { reason = "Invalid SL distance"; return false; }
      if(slDist < 10.0){ reason = StringFormat("SL too close (%.1f < 10)", slDist); return false; }
      if(tpDist > 0)
      {
         double minTP = atrPoints * m_cfgCache.exit.minTPDistATR;
         if(tpDist < minTP) { reason = "TP too close (Min ATR)"; return false; }
      }
      return true;
   }

   double GetRiskPercentage(string symbol, double volume, double slDistancePoints)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return 0.0;
      return (CalculatePositionRisk(symbol, volume, slDistancePoints) / equity) * 100.0;
   }

   void RefreshDailyProfit()
   {
      // FIX PASR-BUG-001: prefix GV key with account login
      string gvName = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
                    + "_PASR_PROFIT_" + m_symbol + "_" + (string)m_cfgCache.risk.magic;
      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      if(HistorySelect(times[0], TimeCurrent() + 1))
      {
         double sum = 0.0;
         for(int i = 0; i < HistoryDealsTotal(); i++)
         {
            ulong t = HistoryDealGetTicket(i);
            if(t > 0 &&
               HistoryDealGetInteger(t, DEAL_MAGIC)  == (long)m_cfgCache.risk.magic &&
               HistoryDealGetString(t,  DEAL_SYMBOL) == m_symbol)
               sum += HistoryDealGetDouble(t, DEAL_PROFIT)
                    + HistoryDealGetDouble(t, DEAL_SWAP)
                    + HistoryDealGetDouble(t, DEAL_COMMISSION);
         }
         m_realizedDailyProfit = sum;
      }
      GlobalVariableSet(gvName, m_realizedDailyProfit);
   }

   void ResetDailyAnchor()
   {
      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      RefreshDailyProfit();
      m_dayStartBalance     = AccountInfoDouble(ACCOUNT_BALANCE) - m_realizedDailyProfit;
      m_lastProfitUpdateDay = times[0];
   }

   void UpdateAccountState()
   {
      if(TimeCurrent() - m_lastScanTime < 1 && m_lastScanTime > 0) return;
      datetime times[];
      if(CopyTime(m_symbol, PERIOD_D1, 0, 1, times) <= 0) return;
      if(times[0] != m_lastProfitUpdateDay) { ResetDailyAnchor(); m_consecutiveLosses = 0; }
      else RefreshDailyProfit();
      UpdatePerformanceStats();
      PositionScanResult temp;
      ZeroMemory(temp);
      temp.dailyRealized = m_realizedDailyProfit;
      double floating    = 0.0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong t = PositionGetTicket(i);
         if(t <= 0 ||
            PositionGetInteger(POSITION_MAGIC) != (long)m_cfgCache.risk.magic ||
            PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         floating += PositionGetDouble(POSITION_PROFIT)
                   + PositionGetDouble(POSITION_SWAP)
                   + PositionGetDouble(POSITION_COMMISSION);
         temp.normalCount++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) temp.buyCount++;
         else temp.sellCount++;
      }
      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong t = OrderGetTicket(i);
         if(t > 0 &&
            OrderGetInteger(ORDER_MAGIC)  == (long)m_cfgCache.risk.magic &&
            OrderGetString(ORDER_SYMBOL)  == m_symbol)
         {
            ENUM_ORDER_STATE os = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
            if(os == ORDER_STATE_STARTED || os == ORDER_STATE_PLACED) temp.pendingCount++;
         }
      }
      temp.floatingPnL = floating;
      temp.totalProfit = temp.dailyRealized + floating;
      if(MathAbs(m_dayStartBalance) > _Point)
         temp.dailyDrawdown = ((m_dayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY))
                               / m_dayStartBalance) * 100.0;
      m_scanCache    = temp;
      m_lastScanTime = TimeCurrent();
   }

   double NormalizePrice(string symbol, double price) const
   { return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)); }

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

   void UpdatePerformanceStats() { m_perfStats = m_perfTracker.GetLifetimeStats(); }

   const PerformanceTracker& GetPerfTracker() const { return m_perfTracker; }

   void RecordTradeResult(double netProfit)
   {
      m_perfTracker.RecordTrade(netProfit, AccountInfoDouble(ACCOUNT_EQUITY));
      if(netProfit < 0) { m_consecutiveLosses++; m_lastLossTime = TimeCurrent(); }
      else m_consecutiveLosses = 0;
      UpdatePerformanceStats();
   }

   //--- Deprecated shims (emit warning + delegate to DataUtils)
   int    ParseHM(string s)  const { Print("[DataManager] DEPRECATED: use DataUtils::ParseHM()");  return DataUtils::ParseHM(s); }
   string StripTags(string s) const { Print("[DataManager] DEPRECATED: use DataUtils::StripTags()"); return DataUtils::StripTags(s); }
   void   DebugLog(bool en, string msg) const { if(en) Print("[PASR] ", msg); }
};

#endif // __INFRA_DATA_MANAGER_MQH__
