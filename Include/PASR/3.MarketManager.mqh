//+------------------------------------------------------------------+
//|                                              3.MarketManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Market State & Session Management Module              |
//|                   V2.2 - Audit Patch                             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.20"
#property strict

#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"

enum ENUM_NEWS_IMPACT
{
   NEWS_IMPACT_NONE = 0,
   NEWS_IMPACT_LOW,
   NEWS_IMPACT_MEDIUM,
   NEWS_IMPACT_HIGH
};

struct SessionInfo
{
   int  startMin;
   int  endMin;
   bool isActive;
   bool isOverlap;
   int  overlapWithIndex;
   int  minutesToClose;
};

// FIX (MM-BUG-4): Circular buffer for spread history — replaces O(N) ArrayCopy self-overlap
struct SpreadTrend
{
   double   spreads[20];  // Fixed-size circular buffer
   int      head;         // Next write index
   int      count;        // Valid samples (0..20)
   double   sma;
   double   slope;
   datetime lastUpdate;

   SpreadTrend() : head(0), count(0), sma(0.0), slope(0.0), lastUpdate(0)
   {
      ArrayInitialize(spreads, 0.0);
   }
};

class MarketManager : public IManager
{
private:
   string m_baseCurr;
   string m_profitCurr;

   double   m_avgSpread;
   double   m_tickSize;
   int      m_digits;
   datetime m_lastSpreadUpdate;

   double m_atrH1Baseline;
   double m_timeframeFactor;

   SessionInfo m_sessions[7];
   int  m_sessionStarts[7];
   int  m_sessionEnds[7];
   bool m_overlapDetected;
   int  m_activeSessionIndex;

   ENUM_NEWS_IMPACT m_newsImpact;
   datetime         m_newsImpactExpiry;

   SpreadTrend m_spreadTrend;
   bool        m_spreadWarningActive;

   MarketRegimeFilter    *m_regimeFilter;
   MultiTFRegimeContext   m_lastRegimeContext;
   datetime               m_lastRegimeCheck;

   string   m_newsStatus;
   datetime m_nextNewsTime;
   datetime m_lastBarTime;
   datetime m_dayAnchor;
   datetime m_lastNewsCheck;
   bool     m_lastNewsResult;
   datetime m_lastWebFetch;
   datetime m_webNewsTimes[];
   datetime m_lastEntryBarTime;
   datetime m_lastLossBarTime;
   int      m_consecutiveLosses;

   bool     m_gateOpen;
   bool     m_entryAllowed;
   double   m_lastSpread;
   double   m_lastATR;
   MqlTick  m_lastTick;
   bool     m_hasLastTick;

   void FetchWebNews();
   void UpdateGateState(const MqlTick &tick);
   void UpdateInstrumentContext();
   void UpdateSpreadTrend(double currentSpread);
   ENUM_NEWS_IMPACT CalculateNewsImpact();
   void DetectSessionOverlaps();
   bool CheckRegimeCompatibility();
   double NormalizeATR(double atr, ENUM_TIMEFRAMES tf);

public:
   MarketManager() : IManager("MarketManager", 100),
                     m_gateOpen(true),
                     m_entryAllowed(true),
                     m_lastSpread(0.0),
                     m_lastATR(0.0),
                     m_hasLastTick(false),
                     m_avgSpread(0.0),
                     m_tickSize(0.0),
                     m_digits(0),
                     m_atrH1Baseline(0.0),
                     m_timeframeFactor(1.0),
                     m_overlapDetected(false),
                     m_activeSessionIndex(-1),
                     m_newsImpact(NEWS_IMPACT_NONE),
                     m_newsImpactExpiry(0),
                     m_spreadWarningActive(false),
                     m_regimeFilter(NULL),
                     m_lastRegimeCheck(0)
   {
      m_baseCurr   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      m_profitCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      ZeroMemory(m_sessionStarts);
      ZeroMemory(m_sessionEnds);
      ZeroMemory(m_lastTick);
      ZeroMemory(m_sessions);
   }

