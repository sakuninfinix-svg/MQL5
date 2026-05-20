//+------------------------------------------------------------------+
//|                                               5.SignalManager.mqh|
//|                                       Copyright 2026, Agsicentre |
//|            Signal Generation & Decision Logic Module             |
//+------------------------------------------------------------------+
//| V2.01 FIXES:                                                     |
//| - SM-BUG-1 [CRITICAL]: Init() used non-existent                 |
//|   GetDataManager().GetManager() — compile error.                 |
//|   Replaced with SetManagers() dependency injection setter.       |
//| - SM-BUG-2 [CRITICAL]: UpdateStats() signalsLastHour counter     |
//|   always reset to 1 — lastSignalTime was overwritten BEFORE      |
//|   the hourly check. Snapshot prevTime before overwrite.          |
//| - SM-BUG-3 [HIGH]: Constructor pre-allocated 100 stale slots.   |
//|   ArrayResize(0) now; AddToHistory() grows on demand.            |
//| - SM-BUG-4 [HIGH]: IsRateLimited() per-bar guard used            |
//|   TimeCurrent()==barTime (true only 1s). Fixed to use            |
//|   iTime(m_symbol,_Period,0)==m_currentBarTime.                   |
//| - SM-BUG-5 [HIGH]: isValid never set true in Generate*Signal()  |
//|   → every emitted event had valid=false. Fixed post-scoring.     |
//| - SM-BUG-6 [MEDIUM]: static lastCheck in OnPriceUpdate() shared  |
//|   across instances. Replaced with member m_lastPriceCheckTime.   |
//| - SM-BUG-7 [MEDIUM]: slMultiplier/tpMultiplier hardcoded 1.5/2.0.|
//|   Now reads Config().sl_atr_mult / Config().tp_atr_mult.         |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.01"
#property strict

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#include "IManager.mqh"
#include "10.DataManager.mqh"
#include "4.SRManager.mqh"
#include "12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Signal Quality Scoring                                           |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_QUALITY
{
   SIGNAL_QUALITY_LOW,       // Score < 40 - Avoid trading
   SIGNAL_QUALITY_MODERATE,  // Score 40-60 - Trade with reduced size
   SIGNAL_QUALITY_HIGH,      // Score 60-80 - Normal trading
   SIGNAL_QUALITY_EXCELLENT  // Score > 80 - High conviction trade
};

//+------------------------------------------------------------------+
//| Signal Reason Codes                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_REASON
{
   SIGNAL_REASON_NONE,
   SIGNAL_REASON_SR_BOUNCE,         // Bounce from S/R level
   SIGNAL_REASON_SR_BREAKOUT,       // Breakout through S/R
   SIGNAL_REASON_PATTERN_COMPLETE,  // Chart pattern completed
   SIGNAL_REASON_REGIME_CHANGE,     // Market regime shift
   SIGNAL_REASON_CONFLUENCE,        // Multiple factors aligned
   SIGNAL_REASON_REVERSAL,          // Reversal pattern detected
   SIGNAL_REASON_CONTINUATION,      // Trend continuation
   SIGNAL_REASON_AI_GENERATED       // AI model generated signal
};

//+------------------------------------------------------------------+
//| Signal Entry Type                                                |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_TYPE
{
   ENTRY_TYPE_MARKET,    // Enter at current market price
   ENTRY_TYPE_LIMIT,     // Wait for pullback to entry zone
   ENTRY_TYPE_STOP,      // Enter on breakout confirmation
   ENTRY_TYPE_SCALE_IN   // Scale into position gradually
};

//+------------------------------------------------------------------+
//| Enhanced Signal Data Structure                                   |
//+------------------------------------------------------------------+
struct SignalData
{
   bool               isValid;
   datetime           timestamp;
   ENUM_ORDER_TYPE    direction;
   double             entryPrice;
   double             slPrice;
   double             tpPrice;
   double             zonePrice;       ///< S/R level that triggered signal
   double             slMultiplier;    ///< ATR multiplier for SL
   double             tpMultiplier;    ///< ATR multiplier for TP
   ENUM_SIGNAL_QUALITY quality;
   ENUM_SIGNAL_REASON  reason;
   ENUM_ENTRY_TYPE     entryType;
   int                 qualityScore;   ///< 0-100 composite score
   string              comment;

