//+------------------------------------------------------------------+
//|                                              3.MarketManager.mqh |
//|                                       Copyright 2026, Agsicentre |
//|            Market State & Session Management Module              |
//|                   V2.20 - Refactored & Optimized                 |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link "agsicentre.wordpress.com"
#property version "2.20"
#property strict

#ifndef __MARKET_MANAGER_MQH__
#define __MARKET_MANAGER_MQH__

#include "IManager.mqh"
// Forward declarations to reduce coupling
class DataManager;
class MarketRegimeFilter;

#include "10.DataManager.mqh"
#include "12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| ENUM: News Impact Levels                                         |
//+------------------------------------------------------------------+
enum ENUM_NEWS_IMPACT
{
   NEWS_IMPACT_NONE = 0,     // No news detected
   NEWS_IMPACT_LOW,          // Low impact news
   NEWS_IMPACT_MEDIUM,       // Medium impact news
   NEWS_IMPACT_HIGH          // High impact news (major events)
};

//+------------------------------------------------------------------+
//| STRUCT: Session Info with Overlap Detection                      |
//+------------------------------------------------------------------+
struct SessionInfo
{
   int startMin;
   int endMin;
   bool isActive;
   bool isOverlap;            // True if overlapping with another session
   int overlapWithIndex;      // Index of overlapping session (-1 if none)
   int minutesToClose;        // Countdown to session close
   
   SessionInfo() : startMin(0), endMin(0), isActive(false), isOverlap(false), 
                   overlapWithIndex(-1), minutesToClose(0) {}
};

//+------------------------------------------------------------------+
//| STRUCT: Spread History for Trend Analysis                        |
//+------------------------------------------------------------------+
struct SpreadTrend
{
   double spreads[];          // Recent spread history
   double sma;                // Simple Moving Average
   double slope;              // Trend slope (positive = widening)
   datetime lastUpdate;
   int maxSamples;            // Maximum samples to keep
   
   SpreadTrend() : sma(0.0), slope(0.0), lastUpdate(0), maxSamples(20)
   {
      ArrayResize(spreads, 0);
   }
   
   void AddSample(double spread)
   {
      // Shift buffer efficiently
      if(ArraySize(spreads) >= maxSamples)
      {
         ArrayCopy(spreads, spreads, 0, 1, WHOLE_ARRAY - 1);
         spreads[maxSamples - 1] = spread;
      }
      else
      {
         int size = ArraySize(spreads);
         ArrayResize(spreads, size + 1);
         spreads[size] = spread;
      }
      lastUpdate = TimeCurrent();
   }
   
   void CalculateSMA()
   {
      if(ArraySize(spreads) == 0)
      {
         sma = 0.0;
         return;
      }
      
      double sum = 0.0;
      for(int i = 0; i < ArraySize(spreads); i++)
         sum += spreads[i];
      sma = sum / ArraySize(spreads);
   }
   
   void CalculateSlope()
   {
      int n = MathMin(10, ArraySize(spreads));
      if(n < 5)
      {
         slope = 0.0;
         return;
      }
      
      double xSum = 0.0, ySum = 0.0, xySum = 0.0, xxSum = 0.0;
      for(int i = 0; i < n; i++)
      {
         double x = (double)i;
         double y = spreads[i];
         xSum += x;
         ySum += y;
         xySum += x * y;
         xxSum += x * x;
      }
      
      double denominator = n * xxSum - xSum * xSum;
      if(denominator != 0)
         slope = (n * xySum - xSum * ySum) / denominator;
      else
         slope = 0.0;
   }
};

//+------------------------------------------------------------------+
//| CLASS: MarketManager                                             |
//+------------------------------------------------------------------+
class MarketManager : public IManager
{
private:
   string m_baseCurr;
   string m_profitCurr;
   
   // Instrument context for dynamic validation
   double m_avgSpread;        // Average spread for this symbol
   double m_tickSize;
   int m_digits;
   datetime m_lastSpreadUpdate;
   
   // ATR normalization
   double m_atrH1Baseline;    // ATR normalized to H1 timeframe
   double m_timeframeFactor;  // sqrt(time) factor for normalization
   
   // Session management with overlap detection
   SessionInfo m_sessions[7];
   int m_sessionStarts[7];
   int m_sessionEnds[7];
   bool m_overlapDetected;
   int m_activeSessionIndex;
   
   // News impact scoring
   ENUM_NEWS_IMPACT m_newsImpact;
   datetime m_newsImpactExpiry;
   
   // Spread trend analysis
   SpreadTrend m_spreadTrend;
   bool m_spreadWarningActive;
   
   // Market regime integration
   MarketRegimeFilter* m_regimeFilter;
   MultiTFRegimeContext m_lastRegimeContext;
   datetime m_lastRegimeCheck;
   
   // --- Internal State Variables ---
   string m_newsStatus;
   datetime m_nextNewsTime;
   datetime m_lastBarTime;
   datetime m_dayAnchor;
   datetime m_lastNewsCheck;
   bool m_lastNewsResult;
   datetime m_lastWebFetch;
   datetime m_webNewsTimes[];
   datetime m_lastEntryBarTime;
   datetime m_lastLossBarTime;
   int m_consecutiveLosses;