   ~MarketManager();

   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
      UpdateInstrumentContext();
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      RefreshConfigCache();
      if(m_regimeFilter != NULL) { delete m_regimeFilter; m_regimeFilter = NULL; }
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_REGIME_CHANGE);
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override;
   virtual void OnNewBar(NewBarEvent *e) override;
   virtual void OnHeartbeat(HeartbeatEvent *e) override;

   virtual bool Init() override;

   bool PassesGate(const MqlTick &tick, double &currentSpread, double currentATR);
   bool PassesGateWithContext(const MqlTick &tick, double &currentSpread, double currentATR);

   bool       IsTradingSession();
   bool       IsSessionOverlap();
   int        GetMinutesToSessionClose();
   SessionInfo GetCurrentSessionInfo();

   bool             IsNewsTime();
   ENUM_NEWS_IMPACT GetNewsImpact()    const { return m_newsImpact; }
   string           GetNewsStatus()    const { return m_newsStatus; }
   datetime         GetNextNewsTime()  const { return m_nextNewsTime; }

   double GetAverageSpread()         const { return m_avgSpread; }
   bool   IsSpreadTrendWidening()    const { return m_spreadTrend.slope > 0.5; }
   bool   IsSpreadWarningActive()    const { return m_spreadWarningActive; }

   double GetNormalizedATR(double currentATR) const;

   bool               IsRegimeCompatible();
   MultiTFRegimeContext GetCurrentRegime();

   bool IsEntryCooldownActive();
   void UpdateLossStreak(double netProfit);

   void UpdateLastEntryBarTime(datetime time) { m_lastEntryBarTime = time; }
   void SetLastBarTime(datetime time)         { m_lastBarTime = time; }
};

//--- Destructor
MarketManager::~MarketManager()
{
   ArrayFree(m_webNewsTimes);
   if(m_regimeFilter != NULL) { delete m_regimeFilter; m_regimeFilter = NULL; }
}

//+------------------------------------------------------------------+
//| UpdateInstrumentContext                                          |
//| FIX (MM-BUG-1): CopyTick fills MqlTick[], NOT double[].         |
//| Replaced with SymbolInfoInteger(SYMBOL_SPREAD) rolling average.  |
//+------------------------------------------------------------------+
void MarketManager::UpdateInstrumentContext()
{
   m_digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   m_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Use live spread as current sample; rolling average maintained via UpdateSpreadTrend
   double currentSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread > 0)
   {
      // Seed average with current spread if no history yet
      if(m_spreadTrend.count == 0)
         m_avgSpread = currentSpread;
      else
      {
         // Exponential moving average (alpha=0.1) for stable baseline
         m_avgSpread = m_avgSpread * 0.9 + currentSpread * 0.1;
      }
   }

   // Timeframe normalization factor
   long tfSeconds  = PeriodSeconds();
   m_timeframeFactor = MathSqrt(tfSeconds / 3600.0);
   m_lastSpreadUpdate = TimeCurrent();

   if(m_debugMode)
      PrintFormat("[%s] Instrument Context: %s, Digits=%d, TickSize=%.5f, AvgSpread=%.2f pts, TF Factor=%.2f",
                  m_name, _Symbol, m_digits, m_tickSize, m_avgSpread, m_timeframeFactor);
}

double MarketManager::NormalizeATR(double atr, ENUM_TIMEFRAMES tf)
{
   if(atr <= 0) return 0.0;
   long   tfSeconds = PeriodSeconds(tf);
   double factor    = MathSqrt(tfSeconds / 3600.0);
   return atr / factor;
}

double MarketManager::GetNormalizedATR(double currentATR) const
{
   if(currentATR <= 0) return 0.0;
   return currentATR / m_timeframeFactor;
}

//+------------------------------------------------------------------+
//| UpdateSpreadTrend                                                |
//| FIX (MM-BUG-4): True circular buffer — no array copies.         |
//+------------------------------------------------------------------+
void MarketManager::UpdateSpreadTrend(double currentSpread)
{
   // Write into circular buffer
   m_spreadTrend.spreads[m_spreadTrend.head] = currentSpread;
   m_spreadTrend.head = (m_spreadTrend.head + 1) % 20;
   if(m_spreadTrend.count < 20) m_spreadTrend.count++;

   int n = m_spreadTrend.count;

   // SMA over valid samples
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += m_spreadTrend.spreads[i];
   m_spreadTrend.sma = sum / n;

   // Linear regression slope over last min(10, n) samples
   if(n >= 5)
   {
      int    samples = MathMin(10, n);
      double xSum = 0, ySum = 0, xySum = 0, xxSum = 0;

      // Walk backward from newest: newest = head-1 (mod 20)
      for(int i = 0; i < samples; i++)
      {
         int    idx = (m_spreadTrend.head - 1 - i + 20) % 20;
         double x   = (double)i;
         double y   = m_spreadTrend.spreads[idx];
         xSum  += x;
         ySum  += y;
         xySum += x * y;
         xxSum += x * x;
      }

      double denom = samples * xxSum - xSum * xSum;
      if(denom != 0.0)
         m_spreadTrend.slope = (samples * xySum - xSum * ySum) / denom;
   }

   m_spreadTrend.lastUpdate = TimeCurrent();

   if(m_spreadTrend.slope > 1.0 && !m_spreadWarningActive)
   {
      m_spreadWarningActive = true;
      if(m_debugMode)
         PrintFormat("[%s] WARNING: Spread trending upward (slope=%.2f). Current: %.1f, SMA: %.1f",
                     m_name, m_spreadTrend.slope, currentSpread, m_spreadTrend.sma);
   }
   else if(m_spreadTrend.slope < 0.3)
      m_spreadWarningActive = false;
}