   // Additional context
   double             atrValue;
   double             supportLevel;
   double             resistanceLevel;
   ENUM_MARKET_REGIME regime;
   int                timeframe;

   SignalData() : isValid(false), timestamp(0), direction(ORDER_TYPE_BUY),
                  entryPrice(0), slPrice(0), tpPrice(0), zonePrice(0),
                  slMultiplier(1.5), tpMultiplier(2.0),
                  quality(SIGNAL_QUALITY_LOW), reason(SIGNAL_REASON_NONE),
                  entryType(ENTRY_TYPE_MARKET), qualityScore(0),
                  atrValue(0), supportLevel(0), resistanceLevel(0),
                  regime(MARKET_REGIME_UNKNOWN), timeframe(0) {}

   void Reset()
   {
      ZeroMemory(this);
      slMultiplier = 1.5;
      tpMultiplier = 2.0;
   }

   double RiskRewardRatio() const
   {
      if(slPrice <= 0 || tpPrice <= 0) return 0.0;
      double risk   = MathAbs(entryPrice - slPrice);
      double reward = MathAbs(tpPrice   - entryPrice);
      return (risk > 0) ? reward / risk : 0.0;
   }

   string GetQualityString() const
   {
      switch(quality)
      {
         case SIGNAL_QUALITY_LOW:       return "LOW";
         case SIGNAL_QUALITY_MODERATE:  return "MODERATE";
         case SIGNAL_QUALITY_HIGH:      return "HIGH";
         case SIGNAL_QUALITY_EXCELLENT: return "EXCELLENT";
         default:                       return "UNKNOWN";
      }
   }

   string GetReasonString() const
   {
      switch(reason)
      {
         case SIGNAL_REASON_NONE:             return "None";
         case SIGNAL_REASON_SR_BOUNCE:        return "S/R Bounce";
         case SIGNAL_REASON_SR_BREAKOUT:      return "S/R Breakout";
         case SIGNAL_REASON_PATTERN_COMPLETE: return "Pattern Complete";
         case SIGNAL_REASON_REGIME_CHANGE:    return "Regime Change";
         case SIGNAL_REASON_CONFLUENCE:       return "Confluence";
         case SIGNAL_REASON_REVERSAL:         return "Reversal";
         case SIGNAL_REASON_CONTINUATION:     return "Continuation";
         case SIGNAL_REASON_AI_GENERATED:     return "AI Generated";
         default:                             return "Unknown";
      }
   }
};

//+------------------------------------------------------------------+
//| Signal Filter Settings                                           |
//+------------------------------------------------------------------+
struct SignalFilter
{
   int    minQualityScore;      ///< Minimum score to generate signal
   bool   allowCounterTrend;    ///< Allow trades against regime bias
   double minRRRatio;           ///< Minimum risk/reward ratio
   int    maxSignalsPerBar;     ///< Limit signals per bar
   int    maxSignalsPerHour;    ///< Limit signals per hour
   bool   requireConfluence;    ///< Require multiple confirming factors
   double minConfluenceScore;   ///< Minimum confluence score

   SignalFilter() : minQualityScore(50), allowCounterTrend(false),
                    minRRRatio(1.5), maxSignalsPerBar(1),
                    maxSignalsPerHour(3), requireConfluence(true),
                    minConfluenceScore(60) {}
};

//+------------------------------------------------------------------+
//| Signal Statistics                                                |
//+------------------------------------------------------------------+
struct SignalStats
{
   int      totalSignals;
   int      buySignals;
   int      sellSignals;
   int      winningSignals;
   int      losingSignals;
   int      neutralSignals;
   double   avgQualityScore;
   int      signalsLastHour;
   datetime lastSignalTime;
   datetime hourWindowStart; ///< Start of the current 1-hour count window

   SignalStats() : totalSignals(0), buySignals(0), sellSignals(0),
                   winningSignals(0), losingSignals(0), neutralSignals(0),
                   avgQualityScore(0), signalsLastHour(0),
                   lastSignalTime(0), hourWindowStart(0) {}
};