   bool m_gateOpen;
   bool m_entryAllowed;
   double m_lastSpread;
   double m_lastATR;
   MqlTick m_lastTick;
   bool m_hasLastTick;

   // Helper methods - Refactored for clarity
   void FetchWebNews();
   void UpdateGateState(const MqlTick &tick);
   void UpdateInstrumentContext();
   void UpdateSpreadTrend(double currentSpread);
   ENUM_NEWS_IMPACT CalculateNewsImpact();
   void DetectSessionOverlaps();
   bool CheckRegimeCompatibility();
   double NormalizeATR(double atr, ENUM_TIMEFRAMES tf);
   
   // New helper methods for better separation of concerns
   bool ValidateSpread(double currentSpread, const StrategyConfig &cfg);
   bool ValidateATR(double normalizedATR, const StrategyConfig &cfg);
   bool ValidateNewsImpact(ENUM_NEWS_IMPACT impact, const StrategyConfig &cfg);
   
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
                     m_lastRegimeCheck(0),
                     m_consecutiveLosses(0),
                     m_lastEntryBarTime(0),
                     m_lastLossBarTime(0),
                     m_nextNewsTime(0),
                     m_lastBarTime(0),
                     m_dayAnchor(0),
                     m_lastNewsCheck(0),
                     m_lastWebFetch(0)
   {
      m_baseCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      m_profitCurr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      ArrayInitialize(m_sessionStarts, -1);
      ArrayInitialize(m_sessionEnds, -1);
      ArrayFill(m_sessions, 0, 7, SessionInfo());
      ArrayInitialize(m_webNewsTimes, 0);
      
      // Initialize spread trend buffer with proper size
      ArrayResize(m_spreadTrend.spreads, m_spreadTrend.maxSamples);
      ArrayInitialize(m_spreadTrend.spreads, 0.0);
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
      if(m_regimeFilter != NULL)
         delete m_regimeFilter;
      m_regimeFilter = NULL;
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_PRICE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_REGIME_CHANGE);  // New event for regime changes
   }

   virtual void OnPriceUpdate(PriceUpdateEvent *e) override;
   virtual void OnNewBar(NewBarEvent *e) override;
   virtual void OnHeartbeat(HeartbeatEvent *e) override;

   virtual bool Init() override;
   
   // Core gate logic with context-aware validation
   bool PassesGate(const MqlTick &tick, double &currentSpread, double currentATR);
   bool PassesGateWithContext(const MqlTick &tick, double &currentSpread, double currentATR);
   
   // Session management
   bool IsTradingSession();
   bool IsSessionOverlap();
   int GetMinutesToSessionClose();
   SessionInfo GetCurrentSessionInfo();
   
   // News with impact scoring
   bool IsNewsTime();
   ENUM_NEWS_IMPACT GetNewsImpact() const { return m_newsImpact; }
   string GetNewsStatus() const { return m_newsStatus; }
   datetime GetNextNewsTime() const { return m_nextNewsTime; }
   
   // Spread analysis
   double GetAverageSpread() const { return m_avgSpread; }
   bool IsSpreadTrendWidening() const { return m_spreadTrend.slope > 0.5; }
   bool IsSpreadWarningActive() const { return m_spreadWarningActive; }
   
   // ATR normalization
   double GetNormalizedATR(double currentATR) const;
   
   // Regime integration
   bool IsRegimeCompatible();
   MultiTFRegimeContext GetCurrentRegime();
   
   // Cooldown and loss tracking
   bool IsEntryCooldownActive();
   void UpdateLossStreak(double netProfit);
   
   // State setters
   void UpdateLastEntryBarTime(datetime time) { m_lastEntryBarTime = time; }
   void SetLastBarTime(datetime time) { m_lastBarTime = time; }
};
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
MarketManager::~MarketManager()
{
   ArrayFree(m_webNewsTimes);
   if(m_regimeFilter != NULL)
      delete m_regimeFilter;
}

//+------------------------------------------------------------------+
//| UpdateInstrumentContext - Get symbol-specific data               |
//+------------------------------------------------------------------+
void MarketManager::UpdateInstrumentContext()
{
   m_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   m_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Calculate average spread from recent history
   double spreads[];
   int copied = CopyTick(_Symbol, 0, 0, 50, spreads);
   if(copied > 0)
   {
      double sum = 0.0;
      int count = 0;
      for(int i = 0; i < copied; i++)
      {
         if(spreads[i] > 0)
         {
            sum += spreads[i];
            count++;
         }
      }
      if(count > 0)
         m_avgSpread = sum / count;
   }
   
   // Calculate timeframe normalization factor
   // H1 = baseline, factor = sqrt(currentTF_seconds / 3600)
   long tfSeconds = PeriodSeconds();
   m_timeframeFactor = MathSqrt(tfSeconds / 3600.0);
   
   m_lastSpreadUpdate = TimeCurrent();
   
   if(m_debugMode)
   {
      PrintFormat("[%s] Instrument Context: %s, Digits=%d, TickSize=%.5f, AvgSpread=%.2f pts, TF Factor=%.2f",
                  m_name, _Symbol, m_digits, m_tickSize, m_avgSpread, m_timeframeFactor);
   }
}