void MarketManager::DetectSessionOverlaps()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currMin = now.hour * 60 + now.min;

   m_overlapDetected    = false;
   m_activeSessionIndex = -1;

   for(int i = 0; i < 7; i++)
   {
      m_sessions[i].isActive          = false;
      m_sessions[i].isOverlap         = false;
      m_sessions[i].overlapWithIndex  = -1;
      m_sessions[i].minutesToClose    = 0;
   }

   int activeCount = 0;
   int activeIndices[7];

   for(int i = 0; i < 7; i++)
   {
      if(m_sessionStarts[i] < 0) continue;

      bool isActive;
      if(m_sessionStarts[i] == 0 && m_sessionEnds[i] == 1440)
         isActive = true;
      else if(m_sessionStarts[i] <= m_sessionEnds[i])
         isActive = (currMin >= m_sessionStarts[i] && currMin <= m_sessionEnds[i]);
      else
         isActive = (currMin >= m_sessionStarts[i] || currMin <= m_sessionEnds[i]);

      if(isActive)
      {
         m_sessions[i].isActive  = true;
         m_sessions[i].startMin  = m_sessionStarts[i];
         m_sessions[i].endMin    = m_sessionEnds[i];
         m_sessions[i].minutesToClose = (m_sessionEnds[i] >= currMin)
            ? m_sessionEnds[i] - currMin
            : (1440 - currMin) + m_sessionEnds[i];

         activeIndices[activeCount] = i;
         activeCount++;
         if(m_activeSessionIndex < 0) m_activeSessionIndex = i;
      }
   }

   if(activeCount > 1)
   {
      m_overlapDetected = true;
      for(int i = 0; i < activeCount; i++)
      {
         int idx = activeIndices[i];
         m_sessions[idx].isOverlap = true;
         if(i < activeCount - 1)
            m_sessions[idx].overlapWithIndex = activeIndices[i + 1];
      }
      if(m_debugMode)
         PrintFormat("[%s] Session Overlap Detected! %d active sessions", m_name, activeCount);
   }
}

bool MarketManager::Init()
{
   if(!IManager::Init()) return false;

   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   UpdateInstrumentContext();

   for(int i = 0; i < 7; i++)
   {
      string session = cfg.sessions[i];
      if(session == "0" || session == "")
      {
         m_sessionStarts[i] = -1;
         m_sessionEnds[i]   = -1;
      }
      else if(session == "00:00-24:00")
      {
         m_sessionStarts[i] = 0;
         m_sessionEnds[i]   = 1440;
      }
      else
      {
         string parts[];
         if(StringSplit(session, '-', parts) == 2)
         {
            m_sessionStarts[i] = m_data.ParseHM(parts[0]);
            m_sessionEnds[i]   = m_data.ParseHM(parts[1]);
         }
         else
         {
            m_sessionStarts[i] = 0;
            m_sessionEnds[i]   = 1440;
         }
      }
   }

   m_regimeFilter = new MarketRegimeFilter();
   if(m_regimeFilter != NULL)
      m_regimeFilter.Init(_Symbol, PERIOD_CURRENT, PERIOD_H4, PERIOD_D1);

   return true;
}

bool MarketManager::PassesGate(const MqlTick &tick, double &currentSpread, double currentATR)
{
   return PassesGateWithContext(tick, currentSpread, currentATR);
}