//+------------------------------------------------------------------+
//| SignalManager Class                                              |
//+------------------------------------------------------------------+
class SignalManager : public IManager
{
private:
   SignalData   m_currentSignal;
   SignalData   m_signalHistory[];   ///< SM-BUG-3: starts empty, grows on demand
   SignalFilter m_filter;
   SignalStats  m_stats;

   int          m_maxHistory;
   int          m_signalsThisBar;
   datetime     m_currentBarTime;

   // SM-BUG-1 FIX: injected via SetManagers(), no longer resolved inside Init()
   SRManager    *m_srManager;
   MarketRegime *m_marketRegime;

   datetime     m_lastSignalTime;
   int          m_minSignalIntervalSec;

   // SM-BUG-6 FIX: member variable instead of static local
   datetime     m_lastPriceCheckTime;

private:
   virtual void RefreshConfigCache() override { IManager::RefreshConfigCache(); }

   //--- Calculate signal quality score (0-100)
   int CalculateQualityScore(const SignalData &signal) const
   {
      int score = 0;

      // Confluence scoring (0-30 points)
      if(signal.supportLevel > 0 && signal.resistanceLevel > 0)
      {
         double range      = signal.resistanceLevel - signal.supportLevel;
         double distToZone = MathAbs(signal.entryPrice - signal.zonePrice);

         if(range > 0 && distToZone < range * 0.1)       score += 30;
         else if(distToZone < range * 0.2)                score += 20;
         else if(distToZone < range * 0.3)                score += 10;
      }

      // Regime alignment (0-25 points)
      if(signal.regime == MARKET_REGIME_TRENDING_UP   && signal.direction == ORDER_TYPE_BUY)
         score += 25;
      else if(signal.regime == MARKET_REGIME_TRENDING_DOWN && signal.direction == ORDER_TYPE_SELL)
         score += 25;
      else if(signal.regime == MARKET_REGIME_RANGING)
         score += 15;
      else if(m_filter.allowCounterTrend)
         score += 10;

      // Risk/Reward scoring (0-25 points)
      double rr = signal.RiskRewardRatio();
      if(rr >= 3.0)      score += 25;
      else if(rr >= 2.0) score += 20;
      else if(rr >= 1.5) score += 15;
      else if(rr >= 1.0) score += 10;

      // Reason-based scoring (0-20 points)
      switch(signal.reason)
      {
         case SIGNAL_REASON_CONFLUENCE:        score += 20; break;
         case SIGNAL_REASON_SR_BOUNCE:         score += 15; break;
         case SIGNAL_REASON_PATTERN_COMPLETE:  score += 15; break;
         case SIGNAL_REASON_SR_BREAKOUT:       score += 12; break;
         case SIGNAL_REASON_REGIME_CHANGE:     score += 10; break;
         case SIGNAL_REASON_CONTINUATION:      score += 10; break;
         case SIGNAL_REASON_REVERSAL:          score +=  8; break;
         default:                              score +=  5; break;
      }

      return MathMin(100, score);
   }

   ENUM_SIGNAL_QUALITY ScoreToQuality(int score) const
   {
      if(score >= 80) return SIGNAL_QUALITY_EXCELLENT;
      if(score >= 60) return SIGNAL_QUALITY_HIGH;
      if(score >= 40) return SIGNAL_QUALITY_MODERATE;
      return SIGNAL_QUALITY_LOW;
   }

   bool PassesFilters(const SignalData &signal) const
   {
      if(signal.qualityScore < m_filter.minQualityScore)   return false;
      if(signal.RiskRewardRatio() < m_filter.minRRRatio)   return false;

      if(m_filter.requireConfluence)
         if(signal.supportLevel <= 0 || signal.resistanceLevel <= 0) return false;

      if(!m_filter.allowCounterTrend)
      {
         if(signal.regime == MARKET_REGIME_TRENDING_UP   && signal.direction == ORDER_TYPE_SELL) return false;
         if(signal.regime == MARKET_REGIME_TRENDING_DOWN && signal.direction == ORDER_TYPE_BUY)  return false;
      }

      return true;
   }