//+------------------------------------------------------------------+
//| NormalizeATR - Convert ATR to H1 baseline                        |
//+------------------------------------------------------------------+
double MarketManager::NormalizeATR(double atr, ENUM_TIMEFRAMES tf)
{
   if(atr <= 0)
      return 0.0;
   
   // Normalize to H1 baseline using square root of time scaling
   long tfSeconds = PeriodSeconds(tf);
   double factor = MathSqrt(tfSeconds / 3600.0);
   
   return atr / factor;
}

//+------------------------------------------------------------------+
//| GetNormalizedATR - Public getter for normalized ATR              |
//+------------------------------------------------------------------+
double MarketManager::GetNormalizedATR(double currentATR) const
{
   if(currentATR <= 0)
      return 0.0;
   return currentATR / m_timeframeFactor;
}

//+------------------------------------------------------------------+
//| UpdateSpreadTrend - Track spread history and calculate trend     |
//+------------------------------------------------------------------+
void MarketManager::UpdateSpreadTrend(double currentSpread)
{
   // Use encapsulated method in SpreadTrend struct
   m_spreadTrend.AddSample(currentSpread);
   m_spreadTrend.CalculateSMA();
   m_spreadTrend.CalculateSlope();
   
   // Check if spread is widening significantly
   if(m_spreadTrend.slope > 1.0 && !m_spreadWarningActive)
   {
      m_spreadWarningActive = true;
      if(m_debugMode)
         PrintFormat("[%s] WARNING: Spread trending upward rapidly (slope=%.2f). Current: %.1f, SMA: %.1f",
                     m_name, m_spreadTrend.slope, currentSpread, m_spreadTrend.sma);
   }
   else if(m_spreadTrend.slope < 0.3)
   {
      m_spreadWarningActive = false;
   }
}

//+------------------------------------------------------------------+
//| DetectSessionOverlaps - Find overlapping sessions                |
//+------------------------------------------------------------------+
void MarketManager::DetectSessionOverlaps()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currMin = now.hour * 60 + now.min;
   
   m_overlapDetected = false;
   m_activeSessionIndex = -1;
   
   // Reset all sessions
   for(int i = 0; i < 7; i++)
   {
      m_sessions[i].isActive = false;
      m_sessions[i].isOverlap = false;
      m_sessions[i].overlapWithIndex = -1;
      m_sessions[i].minutesToClose = 0;
   }
   
   // Find active sessions
   int activeCount = 0;
   int activeIndices[];
   ArrayResize(activeIndices, 7);
   
   for(int i = 0; i < 7; i++)
   {
      if(m_sessionStarts[i] < 0)
         continue;
         
      bool isActive = false;
      if(m_sessionStarts[i] == 0 && m_sessionEnds[i] == 1440)
         isActive = true;
      else if(m_sessionStarts[i] <= m_sessionEnds[i])
         isActive = (currMin >= m_sessionStarts[i] && currMin <= m_sessionEnds[i]);
      else
         isActive = (currMin >= m_sessionStarts[i] || currMin <= m_sessionEnds[i]);
      
      if(isActive)
      {
         m_sessions[i].isActive = true;
         m_sessions[i].startMin = m_sessionStarts[i];
         m_sessions[i].endMin = m_sessionEnds[i];
         
         // Calculate minutes to close
         if(m_sessionEnds[i] >= currMin)
            m_sessions[i].minutesToClose = m_sessionEnds[i] - currMin;
         else
            m_sessions[i].minutesToClose = (1440 - currMin) + m_sessionEnds[i];
         
         activeIndices[activeCount] = i;
         activeCount++;
         
         if(m_activeSessionIndex < 0)
            m_activeSessionIndex = i;
      }
   }
   
   // Detect overlaps (if more than one session is active)
   if(activeCount > 1)
   {
      m_overlapDetected = true;
      for(int i = 0; i < activeCount; i++)
      {
         int idx = activeIndices[i];
         m_sessions[idx].isOverlap = true;
         // Mark overlap with next active session
         if(i < activeCount - 1)
            m_sessions[idx].overlapWithIndex = activeIndices[i + 1];
      }
      
      if(m_debugMode)
         PrintFormat("[%s] Session Overlap Detected! %d active sessions", m_name, activeCount);
   }
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
bool MarketManager::Init()
{
   if (!IManager::Init())
      return false;

   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   
   // Initialize instrument context
   UpdateInstrumentContext();
   
   // Initialize session times
   for (int i = 0; i < 7; i++)
   {
      string session = cfg.sessions[i];
      if (session == "0" || session == "")
      {
         m_sessionStarts[i] = -1;
         m_sessionEnds[i] = -1;
      }
      else if (session == "00:00-24:00")
      {
         m_sessionStarts[i] = 0;
         m_sessionEnds[i] = 1440;
      }
      else
      {
         string parts[];
         if (StringSplit(session, '-', parts) == 2)
         {
            m_sessionStarts[i] = m_data.ParseHM(parts[0]);
            m_sessionEnds[i] = m_data.ParseHM(parts[1]);
         }
         else
         {
            m_sessionStarts[i] = 0;
            m_sessionEnds[i] = 1440;
         }
      }
   }
   
   // Initialize regime filter
   m_regimeFilter = new MarketRegimeFilter();
   if(m_regimeFilter != NULL)
      m_regimeFilter.Init(_Symbol, PERIOD_CURRENT, PERIOD_H4, PERIOD_D1);

   return true;
}

