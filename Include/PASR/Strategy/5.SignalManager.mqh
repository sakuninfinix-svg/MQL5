//+------------------------------------------------------------------+
//|                                               5.SignalManager.mqh|
//|                                       Copyright 2026, Agsicentre |
//|            Signal Generation & Decision Logic Module             |
//+------------------------------------------------------------------+
//| PURPOSE: Generates trading signals based on S/R confluence,      |
//|          market regime, pattern recognition, and risk assessment.|
//|          Implements signal filtering and quality scoring.        |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property link      "agsicentre.wordpress.com"
#property version   "2.00"
#property strict

#ifndef __SIGNAL_MANAGER_MQH__
#define __SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Infrastructure/10.DataManager.mqh"
#include "../Data/4.SRManager.mqh"
#include "../Infrastructure/12.MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Signal Quality Scoring                                           |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_QUALITY
{
   SIGNAL_QUALITY_LOW,      // Score < 40 - Avoid trading
   SIGNAL_QUALITY_MODERATE, // Score 40-60 - Trade with reduced size
   SIGNAL_QUALITY_HIGH,     // Score 60-80 - Normal trading
   SIGNAL_QUALITY_EXCELLENT // Score > 80 - High conviction trade
};

//+------------------------------------------------------------------+
//| Signal Reason Codes                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_REASON
{
   SIGNAL_REASON_NONE,
   SIGNAL_REASON_SR_BOUNCE,       // Bounce from S/R level
   SIGNAL_REASON_SR_BREAKOUT,     // Breakout through S/R
   SIGNAL_REASON_PATTERN_COMPLETE,// Chart pattern completed
   SIGNAL_REASON_REGIME_CHANGE,   // Market regime shift
   SIGNAL_REASON_CONFLUENCE,      // Multiple factors aligned
   SIGNAL_REASON_REVERSAL,        // Reversal pattern detected
   SIGNAL_REASON_CONTINUATION,    // Trend continuation
   SIGNAL_REASON_AI_GENERATED     // AI model generated signal
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
   double             zonePrice;         // S/R level that triggered signal
   double             slMultiplier;      // ATR multiplier for SL
   double             tpMultiplier;      // ATR multiplier for TP
   ENUM_SIGNAL_QUALITY quality;
   ENUM_SIGNAL_REASON reason;
   ENUM_ENTRY_TYPE    entryType;
   int                qualityScore;      // 0-100 composite score
   string             comment;
   
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
      double risk = MathAbs(entryPrice - slPrice);
      double reward = MathAbs(tpPrice - entryPrice);
      return (risk > 0) ? reward / risk : 0.0;
   }
   
   string GetQualityString() const
   {
      switch(quality)
      {
         case SIGNAL_QUALITY_LOW:      return "LOW";
         case SIGNAL_QUALITY_MODERATE: return "MODERATE";
         case SIGNAL_QUALITY_HIGH:     return "HIGH";
         case SIGNAL_QUALITY_EXCELLENT:return "EXCELLENT";
         default: return "UNKNOWN";
      }
   }
   
   string GetReasonString() const
   {
      switch(reason)
      {
         case SIGNAL_REASON_NONE:          return "None";
         case SIGNAL_REASON_SR_BOUNCE:     return "S/R Bounce";
         case SIGNAL_REASON_SR_BREAKOUT:   return "S/R Breakout";
         case SIGNAL_REASON_PATTERN_COMPLETE: return "Pattern Complete";
         case SIGNAL_REASON_REGIME_CHANGE: return "Regime Change";
         case SIGNAL_REASON_CONFLUENCE:    return "Confluence";
         case SIGNAL_REASON_REVERSAL:      return "Reversal";
         case SIGNAL_REASON_CONTINUATION:  return "Continuation";
         case SIGNAL_REASON_AI_GENERATED:  return "AI Generated";
         default: return "Unknown";
      }
   }
};