   // SM-BUG-4 FIX: use iTime() for per-bar comparison (not TimeCurrent())
   bool IsRateLimited() const
   {
      datetime now    = TimeCurrent();
      datetime barNow = iTime(m_symbol, _Period, 0);

      // Per-bar limit
      if(barNow == m_currentBarTime && m_signalsThisBar >= m_filter.maxSignalsPerBar)
         return true;

      // Per-hour limit — use rolling window
      if(m_stats.signalsLastHour >= m_filter.maxSignalsPerHour)
      {
         if(now - m_stats.hourWindowStart < 3600)
            return true;
      }

      // Minimum interval
      if(now - m_lastSignalTime < m_minSignalIntervalSec)
         return true;

      return false;
   }

   // SM-BUG-5 FIX: set isValid=true after scoring; SM-BUG-7 FIX: use Config() for multipliers
   SignalData GenerateBuySignal(double entryPrice, double zonePrice,
                                ENUM_SIGNAL_REASON reason, string comment = "")
   {
      SignalData signal;
      signal.Reset();

      signal.timestamp  = TimeCurrent();
      signal.direction  = ORDER_TYPE_BUY;
      signal.entryPrice = entryPrice;
      signal.zonePrice  = zonePrice;
      signal.reason     = reason;
      signal.comment    = comment;
      signal.timeframe  = _Period;

      // SM-BUG-7 FIX: read multipliers from Config(), fallback to struct defaults
      signal.slMultiplier = (Config().sl_atr_mult > 0) ? Config().sl_atr_mult : 1.5;
      signal.tpMultiplier = (Config().tp_atr_mult > 0) ? Config().tp_atr_mult : 2.0;

      signal.atrValue        = GetCurrentATR();
      signal.regime          = GetMarketRegime();
      signal.supportLevel    = zonePrice;
      signal.resistanceLevel = GetNearestResistance(entryPrice);

      double atr = (signal.atrValue > 0) ? signal.atrValue : _Point * 100;

      signal.slPrice = entryPrice - (atr * signal.slMultiplier);
      signal.tpPrice = entryPrice + (atr * signal.tpMultiplier);

      if(signal.regime == MARKET_REGIME_TRENDING_UP)
      {
         signal.tpMultiplier = signal.tpMultiplier * 1.25;
         signal.tpPrice      = entryPrice + (atr * signal.tpMultiplier);
      }

      signal.qualityScore = CalculateQualityScore(signal);
      signal.quality      = ScoreToQuality(signal.qualityScore);
      signal.isValid      = true;   // SM-BUG-5 FIX

      return signal;
   }

   SignalData GenerateSellSignal(double entryPrice, double zonePrice,
                                 ENUM_SIGNAL_REASON reason, string comment = "")
   {
      SignalData signal;
      signal.Reset();

      signal.timestamp  = TimeCurrent();
      signal.direction  = ORDER_TYPE_SELL;
      signal.entryPrice = entryPrice;
      signal.zonePrice  = zonePrice;
      signal.reason     = reason;
      signal.comment    = comment;
      signal.timeframe  = _Period;

      // SM-BUG-7 FIX
      signal.slMultiplier = (Config().sl_atr_mult > 0) ? Config().sl_atr_mult : 1.5;
      signal.tpMultiplier = (Config().tp_atr_mult > 0) ? Config().tp_atr_mult : 2.0;

      signal.atrValue        = GetCurrentATR();
      signal.regime          = GetMarketRegime();
      signal.resistanceLevel = zonePrice;
      signal.supportLevel    = GetNearestSupport(entryPrice);

      double atr = (signal.atrValue > 0) ? signal.atrValue : _Point * 100;

      signal.slPrice = entryPrice + (atr * signal.slMultiplier);
      signal.tpPrice = entryPrice - (atr * signal.tpMultiplier);

      if(signal.regime == MARKET_REGIME_TRENDING_DOWN)
      {
         signal.tpMultiplier = signal.tpMultiplier * 1.25;
         signal.tpPrice      = entryPrice - (atr * signal.tpMultiplier);
      }

      signal.qualityScore = CalculateQualityScore(signal);
      signal.quality      = ScoreToQuality(signal.qualityScore);
      signal.isValid      = true;   // SM-BUG-5 FIX

      return signal;
   }

   double GetCurrentATR() const
   {
      return (CheckPointer(m_data) != POINTER_INVALID) ? m_data.GetATR() : _Point * 100;
   }

   ENUM_MARKET_REGIME GetMarketRegime() const
   {
      return (CheckPointer(m_marketRegime) != POINTER_INVALID)
         ? m_marketRegime.GetCurrentRegime()
         : MARKET_REGIME_UNKNOWN;
   }