//+------------------------------------------------------------------+
//| PassesGate - Combines all market filters (LEGACY)                |
//+------------------------------------------------------------------+
bool MarketManager::PassesGate(const MqlTick &tick, double &currentSpread, double currentATR)
{
   return PassesGateWithContext(tick, currentSpread, currentATR);
}

//+------------------------------------------------------------------+
//| PassesGateWithContext - Context-aware market gate logic          |
//+------------------------------------------------------------------+
bool MarketManager::PassesGateWithContext(const MqlTick &tick, double &currentSpread, double currentATR)
{
   if(currentATR <= 0)
      return false;
      
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   
   // 1. Check trading session
   if (!IsTradingSession())
   {
      if(m_debugMode)
         PrintFormat("[%s] Gate blocked: Trading session closed", m_name);
      return false;
   }
   
   // Detect session overlaps
   DetectSessionOverlaps();
   
   // 2. Calculate spread
   currentSpread = (tick.ask - tick.bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Update spread trend analysis
   UpdateSpreadTrend(currentSpread);
   
   // Validate spread with dynamic threshold
   if(!ValidateSpread(currentSpread, cfg))
      return false;
   
   // 3. Validate ATR with normalization
   double normalizedATR = GetNormalizedATR(currentATR);
   if(!ValidateATR(normalizedATR, cfg))
      return false;
   
   // 4. Validate news impact
   ENUM_NEWS_IMPACT newsImpact = CalculateNewsImpact();
   if(!ValidateNewsImpact(newsImpact, cfg))
      return false;
   
   // 5. Check market regime compatibility
   if(!CheckRegimeCompatibility())
   {
      if(m_debugMode)
         PrintFormat("[%s] Gate blocked: Market regime incompatible", m_name);
      return false;
   }
   
   // 6. Session overlap notification
   if(m_overlapDetected && m_debugMode)
      PrintFormat("[%s] Session overlap detected - higher volatility expected", m_name);
   
   // 7. Session close warning
   int minsToClose = GetMinutesToSessionClose();
   if(minsToClose > 0 && minsToClose < 30 && m_debugMode)
      PrintFormat("[%s] WARNING: Session closing in %d minutes", m_name, minsToClose);
   
   return true;
}

//+------------------------------------------------------------------+
//| ValidateSpread - Check spread against dynamic threshold          |
//+------------------------------------------------------------------+
bool MarketManager::ValidateSpread(double currentSpread, const StrategyConfig &cfg)
{
   // Dynamic threshold based on average spread
   double dynamicThreshold = MathMax(cfg.max_spread, m_avgSpread * 2.5);
   
   if(currentSpread > dynamicThreshold)
   {
      if(m_debugMode)
         PrintFormat("[%s] Spread too high: %.1f pts (Threshold: %.1f, Avg: %.2f)",
                     m_name, currentSpread, dynamicThreshold, m_avgSpread);
      return false;
   }
   
   // Warning if spread is widening
   if(IsSpreadTrendWidening() && m_debugMode)
      PrintFormat("[%s] WARNING: Spread trending upward. Current: %.1f, SMA: %.1f",
                  m_name, currentSpread, m_spreadTrend.sma);
   
   return true;
}

//+------------------------------------------------------------------+
//| ValidateATR - Check ATR within normalized bounds                 |
//+------------------------------------------------------------------+
bool MarketManager::ValidateATR(double normalizedATR, const StrategyConfig &cfg)
{
   double normalizedMin = cfg.atr_min / m_timeframeFactor;
   double normalizedMax = cfg.atr_max / m_timeframeFactor;
   
   if(normalizedATR < normalizedMin || normalizedATR > normalizedMax)
   {
      if(m_debugMode)
      {
         string reason = (normalizedATR < normalizedMin) ? "Too Low" : "Too High";
         PrintFormat("[%s] ATR blocked: %.1f (Norm: %.1f), Range: %.1f-%.1f - %s",
                     m_name, normalizedATR * m_timeframeFactor, normalizedATR, 
                     normalizedMin, normalizedMax, reason);
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| ValidateNewsImpact - Check news impact level                     |
//+------------------------------------------------------------------+
bool MarketManager::ValidateNewsImpact(ENUM_NEWS_IMPACT impact, const StrategyConfig &cfg)
{
   // Block high impact news
   if(impact >= NEWS_IMPACT_HIGH)
   {
      if(m_debugMode)
         PrintFormat("[%s] Gate blocked: High impact news detected", m_name);
      return false;
   }
   
   // Block medium impact if configured
   if(impact == NEWS_IMPACT_MEDIUM && cfg.news_level >= NEWS_HIGH_MEDIUM)
   {
      if(m_debugMode)
         PrintFormat("[%s] Gate blocked: Medium impact news per config", m_name);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| CalculateNewsImpact - Score news impact level                    |
//+------------------------------------------------------------------+
ENUM_NEWS_IMPACT MarketManager::CalculateNewsImpact()
{
   datetime now = TimeCurrent();
   
   // Return cached result if still valid
   if(now < m_newsImpactExpiry && m_newsImpact != NEWS_IMPACT_NONE)
      return m_newsImpact;
   
   m_newsImpact = NEWS_IMPACT_NONE;
   m_newsImpactExpiry = now + 300; // Cache for 5 minutes
   
   // Check web news
   for(int i = 0; i < ArraySize(m_webNewsTimes); i++)
   {
      if(now >= m_webNewsTimes[i] - 1800 && now <= m_webNewsTimes[i] + 1800)
      {
         m_newsImpact = NEWS_IMPACT_HIGH;
         m_newsStatus = "WEB HIGH IMPACT NEWS";
         return m_newsImpact;
      }
   }
   
   // Check native calendar
   MqlCalendarValue values[];
   datetime timeFrom = TimeGMT() - 1800;
   datetime timeTo = TimeGMT() + 1800;
   
   string currencies[2] = {m_baseCurr, m_profitCurr};
   for(int c = 0; c < 2; c++)
   {
      if(currencies[c] == "") continue;
      
      if(CalendarValueHistory(values, timeFrom, timeTo, NULL, currencies[c]) > 0)
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event))
            {
               if(event.importance == CALENDAR_IMPORTANCE_HIGH)
               {
                  m_newsImpact = NEWS_IMPACT_HIGH;
                  m_newsStatus = "HIGH: " + event.name;
                  return m_newsImpact;
               }
               else if(event.importance == CALENDAR_IMPORTANCE_MODERATE && m_newsImpact < NEWS_IMPACT_MEDIUM)
               {
                  m_newsImpact = NEWS_IMPACT_MEDIUM;
                  m_newsStatus = "MEDIUM: " + event.name;
               }
               else if(event.importance == CALENDAR_IMPORTANCE_LOW && m_newsImpact < NEWS_IMPACT_LOW)
               {
                  m_newsImpact = NEWS_IMPACT_LOW;
                  m_newsStatus = "LOW: " + event.name;
               }
            }
         }
      }
   }
   
   if(m_newsImpact == NEWS_IMPACT_NONE)
      m_newsStatus = "No News";
   
   return m_newsImpact;
}

//+------------------------------------------------------------------+
//| CheckRegimeCompatibility - Integrate with MarketRegimeFilter     |
//+------------------------------------------------------------------+
bool MarketManager::CheckRegimeCompatibility()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   
   // Skip regime check if disabled in config
   if(!cfg.market_regime_enabled)
      return true;
   
   if(m_regimeFilter == NULL)
      return true;
   
   // Update regime context (with throttling)
   datetime now = TimeCurrent();
   if(now - m_lastRegimeCheck < 60) // Check every minute
      return true;
   
   m_lastRegimeCheck = now;
   MultiTFRegimeContext context = m_regimeFilter.GetContext();
   
   if(CheckPointer(context) == POINTER_INVALID)
      return true;
   
   m_lastRegimeContext = context;
   
   // Check if regime is tradeable
   switch(context.tradingTF)
   {
      case REGIME_TRENDING_STRONG:
         // Strong trends are good for trend-following strategies
         return true;
         
      case REGIME_TRENDING_WEAK:
         // Weak trends - might want to reduce position size
         return true;
         
      case REGIME_RANGING_SIDEWAYS:
         // Ranging - only trade if strategy supports mean reversion
         if(cfg.pattern_mean_reversion_mode)
            return true;
         if(m_debugMode)
            PrintFormat("[%s] Ranging market detected. Mean reversion mode OFF, blocking.", m_name);
         return false;
         
      case REGIME_CHOPPY_HIGH_VOL:
         // Choppy high vol - dangerous, avoid trading
         if(m_debugMode)
            PrintFormat("[%s] Choppy high volatility regime. Blocking trades.", m_name);
         return false;
         
      case REGIME_TRANSITION:
         // Regime transition - wait for clarity
         if(m_debugMode)
            PrintFormat("[%s] Market regime in transition. Waiting for clarity.", m_name);
         return false;
         
      default:
         return true;
   }
}

//+------------------------------------------------------------------+
//| GetCurrentRegime - Get current market regime context             |
//+------------------------------------------------------------------+
MultiTFRegimeContext MarketManager::GetCurrentRegime()
{
   if(m_regimeFilter == NULL)
   {
      MultiTFRegimeContext empty;
      return empty;
   }
   return m_regimeFilter.GetContext();
}

//+------------------------------------------------------------------+
//| IsRegimeCompatible - Public wrapper                              |
//+------------------------------------------------------------------+
bool MarketManager::IsRegimeCompatible()
{
   return CheckRegimeCompatibility();
}

void MarketManager::OnPriceUpdate(PriceUpdateEvent *e)
{
   if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
      return;

   m_lastTick = e.tick;
   m_hasLastTick = true;
   UpdateGateState(m_lastTick);
}

void MarketManager::OnNewBar(NewBarEvent *e)
{
   if (CheckPointer(e) == POINTER_INVALID || !m_initialized)
      return;

   if (!m_hasLastTick)
   {
      if (!SymbolInfoTick(_Symbol, m_lastTick)) return;
      m_hasLastTick = true;
   }

   // Detect session overlaps on new bar
   DetectSessionOverlaps();
   
   UpdateGateState(m_lastTick);
}

//+------------------------------------------------------------------+
//| OnHeartbeat - Periodic tasks                                     |
//+------------------------------------------------------------------+
void MarketManager::OnHeartbeat(HeartbeatEvent *e)
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   if (cfg.news.use)
      FetchWebNews();
   
   // Periodically update instrument context (every 5 minutes)
   if(TimeCurrent() - m_lastSpreadUpdate > 300)
      UpdateInstrumentContext();
}