//+------------------------------------------------------------------+
//| Signal Filter Settings                                           |
//+------------------------------------------------------------------+
struct SignalFilter
{
   int    minQualityScore;       // Minimum score to generate signal
   bool   allowCounterTrend;     // Allow trades against regime bias
   double minRRRatio;            // Minimum risk/reward ratio
   int    maxSignalsPerBar;      // Limit signals per bar
   int    maxSignalsPerHour;     // Limit signals per hour
   bool   requireConfluence;     // Require multiple confirming factors
   double minConfluenceScore;    // Minimum confluence score
   
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
   int    totalSignals;
   int    buySignals;
   int    sellSignals;
   int    winningSignals;
   int    losingSignals;
   int    neutralSignals;
   double avgQualityScore;
   int    signalsLastHour;
   datetime lastSignalTime;
   
   SignalStats() : totalSignals(0), buySignals(0), sellSignals(0),
                   winningSignals(0), losingSignals(0), neutralSignals(0),
                   avgQualityScore(0), signalsLastHour(0), lastSignalTime(0) {}
};

//+------------------------------------------------------------------+
//| SignalManager Class                                              |
//+------------------------------------------------------------------+
class SignalManager : public IManager
{
private:
   SignalData   m_currentSignal;
   SignalData   m_signalHistory[];
   SignalFilter m_filter;
   SignalStats  m_stats;
   
   int          m_maxHistory;
   int          m_signalsThisBar;
   datetime     m_currentBarTime;
   
   // Dependencies (injected or looked up)
   SRManager    *m_srManager;
   MarketRegime *m_marketRegime;
   
   // Throttle to prevent signal spam
   datetime     m_lastSignalTime;
   int          m_minSignalIntervalSec;
   
private:
   //--- Calculate signal quality score (0-100)
   int CalculateQualityScore(const SignalData &signal) const
   {
      int score = 0;
      
      // Confluence scoring (0-30 points)
      if(signal.supportLevel > 0 && signal.resistanceLevel > 0)
      {
         double range = signal.resistanceLevel - signal.supportLevel;
         double distToZone = MathAbs(signal.entryPrice - signal.zonePrice);
         
         if(range > 0 && distToZone < range * 0.1)
            score += 30; // Price near key zone
         else if(distToZone < range * 0.2)
            score += 20;
         else if(distToZone < range * 0.3)
            score += 10;
      }
      
      // Regime alignment (0-25 points)
      if(signal.regime == MARKET_REGIME_TRENDING_UP && signal.direction == ORDER_TYPE_BUY)
         score += 25;
      else if(signal.regime == MARKET_REGIME_TRENDING_DOWN && signal.direction == ORDER_TYPE_SELL)
         score += 25;
      else if(signal.regime == MARKET_REGIME_RANGING)
         score += 15; // Neutral regime, partial points
      else if(m_filter.allowCounterTrend)
         score += 10; // Counter-trend allowed but penalized
      
      // Risk/Reward scoring (0-25 points)
      double rr = signal.RiskRewardRatio();
      if(rr >= 3.0)      score += 25;
      else if(rr >= 2.0) score += 20;
      else if(rr >= 1.5) score += 15;
      else if(rr >= 1.0) score += 10;
      
      // Reason-based scoring (0-20 points)
      switch(signal.reason)
      {
         case SIGNAL_REASON_CONFLUENCE:     score += 20; break;
         case SIGNAL_REASON_SR_BOUNCE:      score += 15; break;
         case SIGNAL_REASON_PATTERN_COMPLETE: score += 15; break;
         case SIGNAL_REASON_SR_BREAKOUT:    score += 12; break;
         case SIGNAL_REASON_REGIME_CHANGE:  score += 10; break;
         case SIGNAL_REASON_CONTINUATION:   score += 10; break;
         case SIGNAL_REASON_REVERSAL:       score += 8; break;
         default: score += 5;
      }
      
      return MathMin(100, score);
   }
   
   //--- Determine signal quality enum from score
   ENUM_SIGNAL_QUALITY ScoreToQuality(int score) const
   {
      if(score >= 80) return SIGNAL_QUALITY_EXCELLENT;
      if(score >= 60) return SIGNAL_QUALITY_HIGH;
      if(score >= 40) return SIGNAL_QUALITY_MODERATE;
      return SIGNAL_QUALITY_LOW;
   }
   