   double GetNearestSupport(double price) const
   {
      if(CheckPointer(m_srManager) != POINTER_INVALID)
      {
         SRLevel *level = m_srManager.GetNearestSupport(price);
         if(CheckPointer(level) != POINTER_INVALID) return level.price;
      }
      return 0;
   }

   double GetNearestResistance(double price) const
   {
      if(CheckPointer(m_srManager) != POINTER_INVALID)
      {
         SRLevel *level = m_srManager.GetNearestResistance(price);
         if(CheckPointer(level) != POINTER_INVALID) return level.price;
      }
      return 0;
   }

   // SM-BUG-2 FIX: snapshot lastSignalTime BEFORE overwriting so hourly check is correct
   void UpdateStats(const SignalData &signal)
   {
      m_stats.totalSignals++;

      if(signal.direction == ORDER_TYPE_BUY) m_stats.buySignals++;
      else                                    m_stats.sellSignals++;

      m_stats.avgQualityScore =
         (m_stats.avgQualityScore * (m_stats.totalSignals - 1) + signal.qualityScore)
         / m_stats.totalSignals;

      // Hourly window management (SM-BUG-2 FIX)
      datetime now = TimeCurrent();
      if(now - m_stats.hourWindowStart >= 3600)
      {
         m_stats.signalsLastHour = 1;         // reset window
         m_stats.hourWindowStart = now;
      }
      else
         m_stats.signalsLastHour++;

      m_stats.lastSignalTime = signal.timestamp;   // update AFTER hourly check
   }

   // SM-BUG-3 FIX: array starts at 0, grows here only
   void AddToHistory(const SignalData &signal)
   {
      int idx = ArraySize(m_signalHistory);
      if(idx >= m_maxHistory)
      {
         ArrayCopy(m_signalHistory, m_signalHistory, 0, 1, WHOLE_ARRAY);
         ArrayResize(m_signalHistory, m_maxHistory - 1);
         idx = m_maxHistory - 1;
      }
      ArrayResize(m_signalHistory, idx + 1);
      m_signalHistory[idx] = signal;
   }

public:
   // SM-BUG-3 FIX: no pre-allocation; SM-BUG-6 FIX: m_lastPriceCheckTime member init
   SignalManager() : m_maxHistory(100), m_signalsThisBar(0),
                     m_currentBarTime(0), m_srManager(NULL),
                     m_marketRegime(NULL), m_lastSignalTime(0),
                     m_minSignalIntervalSec(5), m_lastPriceCheckTime(0)
   {
      ArrayResize(m_signalHistory, 0);   // SM-BUG-3 FIX: start empty
   }

   virtual ~SignalManager()
   {
      ArrayFree(m_signalHistory);
   }