//+------------------------------------------------------------------+
//| Consolidated Market Gate Logic                                   |
//+------------------------------------------------------------------+
void MarketManager::UpdateGateState(const MqlTick &tick)
{
   double currentSpread = 0.0;
   double currentATR = (CheckPointer(m_data) != POINTER_INVALID) ? m_data.GetATRPoints() : 0.0;
   bool gateOpen = (currentATR > 0) ? PassesGate(tick, currentSpread, currentATR) : false;

   bool entryAllowed = !IsEntryCooldownActive();
   bool stateChanged = (gateOpen != m_gateOpen) ||
                       (entryAllowed != m_entryAllowed) ||
                       (MathAbs(currentSpread - m_lastSpread) > 0.1) ||
                       (MathAbs(currentATR - m_lastATR) > 0.1);

   m_gateOpen = gateOpen;
   m_entryAllowed = entryAllowed;
   m_lastSpread = currentSpread;
   m_lastATR = currentATR;

   if (stateChanged || m_debugMode)
   {
      if (m_debugMode)
         PrintFormat("[%s] MarketGate updated on NewBar - gateOpen=%s entryAllowed=%s spread=%.1f atr=%.2f",
                     m_name,
                     m_gateOpen ? "true" : "false",
                     m_entryAllowed ? "true" : "false",
                     m_lastSpread,
                     m_lastATR);
      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

//+------------------------------------------------------------------+
//| IsTradingSession                                                 |
//+------------------------------------------------------------------+
bool MarketManager::IsTradingSession()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int startMin = m_sessionStarts[now.day_of_week];
   int endMin = m_sessionEnds[now.day_of_week];

   if (startMin < 0)
      return false;
   if (startMin == 0 && endMin == 1440)
      return true;

   int currMin = now.hour * 60 + now.min;
   if (startMin <= endMin)
      return (currMin >= startMin && currMin <= endMin);
   return (currMin >= startMin || currMin <= endMin);
}

//+------------------------------------------------------------------+
//| IsSessionOverlap - Check if currently in overlapping session     |
//+------------------------------------------------------------------+
bool MarketManager::IsSessionOverlap()
{
   DetectSessionOverlaps();
   return m_overlapDetected;
}

//+------------------------------------------------------------------+
//| GetMinutesToSessionClose - Countdown to session end              |
//+------------------------------------------------------------------+
int MarketManager::GetMinutesToSessionClose()
{
   DetectSessionOverlaps();
   
   if(m_activeSessionIndex < 0)
      return -1; // No active session
   
   return m_sessions[m_activeSessionIndex].minutesToClose;
}

//+------------------------------------------------------------------+
//| GetCurrentSessionInfo - Get detailed session information         |
//+------------------------------------------------------------------+
SessionInfo MarketManager::GetCurrentSessionInfo()
{
   DetectSessionOverlaps();
   
   if(m_activeSessionIndex < 0)
   {
      SessionInfo empty;
      ZeroMemory(empty);
      return empty;
   }
   
   return m_sessions[m_activeSessionIndex];
}

//+------------------------------------------------------------------+
//| FetchWebNews - Mendapatkan data berita via WebRequest            |
//+------------------------------------------------------------------+
void MarketManager::FetchWebNews()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   if (MQLInfoInteger(MQL_TESTER))
      return;
   if (TimeCurrent() < m_lastWebFetch + 1800)
      return; // Fetch every 30 mins
   char data[], result[];
   string headers;
   int res = WebRequest("GET", cfg.news_url, NULL, NULL, 5000, data, 0, result, headers);

   if (res != 200)
   {
      m_data.DebugLog(m_debugMode, "WebNews Fetch Failed. HTTP Status: " + (string)res + ", MQL Error: " + (string)GetLastError());
      return;
   }

   string content = CharArrayToString(result);
   ArrayFree(m_webNewsTimes);
   string tagOpen = "<event>", tagClose = "</event>";
   int pos = 0;
   while ((pos = StringFind(content, tagOpen, pos)) >= 0)
   {
      int endPos = StringFind(content, tagClose, pos);
      if (endPos < 0)
         break;

      string eventData = StringSubstr(content, pos, endPos - pos);
      bool isHighImpact = (StringFind(eventData, "High") >= 0 ||
                           (CFG.news.level >= NEWS_HIGH_MEDIUM && StringFind(eventData, "Medium") >= 0));

      bool isRelevant = (StringFind(eventData, m_baseCurr) >= 0 ||
                         StringFind(eventData, m_profitCurr) >= 0 ||
                         StringFind(eventData, "USD") >= 0);

      if (isHighImpact && isRelevant)
      {
         int datePos = StringFind(eventData, "<date>");
         int timePos = StringFind(eventData, "<time>");
         if (datePos >= 0 && timePos >= 0)
         {
            int dateEnd = StringFind(eventData, "</date>", datePos);
            int timeEnd = StringFind(eventData, "</time>", timePos);
            string dateRaw = StringSubstr(eventData, datePos, dateEnd - datePos);
            string timeRaw = StringSubstr(eventData, timePos, timeEnd - timePos);
            string dStr = m_data.StripTags(dateRaw);
            string tStr = m_data.StripTags(timeRaw);
            string dParts[];
            if (StringSplit(dStr, '-', dParts) == 3 && dParts[0] != "" && dParts[1] != "" && dParts[2] != "")
            {
               dStr = dParts[2] + "." + dParts[0] + "." + dParts[1];
               if (dStr == "..")
                  continue;
            }

            string timeOnly = tStr;
            StringReplace(timeOnly, " AM", "");
            StringReplace(timeOnly, " PM", "");
            int sep = StringFind(timeOnly, ":");
            if (sep < 0)
               continue;

            int hr = (int)StringToInteger(StringSubstr(timeOnly, 0, sep));
            int mn = (int)StringToInteger(StringSubstr(timeOnly, sep + 1));

            if (StringFind(tStr, "PM") >= 0 && hr != 12)
               hr += 12;
            else if (StringFind(tStr, "AM") >= 0 && hr == 12)
               hr = 0;
            string finalTime = StringFormat("%02d:%02d", hr, mn);
            datetime eventTime = StringToTime(dStr + " " + finalTime);
            if (eventTime > 0)
            {
               int sz = ArraySize(m_webNewsTimes);
               ArrayResize(m_webNewsTimes, sz + 1, 10); // Use reserve to prevent O(N^2) allocations
               m_webNewsTimes[sz] = eventTime;
            }
         }
      }
      pos = endPos + StringLen(tagClose);
   }
   m_lastWebFetch = TimeCurrent();
}