   //--- Check if signal passes filters
   bool PassesFilters(const SignalData &signal) const
   {
      // Quality threshold
      if(signal.qualityScore < m_filter.minQualityScore)
         return false;
      
      // Risk/Reward threshold
      if(signal.RiskRewardRatio() < m_filter.minRRRatio)
         return false;
      
      // Confluence requirement
      if(m_filter.requireConfluence)
      {
         if(signal.supportLevel <= 0 || signal.resistanceLevel <= 0)
            return false;
      }
      
      // Counter-trend filter
      if(!m_filter.allowCounterTrend)
      {
         if(signal.regime == MARKET_REGIME_TRENDING_UP && signal.direction == ORDER_TYPE_SELL)
            return false;
         if(signal.regime == MARKET_REGIME_TRENDING_DOWN && signal.direction == ORDER_TYPE_BUY)
            return false;
      }
      
      return true;
   }
   
   //--- Rate limiting
   bool IsRateLimited() const
   {
      datetime now = TimeCurrent();
      
      // Per-bar limit
      if(now == m_currentBarTime && m_signalsThisBar >= m_filter.maxSignalsPerBar)
         return true;
      
      // Per-hour limit
      if(m_stats.signalsLastHour >= m_filter.maxSignalsPerHour)
      {
         datetime hourAgo = now - 3600;
         if(m_stats.lastSignalTime > hourAgo)
            return true;
      }
      
      // Minimum interval
      if(now - m_lastSignalTime < m_minSignalIntervalSec)
         return true;
      
      return false;
   }
   
   //--- Generate BUY signal
   SignalData GenerateBuySignal(double entryPrice, double zonePrice, 
                                ENUM_SIGNAL_REASON reason, string comment = "")
   {
      SignalData signal;
      signal.Reset();
      
      signal.timestamp = TimeCurrent();
      signal.direction = ORDER_TYPE_BUY;
      signal.entryPrice = entryPrice;
      signal.zonePrice = zonePrice;
      signal.reason = reason;
      signal.comment = comment;
      signal.timeframe = _Period;
      
      // Get current market context
      signal.atrValue = GetCurrentATR();
      signal.regime = GetMarketRegime();
      signal.supportLevel = zonePrice;
      signal.resistanceLevel = GetNearestResistance(entryPrice);
      
      // Calculate SL/TP
      double atr = signal.atrValue;
      if(atr <= 0) atr = _Point * 100;
      
      signal.slPrice = entryPrice - (atr * signal.slMultiplier);
      signal.tpPrice = entryPrice + (atr * signal.tpMultiplier);
      
      // Adjust for regime
      if(signal.regime == MARKET_REGIME_TRENDING_UP)
      {
         signal.tpMultiplier = 2.5; // Let winners run in uptrend
         signal.tpPrice = entryPrice + (atr * signal.tpMultiplier);
      }
      
      // Calculate quality
      signal.qualityScore = CalculateQualityScore(signal);
      signal.quality = ScoreToQuality(signal.qualityScore);
      
      return signal;
   }
   
   //--- Generate SELL signal
   SignalData GenerateSellSignal(double entryPrice, double zonePrice,
                                 ENUM_SIGNAL_REASON reason, string comment = "")
   {
      SignalData signal;
      signal.Reset();
      
      signal.timestamp = TimeCurrent();
      signal.direction = ORDER_TYPE_SELL;
      signal.entryPrice = entryPrice;
      signal.zonePrice = zonePrice;
      signal.reason = reason;
      signal.comment = comment;
      signal.timeframe = _Period;
      
      // Get current market context
      signal.atrValue = GetCurrentATR();
      signal.regime = GetMarketRegime();
      signal.resistanceLevel = zonePrice;
      signal.supportLevel = GetNearestSupport(entryPrice);
      
      // Calculate SL/TP
      double atr = signal.atrValue;
      if(atr <= 0) atr = _Point * 100;
      
      signal.slPrice = entryPrice + (atr * signal.slMultiplier);
      signal.tpPrice = entryPrice - (atr * signal.tpMultiplier);
      
      // Adjust for regime
      if(signal.regime == MARKET_REGIME_TRENDING_DOWN)
      {
         signal.tpMultiplier = 2.5;
         signal.tpPrice = entryPrice - (atr * signal.tpMultiplier);
      }
      
      // Calculate quality
      signal.qualityScore = CalculateQualityScore(signal);
      signal.quality = ScoreToQuality(signal.qualityScore);
      
      return signal;
   }
   