   // SM-BUG-1 FIX: removed GetDataManager().GetManager() — inject via SetManagers() instead
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      // m_srManager and m_marketRegime must be set via SetManagers()
      // before Init() or after, but will be checked at usage via CheckPointer
      Log("SignalManager initialized (v2.01)");
      return true;
   }

   /// Dependency injection — call from PASR.mqh after all managers are created
   void SetManagers(SRManager *sr, MarketRegime *regime)
   {
      m_srManager   = sr;
      m_marketRegime = regime;
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_PRICE_UPDATE);
   }

   bool TryGenerateSignal(ENUM_ORDER_TYPE direction, double entryPrice,
                          ENUM_SIGNAL_REASON reason, string comment = "")
   {
      if(IsRateLimited())
      {
         if(m_debugMode) Log("Signal rate limited, skipping");
         return false;
      }

      // Sync bar tracker
      datetime barNow = iTime(m_symbol, _Period, 0);
      if(barNow != m_currentBarTime)
      {
         m_currentBarTime = barNow;
         m_signalsThisBar = 0;
      }

      SignalData signal;
      double     zonePrice = 0;

      if(direction == ORDER_TYPE_BUY)
      {
         zonePrice = GetNearestSupport(entryPrice);
         if(zonePrice <= 0) zonePrice = entryPrice;
         signal = GenerateBuySignal(entryPrice, zonePrice, reason, comment);
      }
      else
      {
         zonePrice = GetNearestResistance(entryPrice);
         if(zonePrice <= 0) zonePrice = entryPrice;
         signal = GenerateSellSignal(entryPrice, zonePrice, reason, comment);
      }

      if(!PassesFilters(signal))
      {
         if(m_debugMode)
            Log("Signal filtered — Score: " + IntegerToString(signal.qualityScore));
         return false;
      }

      m_currentSignal  = signal;
      m_signalsThisBar++;
      m_lastSignalTime = TimeCurrent();

      UpdateStats(signal);
      AddToHistory(signal);
      EmitSignalGenerated(signal);

      if(m_debugMode)
         PrintFormat("[Signal] %s | %s | Score:%d | RR:%.2f",
                     signal.GetQualityString(), signal.GetReasonString(),
                     signal.qualityScore, signal.RiskRewardRatio());
      return true;
   }

   void CheckSRBounceSignals(double currentPrice)
   {
      if(CheckPointer(m_srManager) == POINTER_INVALID) return;

      SRLevel *nearestSup = m_srManager.GetNearestSupport(currentPrice);
      SRLevel *nearestRes = m_srManager.GetNearestResistance(currentPrice);
      double   atr        = GetCurrentATR();

      if(CheckPointer(nearestSup) != POINTER_INVALID)
      {
         double distToSup = currentPrice - nearestSup.price;
         if(distToSup < atr * 0.5 && nearestSup.confluenceScore >= 60)
            TryGenerateSignal(ORDER_TYPE_BUY, currentPrice,
                              SIGNAL_REASON_SR_BOUNCE, "Support bounce setup");
      }

      if(CheckPointer(nearestRes) != POINTER_INVALID)
      {
         double distToRes = nearestRes.price - currentPrice;
         if(distToRes < atr * 0.5 && nearestRes.confluenceScore >= 60)
            TryGenerateSignal(ORDER_TYPE_SELL, currentPrice,
                              SIGNAL_REASON_SR_BOUNCE, "Resistance bounce setup");
      }
   }

   void EmitSignalGenerated(const SignalData &signal)
   {
      SignalDecision decision;
      decision.valid       = signal.isValid;   // SM-BUG-5 FIX: now always true for valid signals
      decision.orderType   = signal.direction;
      decision.signalPrice = signal.entryPrice;
      decision.zonePrice   = signal.zonePrice;
      decision.patternType = PATTERN_NONE;
      decision.bias        = (signal.direction == ORDER_TYPE_BUY) ? 1 : -1;
      decision.signalShift = 0;
      decision.slMultiplier = signal.slMultiplier;
      decision.reason      = signal.GetReasonString();

      SignalGeneratedEvent *event = new SignalGeneratedEvent(
         decision,
         signal.atrValue,
         signal.supportLevel,
         signal.resistanceLevel
      );

      if(CheckPointer(event) != POINTER_INVALID)
         DispatchEvent(event);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_currentBarTime = e.barOpenTime;
      m_signalsThisBar = 0;
      CheckSRBounceSignals(e.close);
   }

   // SM-BUG-6 FIX: m_lastPriceCheckTime is now a member, not a static local
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      datetime now = TimeCurrent();
      if(now - m_lastPriceCheckTime < 1) return;
      m_lastPriceCheckTime = now;
      CheckSRBounceSignals(e.tick.bid);
   }

   virtual void OnZoneUpdate(ZoneUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(m_debugMode)
         PrintFormat("[Signal] Zone update — Sup:%.5f Res:%.5f",
                     e.support, e.resistance);
   }

   void              SetFilter(const SignalFilter &filter) { m_filter = filter; }
   const SignalFilter& GetFilter()         const { return m_filter; }
   void              SetMinSignalInterval(int s) { m_minSignalIntervalSec = MathMax(1, s); }

   const SignalData&  GetCurrentSignal()   const { return m_currentSignal; }
   const SignalStats& GetStats()           const { return m_stats; }
   int                GetSignalCount()     const { return m_stats.totalSignals; }

   SignalData* GetSignalHistory(int index)
   {
      if(index < 0 || index >= ArraySize(m_signalHistory)) return NULL;
      return &m_signalHistory[index];
   }
};

#endif // __SIGNAL_MANAGER_MQH__