//+------------------------------------------------------------------+
//| IsNewsTime - Legacy binary check (backward compatibility)        |
//+------------------------------------------------------------------+
bool MarketManager::IsNewsTime()
{
   ENUM_NEWS_IMPACT impact = CalculateNewsImpact();
   return (impact >= NEWS_IMPACT_HIGH);
}

//+------------------------------------------------------------------+
//| IsEntryCooldownActive                                            |
//+------------------------------------------------------------------+
bool MarketManager::IsEntryCooldownActive()
{
   StrategyConfig cfg; m_data.GetConfigCache(cfg);
   MqlRates rates[];
   // FIX: Use closed bar (shift 1) to prevent repainting issues
   if (CopyRates(m_symbol, m_period, 1, 1, rates) <= 0)
      return false;
   datetime currBar = rates[0].time;

   if (m_lastEntryBarTime > 0)
   {
      int barsSinceEntry = (int)((currBar - m_lastEntryBarTime) / PeriodSeconds(m_period));
      if (barsSinceEntry < cfg.entry_cooldown_bars)
      {
         m_data.DebugLog(m_debugMode, "Entry cooldown active (bars: " + (string)barsSinceEntry + ")");
         return true;
      }
   }

   if (m_consecutiveLosses >= cfg.max_consecutive_loss)
   {
      int barsSinceLoss = (int)((currBar - m_lastLossBarTime) / PeriodSeconds(m_period));
      if (barsSinceLoss < cfg.loss_cooldown_bars)
      {
         m_data.DebugLog(m_debugMode, "Loss cooldown active (bars: " + (string)barsSinceLoss + ")");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| UpdateLossStreak                                                 |
//+------------------------------------------------------------------+
void MarketManager::UpdateLossStreak(double netProfit)
{
   if (netProfit < 0)
   {
      m_consecutiveLosses++;
      MqlRates rates[];
      // FIX: Use closed bar (shift 1) to prevent repainting issues
      if (CopyRates(m_symbol, m_period, 1, 1, rates) > 0)
         m_lastLossBarTime = rates[0].time;

      string msg = "Loss Detected! Net Profit: " + DoubleToString(netProfit, 2) +
                   " | Consecutive Losses: " + (string)m_consecutiveLosses;
      if (m_consecutiveLosses >= CFG.risk.maxConsecutiveLoss)
         msg += " | Cooldown Active.";
      m_data.DebugLog(m_debugMode, msg);
   }
   else if (netProfit > 0)
   {
      m_consecutiveLosses = 0;
      m_data.DebugLog(m_debugMode, "Profit Detected! Resetting loss counter.");
   }

   // Update status izin entry dan kirim event jika terjadi perubahan state
   bool entryAllowed = !IsEntryCooldownActive();
   if (entryAllowed != m_entryAllowed)
   {
      m_entryAllowed = entryAllowed;
      if (m_debugMode)
         PrintFormat("[%s] Izin entry berubah menjadi %s akibat hasil trade terakhir.",
                     m_name, m_entryAllowed ? "DIIZINKAN" : "DIBLOKIR");

      MarketGateEvent *evt = new MarketGateEvent(m_gateOpen, m_lastSpread, m_lastATR, m_entryAllowed);
      DispatchEvent(evt);
   }
}

//+------------------------------------------------------------------+
//| DOCUMENTATION: Context-Aware Features Usage Examples             |
//+------------------------------------------------------------------+
/*
====================================================================================
CONTEXT-AWARE MARKET MANAGER V2.1 - USAGE GUIDE
====================================================================================

FITUR BARU:
-----------
1. Dynamic Spread Threshold
   - Threshold spread otomatis menyesuaikan dengan average spread instrumen
   - Rumus: max(static_threshold, avg_spread * 2.5)
   
2. ATR Normalization
   - Normalisasi ATR ke baseline H1 untuk konsistensi lintas timeframe
   - Faktor: sqrt(timeframe_seconds / 3600)
   
3. News Impact Scoring
   - NEWS_IMPACT_NONE    : Tidak ada berita
   - NEWS_IMPACT_LOW     : Berita low impact
   - NEWS_IMPACT_MEDIUM  : Berita medium impact
   - NEWS_IMPACT_HIGH    : Berita high impact (block trading)
   
4. Session Overlap Detection
   - Deteksi otomatis overlap session (London-NY, dll)
   - Informasi minutes-to-close untuk setiap session
   
5. Spread Trend Analysis
   - Tracking spread dengan SMA dan linear regression
   - Early warning saat spread melebar
   
6. Market Regime Integration
   - Integrasi dengan 12.MarketRegime.mqh
   - Block trading saat regime tidak sesuai

CONTOH PENGGUNAAN DI EA:
------------------------

void OnTick()
{
   MarketManager* marketMgr = GetMarketManager();
   
   // 1. Cek news impact level
   ENUM_NEWS_IMPACT newsImpact = marketMgr->GetNewsImpact();
   if(newsImpact == NEWS_IMPACT_HIGH)
   {
      Print("High impact news detected. Skipping trades.");
      return;
   }
   
   // 2. Cek session overlap (volatilitas tinggi)
   if(marketMgr->IsSessionOverlap())
   {
      Print("Session overlap detected. Higher volatility expected.");
      // Optional: Reduce lot size during overlap
   }
   
   // 3. Cek waktu tersisa sebelum session close
   int minsToClose = marketMgr->GetMinutesToSessionClose();
   if(minsToClose > 0 && minsToClose < 30)
   {
      Print("Session closing in ", minsToClose, " minutes. Avoid new entries.");
      return;
   }
   
   // 4. Cek spread trend
   if(marketMgr->IsSpreadTrendWidening())
   {
      Print("WARNING: Spread is widening. Current: ", marketMgr->GetAverageSpread());
      // Optional: Wait for spread to stabilize
   }
   
   // 5. Cek market regime compatibility
   if(!marketMgr->IsRegimeCompatible())
   {
      MultiTFRegimeContext regime = marketMgr->GetCurrentRegime();
      Print("Market regime not compatible: ", regime.Description());
      return;
   }
   
   // 6. Gunakan normalized ATR untuk perbandingan lintas TF
   double currentATR = DataManager::GetATRPoints();
   double normalizedATR = marketMgr->GetNormalizedATR(currentATR);
   Print("Current ATR: ", currentATR, ", Normalized (H1): ", normalizedATR);
   
   // 7. PassesGate sekarang sudah context-aware
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   double spread, atr;
   if(!marketMgr->PassesGate(tick, spread, atr))
   {
      // Gate blocked - cek reason spesifik
      if(spread > marketMgr->GetAverageSpread() * 2.5)
         Print("Spread too high for this instrument");
      return;
   }
   
   // All checks passed - proceed with trading logic
   ...
}

CUSTOM CONFIGURATION:
---------------------
Tambahkan field berikut di StrategyConfig untuk kontrol lebih detail:

- market_regime_enabled (bool)   : Enable/disable regime filtering
- pattern_mean_reversion_mode (bool) : Allow trading in ranging markets
- news_level (enum)              : NEWS_OFF, NEWS_HIGH_ONLY, NEWS_HIGH_MEDIUM, ALL

PERFORMA OPTIMIZATION:
----------------------
- Instrument context di-update setiap 5 menit (bukan setiap tick)
- News impact di-cache selama 5 menit
- Regime check di-throttle 1x per menit
- Spread trend menggunakan circular buffer (max 20 samples)

DEBUG LOGGING:
--------------
Enable debug mode untuk melihat detail:
- Instrument context saat init
- Session overlap detection
- Spread trend warnings
- Regime compatibility checks
- News impact changes

====================================================================================
*/

#endif