//+------------------------------------------------------------------+
//| PassesGateWithContext                                            |
//| FIX (MM-BUG-3): DetectSessionOverlaps called ONCE at top.       |
//| Previously called twice: explicitly here + inside IsTradingSession|
//+------------------------------------------------------------------+
bool MarketManager::PassesGateWithContext(const MqlTick &tick, double &currentSpread, double currentATR)
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);

   // Detect overlaps once — shared by IsTradingSession and session close warning
   DetectSessionOverlaps();

   // 1. Session check
   if(!IsTradingSession())
   {
      m_data.DebugLog(m_debugMode, "Trading session is closed.");
      return false;
   }

   // 2. Spread
   double bid = tick.bid;
   double ask = tick.ask;
   currentSpread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   UpdateSpreadTrend(currentSpread);

   double dynamicSpreadThreshold = MathMax(cfg.max_spread, m_avgSpread * 2.5);
   if(currentSpread > dynamicSpreadThreshold)
   {
      m_data.DebugLog(m_debugMode, StringFormat(
         "Spread too high: %.1f pts (Dynamic Threshold: %.1f, Static: %.1f). Avg Spread: %.2f",
         currentSpread, dynamicSpreadThreshold, cfg.max_spread, m_avgSpread));
      return false;
   }

   if(IsSpreadTrendWidening() && m_debugMode)
      PrintFormat("[%s] WARNING: Spread trending upward. Current: %.1f, SMA: %.1f",
                  m_name, currentSpread, m_spreadTrend.sma);

   // 3. ATR
   double normalizedATR = GetNormalizedATR(currentATR);
   double normalizedMin = cfg.atr_min / m_timeframeFactor;
   double normalizedMax = cfg.atr_max / m_timeframeFactor;

   if(normalizedATR < normalizedMin || normalizedATR > normalizedMax)
   {
      if(m_debugMode)
      {
         string reason = (normalizedATR < normalizedMin) ? "Too Low" : "Too High";
         PrintFormat("[%s] ATR Gate Blocked: Current %.1f (Norm: %.1f), Min: %.1f, Max: %.1f - %s",
                     m_name, currentATR, normalizedATR, normalizedMin, normalizedMax, reason);
      }
      return false;
   }

   // 4. News
   ENUM_NEWS_IMPACT newsImpact = CalculateNewsImpact();
   if(newsImpact >= NEWS_IMPACT_HIGH)
   {
      m_data.DebugLog(m_debugMode, "High impact news detected. Blocking trades.");
      return false;
   }
   if(newsImpact == NEWS_IMPACT_MEDIUM && cfg.news_level >= NEWS_HIGH_MEDIUM)
   {
      m_data.DebugLog(m_debugMode, "Medium impact news detected. Blocking per config.");
      return false;
   }

   // 5. Regime
   if(!CheckRegimeCompatibility())
   {
      m_data.DebugLog(m_debugMode, "Market regime not compatible with current strategy.");
      return false;
   }

   // 6. Session overlap info
   if(m_overlapDetected && m_debugMode)
      PrintFormat("[%s] Session overlap detected. Higher volatility expected.", m_name);

   // 7. Session close warning
   int minsToClose = GetMinutesToSessionClose();
   if(minsToClose > 0 && minsToClose < 30 && m_debugMode)
      PrintFormat("[%s] WARNING: Session closing in %d minutes. Avoid new entries.", m_name, minsToClose);

   return true;
}