   double GetCurrentATR() const
   {
      if(CheckPointer(m_data) != POINTER_INVALID)
         return m_data.GetATR();
      return _Point * 100;
   }
   
   ENUM_MARKET_REGIME GetMarketRegime() const
   {
      if(CheckPointer(m_marketRegime) != POINTER_INVALID)
         return m_marketRegime.GetCurrentRegime();
      return MARKET_REGIME_UNKNOWN;
   }
   
   double GetNearestSupport(double price) const
   {
      if(CheckPointer(m_srManager) != POINTER_INVALID)
      {
         SRLevel *level = m_srManager.GetNearestSupport(price);
         if(CheckPointer(level) != POINTER_INVALID)
            return level.price;
      }
      return 0;
   }
   
   double GetNearestResistance(double price) const
   {
      if(CheckPointer(m_srManager) != POINTER_INVALID)
      {
         SRLevel *level = m_srManager.GetNearestResistance(price);
         if(CheckPointer(level) != POINTER_INVALID)
            return level.price;
      }
      return 0;
   }
   
   void UpdateStats(const SignalData &signal)
   {
      m_stats.totalSignals++;
      
      if(signal.direction == ORDER_TYPE_BUY)
         m_stats.buySignals++;
      else
         m_stats.sellSignals++;
      
      m_stats.avgQualityScore = (m_stats.avgQualityScore * (m_stats.totalSignals - 1) + 
                                 signal.qualityScore) / m_stats.totalSignals;
      
      m_stats.lastSignalTime = signal.timestamp;
      
      // Update hourly counter
      if(TimeCurrent() - m_stats.lastSignalTime < 3600)
         m_stats.signalsLastHour++;
      else
         m_stats.signalsLastHour = 1;
   }
   
   void AddToHistory(const SignalData &signal)
   {
      int idx = ArraySize(m_signalHistory);
      ArrayResize(m_signalHistory, idx + 1);
      m_signalHistory[idx] = signal;
      
      // Trim history if needed
      if(ArraySize(m_signalHistory) > m_maxHistory)
      {
         ArrayCopy(m_signalHistory, m_signalHistory, 0, 1, WHOLE_ARRAY);
         ArrayResize(m_signalHistory, m_maxHistory);
      }
   }
   
public:
   SignalManager() : m_maxHistory(100), m_signalsThisBar(0),
                     m_currentBarTime(0), m_srManager(NULL),
                     m_marketRegime(NULL), m_lastSignalTime(0),
                     m_minSignalIntervalSec(5)
   {
      ArrayResize(m_signalHistory, m_maxHistory);
   }
   
   virtual ~SignalManager()
   {
      ArrayFree(m_signalHistory);
   }
   
   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      
      // Try to get references to dependent managers
      // In production, these would be injected via dependency injection
      m_srManager = (SRManager*)GetDataManager().GetManager("SRManager");
      m_marketRegime = (MarketRegime*)GetDataManager().GetManager("MarketRegime");
      