//+------------------------------------------------------------------+
//| CalculateNewsImpact                                              |
//| FIX (MM-BUG-5): Cache was reset even for NEWS_IMPACT_NONE,      |
//| causing full calendar scan every 5 min even with no news.        |
//| Now: only re-scan if cache is expired OR if previous result was  |
//| NONE (NONE is not worth caching long — events can appear).       |
//+------------------------------------------------------------------+
ENUM_NEWS_IMPACT MarketManager::CalculateNewsImpact()
{
   datetime now = TimeCurrent();

   // Return cached result if still valid and it was a real hit (not NONE)
   if(now < m_newsImpactExpiry && m_newsImpact != NEWS_IMPACT_NONE)
      return m_newsImpact;

   // For NONE, re-check every 60s (not 5min) to detect approaching events
   // For non-NONE expired cache, re-check normally
   m_newsImpact       = NEWS_IMPACT_NONE;
   m_newsImpactExpiry = now + (m_newsImpact == NEWS_IMPACT_NONE ? 60 : 300);

   for(int i = 0; i < ArraySize(m_webNewsTimes); i++)
   {
      if(now >= m_webNewsTimes[i] - 1800 && now <= m_webNewsTimes[i] + 1800)
      {
         m_newsImpact       = NEWS_IMPACT_HIGH;
         m_newsImpactExpiry = now + 300;
         m_newsStatus       = "WEB HIGH IMPACT NEWS";
         return m_newsImpact;
      }
   }

   MqlCalendarValue values[];
   datetime timeFrom = TimeGMT() - 1800;
   datetime timeTo   = TimeGMT() + 1800;

   string currencies[2] = {m_baseCurr, m_profitCurr};
   for(int c = 0; c < 2; c++)
   {
      if(currencies[c] == "") continue;

      if(CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) > 0)
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(values[i].event_id, ev))
            {
               if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
               {
                  m_newsImpact       = NEWS_IMPACT_HIGH;
                  m_newsImpactExpiry = now + 300;
                  m_newsStatus       = "HIGH: " + ev.name;
                  return m_newsImpact;
               }
               else if(ev.importance == CALENDAR_IMPORTANCE_MODERATE && m_newsImpact < NEWS_IMPACT_MEDIUM)
               {
                  m_newsImpact = NEWS_IMPACT_MEDIUM;
                  m_newsStatus = "MEDIUM: " + ev.name;
               }
               else if(ev.importance == CALENDAR_IMPORTANCE_LOW && m_newsImpact < NEWS_IMPACT_LOW)
               {
                  m_newsImpact = NEWS_IMPACT_LOW;
                  m_newsStatus = "LOW: " + ev.name;
               }
            }
         }
      }
   }

   if(m_newsImpact != NEWS_IMPACT_NONE)
      m_newsImpactExpiry = now + 300;

   if(m_newsImpact == NEWS_IMPACT_NONE)
      m_newsStatus = "No News";

   return m_newsImpact;
}

//+------------------------------------------------------------------+
//| CheckRegimeCompatibility                                         |
//| FIX (MM-BUG-2): MultiTFRegimeContext is a STRUCT, not pointer.  |
//| CheckPointer() on a struct value always returns POINTER_INVALID. |
//| Removed invalid pointer check.                                   |
//+------------------------------------------------------------------+
bool MarketManager::CheckRegimeCompatibility()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);

   if(!cfg.market_regime_enabled) return true;
   if(m_regimeFilter == NULL)     return true;

   datetime now = TimeCurrent();
   if(now - m_lastRegimeCheck < 60) return true;  // throttle: 1x per minute

   m_lastRegimeCheck    = now;
   // FIX: GetContext() returns struct by value — no pointer check needed
   m_lastRegimeContext  = m_regimeFilter.GetContext();

   switch(m_lastRegimeContext.tradingTF)
   {
      case REGIME_TRENDING_STRONG:  return true;
      case REGIME_TRENDING_WEAK:    return true;

      case REGIME_RANGING_SIDEWAYS:
         if(cfg.pattern_mean_reversion_mode) return true;
         if(m_debugMode)
            PrintFormat("[%s] Ranging market detected. Mean reversion mode OFF, blocking.", m_name);
         return false;

      case REGIME_CHOPPY_HIGH_VOL:
         if(m_debugMode)
            PrintFormat("[%s] Choppy high volatility regime. Blocking trades.", m_name);
         return false;

      case REGIME_TRANSITION:
         if(m_debugMode)
            PrintFormat("[%s] Market regime in transition. Waiting for clarity.", m_name);
         return false;

      default: return true;
   }
}

MultiTFRegimeContext MarketManager::GetCurrentRegime()
{
   if(m_regimeFilter == NULL)
   {
      MultiTFRegimeContext empty;
      ZeroMemory(empty);
      return empty;
   }
   return m_regimeFilter.GetContext();
}

bool MarketManager::IsRegimeCompatible()
{
   return CheckRegimeCompatibility();
}

void MarketManager::OnPriceUpdate(PriceUpdateEvent *e)
{
   if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
   m_lastTick    = e.tick;
   m_hasLastTick = true;
   // Update spread EMA on every tick
   double spreadNow = (e.tick.ask - e.tick.bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spreadNow > 0)
      m_avgSpread = m_avgSpread * 0.9 + spreadNow * 0.1;
   UpdateGateState(m_lastTick);
}