      Log("✅ SignalManager initialized");
      return true;
   }
   
   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_ZONE_UPDATE);
      AddEvent(EVENT_ID_NEW_BAR);
   }
   
   //--- Main signal generation method
   bool TryGenerateSignal(ENUM_ORDER_TYPE direction, double entryPrice,
                          ENUM_SIGNAL_REASON reason, string comment = "")
   {
      // Check rate limits
      if(IsRateLimited())
      {
         if(m_debugMode)
            Log("⏸️ Signal rate limited, skipping");
         return false;
      }
      
      // Check if new bar
      datetime barTime = iTime(m_symbol, _Period, 0);
      if(barTime != m_currentBarTime)
      {
         m_currentBarTime = barTime;
         m_signalsThisBar = 0;
      }
      
      SignalData signal;
      double zonePrice = 0;
      
      // Get zone price based on direction
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
      
      // Apply filters
      if(!PassesFilters(signal))
      {
         if(m_debugMode)
            Log("🚫 Signal filtered out - Score: " + IntegerToString(signal.qualityScore));
         return false;
      }
      
      // Emit signal event
      m_currentSignal = signal;
      m_signalsThisBar++;
      m_lastSignalTime = TimeCurrent();
      
      UpdateStats(signal);
      AddToHistory(signal);
      
      EmitSignalGenerated(signal);
      
      Log("📊 Signal Generated: " + signal.GetQualityString() + 
          " | " + signal.GetReasonString() +
          " | Score: " + IntegerToString(signal.qualityScore) +
          " | RR: " + DoubleToString(signal.RiskRewardRatio(), 2));
      
      return true;
   }
   
   //--- Check for S/R bounce signals
   void CheckSRBounceSignals(double currentPrice)
   {
      if(CheckPointer(m_srManager) == POINTER_INVALID) return;
      
      SRLevel *nearestSup = m_srManager.GetNearestSupport(currentPrice);
      SRLevel *nearestRes = m_srManager.GetNearestResistance(currentPrice);
      
      // Check support bounce
      if(CheckPointer(nearestSup) != POINTER_INVALID)
      {
         double distToSup = currentPrice - nearestSup.price;
         double atr = GetCurrentATR();
         
         if(distToSup < atr * 0.5 && nearestSup.confluenceScore >= 60)
         {
            // Price near strong support - potential BUY
            TryGenerateSignal(ORDER_TYPE_BUY, currentPrice, 
                             SIGNAL_REASON_SR_BOUNCE, "Support bounce setup");
         }
      }
      
      // Check resistance bounce
      if(CheckPointer(nearestRes) != POINTER_INVALID)
      {
         double distToRes = nearestRes.price - currentPrice;
         double atr = GetCurrentATR();
         
         if(distToRes < atr * 0.5 && nearestRes.confluenceScore >= 60)
         {
            // Price near strong resistance - potential SELL
            TryGenerateSignal(ORDER_TYPE_SELL, currentPrice,
                             SIGNAL_REASON_SR_BOUNCE, "Resistance bounce setup");
         }
      }
   }
   
   //--- Emit signal event to EventBus
   void EmitSignalGenerated(const SignalData &signal)
   {
      SignalDecision decision;
      decision.valid = signal.isValid;
      decision.orderType = signal.direction;
      decision.signalPrice = signal.entryPrice;
      decision.zonePrice = signal.zonePrice;
      decision.patternType = PATTERN_NONE;
      decision.bias = (signal.direction == ORDER_TYPE_BUY) ? 1 : -1;
      decision.signalShift = 0;
      decision.slMultiplier = signal.slMultiplier;
      decision.reason = signal.GetReasonString();
      
      SignalGeneratedEvent *event = new SignalGeneratedEvent(
         decision,
         signal.atrValue,
         signal.supportLevel,
         signal.resistanceLevel
      );
      
      if(CheckPointer(event) != POINTER_INVALID)
         DispatchEvent(event);
   }
   
   //--- Event handlers
   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Reset per-bar counters
      m_currentBarTime = e.barOpenTime;
      m_signalsThisBar = 0;
      
      // Check for signals on new bar
      double currentPrice = e.close;
      CheckSRBounceSignals(currentPrice);
   }
   
   virtual void OnPriceUpdate(PriceUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Only check on significant price moves (throttle)
      static datetime lastCheck = 0;
      datetime now = TimeCurrent();
      
      if(now - lastCheck < 1) return; // Check every second max
      lastCheck = now;
      
      CheckSRBounceSignals(e.tick.bid);
   }
   
   virtual void OnZoneUpdate(ZoneUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      
      // Zone updated - may trigger signal re-evaluation
      if(m_debugMode)
         Log("📍 Zone update received - Sup: " + DoubleToString(e.support, _Digits) +
             " Res: " + DoubleToString(e.resistance, _Digits));
   }
   
   //--- Configuration
   void SetFilter(const SignalFilter &filter) { m_filter = filter; }
   const SignalFilter& GetFilter() const { return m_filter; }
   
   void SetMinSignalInterval(int seconds) 
   { 
      m_minSignalIntervalSec = MathMax(1, seconds); 
   }
   
   //--- Accessors
   const SignalData& GetCurrentSignal() const { return m_currentSignal; }
   const SignalStats& GetStats() const { return m_stats; }
   
   int GetSignalCount() const { return m_stats.totalSignals; }
   
   SignalData* GetSignalHistory(int index)
   {
      if(index < 0 || index >= ArraySize(m_signalHistory))
         return NULL;
      return &m_signalHistory[index];
   }
};

#endif // __SIGNAL_MANAGER_MQH__