void MarketManager::OnNewBar(NewBarEvent *e)
{
   if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;

   if(!m_hasLastTick)
   {
      if(!SymbolInfoTick(_Symbol, m_lastTick)) return;
      m_hasLastTick = true;
   }

   // DetectSessionOverlaps called inside PassesGateWithContext — no duplicate call needed here
   UpdateGateState(m_lastTick);
}

void MarketManager::OnHeartbeat(HeartbeatEvent *e)
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   // FIX (MM-BUG-6): Use local cfg, not global CFG.news.use
   if(cfg.news.use)
      FetchWebNews();

   if(TimeCurrent() - m_lastSpreadUpdate > 300)
      UpdateInstrumentContext();
}

void MarketManager::UpdateGateState(const MqlTick &tick)
{
   double currentSpread = 0.0;
   double currentATR    = (CheckPointer(m_data) != POINTER_INVALID) ? m_data.GetATRPoints() : 0.0;
   bool   gateOpen      = (currentATR > 0) ? PassesGate(tick, currentSpread, currentATR) : false;

   bool entryAllowed = !IsEntryCooldownActive();
   bool stateChanged = (gateOpen != m_gateOpen) ||
                       (entryAllowed != m_entryAllowed) ||
                       (MathAbs(currentSpread - m_lastSpread) > 0.1) ||
                       (MathAbs(currentATR - m_lastATR) > 0.1);

   m_gateOpen       = gateOpen;
   m_entryAllowed   = entryAllowed;
   m_lastSpread     = currentSpread;
   m_lastATR        = currentATR;

   if(stateChanged || m_debugMode)
   {
      if(m_debugMode)
         PrintFormat("[%s] MarketGate updated - gateOpen=%s entryAllowed=%s spread=%.1f atr=%.2f",
                     m_name,
                     m_gateOpen ? "true" : "false",
                     m_entryAllowed ? "true" : "false",
                     m_lastSpread, m_lastATR);
      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

bool MarketManager::IsTradingSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int startMin = m_sessionStarts[now.day_of_week];
   int endMin   = m_sessionEnds[now.day_of_week];

   if(startMin < 0) return false;
   if(startMin == 0 && endMin == 1440) return true;

   int currMin = now.hour * 60 + now.min;
   if(startMin <= endMin)
      return (currMin >= startMin && currMin <= endMin);
   return (currMin >= startMin || currMin <= endMin);
}

bool MarketManager::IsSessionOverlap()
{
   // DetectSessionOverlaps already called by PassesGateWithContext on each tick/bar.
   // Only call explicitly when queried outside gate flow.
   DetectSessionOverlaps();
   return m_overlapDetected;
}

int MarketManager::GetMinutesToSessionClose()
{
   if(m_activeSessionIndex < 0) return -1;
   return m_sessions[m_activeSessionIndex].minutesToClose;
}

SessionInfo MarketManager::GetCurrentSessionInfo()
{
   if(m_activeSessionIndex < 0)
   {
      SessionInfo empty;
      ZeroMemory(empty);
      return empty;
   }
   return m_sessions[m_activeSessionIndex];
}

void MarketManager::FetchWebNews()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(TimeCurrent() < m_lastWebFetch + 1800) return;

   char data[], result[];
   string headers;
   int res = WebRequest("GET", cfg.news_url, NULL, NULL, 5000, data, 0, result, headers);

   if(res != 200)
   {
      m_data.DebugLog(m_debugMode, "WebNews Fetch Failed. HTTP Status: " + (string)res +
                      ", MQL Error: " + (string)GetLastError());
      return;
   }

   string content = CharArrayToString(result);
   ArrayFree(m_webNewsTimes);
   string tagOpen = "<event>", tagClose = "</event>";
   int    pos     = 0;

   while((pos = StringFind(content, tagOpen, pos)) >= 0)
   {
      int endPos = StringFind(content, tagClose, pos);
      if(endPos < 0) break;

      string eventData = StringSubstr(content, pos, endPos - pos);

      // FIX (MM-BUG-6): Use local cfg.news.level, not global CFG
      bool isHighImpact = (StringFind(eventData, "High") >= 0 ||
                           (cfg.news.level >= NEWS_HIGH_MEDIUM && StringFind(eventData, "Medium") >= 0));

      bool isRelevant = (StringFind(eventData, m_baseCurr)   >= 0 ||
                         StringFind(eventData, m_profitCurr) >= 0 ||
                         StringFind(eventData, "USD")         >= 0);

      if(isHighImpact && isRelevant)
      {
         int datePos = StringFind(eventData, "<date>");
         int timePos = StringFind(eventData, "<time>");
         if(datePos >= 0 && timePos >= 0)
         {
            int    dateEnd  = StringFind(eventData, "</date>", datePos);
            int    timeEnd  = StringFind(eventData, "</time>", timePos);
            string dateRaw  = StringSubstr(eventData, datePos, dateEnd - datePos);
            string timeRaw  = StringSubstr(eventData, timePos, timeEnd - timePos);
            string dStr     = m_data.StripTags(dateRaw);
            string tStr     = m_data.StripTags(timeRaw);
            string dParts[];

            if(StringSplit(dStr, '-', dParts) == 3 &&
               dParts[0] != "" && dParts[1] != "" && dParts[2] != "")
            {
               dStr = dParts[2] + "." + dParts[0] + "." + dParts[1];
               if(dStr == "..") { pos = endPos + StringLen(tagClose); continue; }
            }

            string timeOnly = tStr;
            StringReplace(timeOnly, " AM", "");
            StringReplace(timeOnly, " PM", "");
            int sep = StringFind(timeOnly, ":");
            if(sep < 0) { pos = endPos + StringLen(tagClose); continue; }

            int hr = (int)StringToInteger(StringSubstr(timeOnly, 0, sep));
            int mn = (int)StringToInteger(StringSubstr(timeOnly, sep + 1));

            if(StringFind(tStr, "PM") >= 0 && hr != 12) hr += 12;
            else if(StringFind(tStr, "AM") >= 0 && hr == 12) hr = 0;

            datetime eventTime = StringToTime(dStr + " " + StringFormat("%02d:%02d", hr, mn));
            if(eventTime > 0)
            {
               int sz = ArraySize(m_webNewsTimes);
               ArrayResize(m_webNewsTimes, sz + 1, 10);
               m_webNewsTimes[sz] = eventTime;
            }
         }
      }
      pos = endPos + StringLen(tagClose);
   }
   m_lastWebFetch = TimeCurrent();
}

bool MarketManager::IsNewsTime()
{
   return (CalculateNewsImpact() >= NEWS_IMPACT_HIGH);
}

bool MarketManager::IsEntryCooldownActive()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   MqlRates rates[];
   if(CopyRates(m_symbol, m_period, 1, 1, rates) <= 0) return false;
   datetime currBar = rates[0].time;

   if(m_lastEntryBarTime > 0)
   {
      int barsSinceEntry = (int)((currBar - m_lastEntryBarTime) / PeriodSeconds(m_period));
      if(barsSinceEntry < cfg.entry_cooldown_bars)
      {
         m_data.DebugLog(m_debugMode, "Entry cooldown active (bars: " + (string)barsSinceEntry + ")");
         return true;
      }
   }

   if(m_consecutiveLosses >= cfg.max_consecutive_loss)
   {
      int barsSinceLoss = (int)((currBar - m_lastLossBarTime) / PeriodSeconds(m_period));
      if(barsSinceLoss < cfg.loss_cooldown_bars)
      {
         m_data.DebugLog(m_debugMode, "Loss cooldown active (bars: " + (string)barsSinceLoss + ")");
         return true;
      }
   }

   return false;
}

void MarketManager::UpdateLossStreak(double netProfit)
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   if(netProfit < 0)
   {
      m_consecutiveLosses++;
      MqlRates rates[];
      if(CopyRates(m_symbol, m_period, 1, 1, rates) > 0)
         m_lastLossBarTime = rates[0].time;

      string msg = "Loss Detected! Net Profit: " + DoubleToString(netProfit, 2) +
                   " | Consecutive Losses: " + (string)m_consecutiveLosses;
      if(m_consecutiveLosses >= cfg.max_consecutive_loss)
         msg += " | Cooldown Active.";
      m_data.DebugLog(m_debugMode, msg);
   }
   else if(netProfit > 0)
   {
      m_consecutiveLosses = 0;
      m_data.DebugLog(m_debugMode, "Profit Detected! Resetting loss counter.");
   }

   bool entryAllowed = !IsEntryCooldownActive();
   if(entryAllowed != m_entryAllowed)
   {
      m_entryAllowed = entryAllowed;
      if(m_debugMode)
         PrintFormat("[%s] Entry permission changed to %s due to last trade result.",
                     m_name, m_entryAllowed ? "ALLOWED" : "BLOCKED");

      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

#endif
