//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh — v3.02 (EVENT-DRIVEN + OPTIMIZED)      |
//| Weighted-vote + veto + confidence-multiplier signal aggregation. |
//|                                                                  |
//| [OPTIMIZED] FEATURES FROM GITHUB REFERENCE:                      |
//|   + Event-Driven Architecture (PriceUpdate, NewBar, ZoneUpdate)  |
//|   + Batch Candle Fetching (single CopyRates call per bar)        |
//|   + Modular Filter Pipeline (9 separate boolean filters)         |
//|   + Dual Cooldown System (SignalCooldown + FailedZone)           |
//|   + Zone Reuse Tracking (per-bar zone registration)              |
//|   + Enhanced Config Cache (12+ parameters cached)                |
//|   + MTF Bias Scoring with quality tiers                          |
//|   + CachedMarketData for event-driven data flow                  |
//|                                                                  |
//| SIGNAL SOURCE TYPES (determined by weight parameter):            |
//|   weight > 0  : VOTER   — direction + confidence contribute to   |
//|                           weighted score                         |
//|   weight = 0  : MULT    — direction==NONE, confidence is a       |
//|                           multiplier applied to total score      |
//|   weight < 0  : VETO    — direction==NONE from this source        |
//|                           SUPPRESSES the entire aggregation       |
//|                           (used by RegimeSignalSource VETO mode) |
//|                                                                  |
//| URGENCY TIERS:                                                   |
//|   HIGH   : score >= 0.75  (strong confluence, execute promptly)  |
//|   MEDIUM : score >= 0.55  (good signal, normal execution)        |
//|   LOW    : score <  0.55  (weak, filtered out by default)        |
//|                                                                  |
//| SIGNAL COOLDOWN:                                                 |
//|   After a signal fires in direction D, same direction is blocked |
//|   for N bars (configurable, default=3). Prevents double entries. |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|  v3.02 (2026-05-21) — [OPTIMIZED] GitHub feature adoption:       |
//|    + Event-driven architecture (IEventHandler implementation)    |
//|    + FetchCandleBatch() for optimized data retrieval             |
//|    + 9 Modular Filter Functions (PassZoneTouchFilter, etc.)      |
//|    + Dual Cooldown System (SignalCooldown + FailedZone arrays)   |
//|    + Zone Reuse & Failure tracking per bar                       |
//|    + DetectSignalCore() engine with filter pipeline              |
//|    + TryGenerateSignal() for backward compatibility              |
//|    + CachedMarketData struct for event data caching              |
//|  v3.01 (2026-05-21) — Phase 4 enhancements:                     |
//|    + Config Cache System (CachedConfig struct)                   |
//|    + Batch Candle Fetching (single CopyRates call)               |
//|    + Modular Filter Pipeline (9 separate filter functions)       |
//|    + Zone Reuse & Failure Cooldown (FailedZone structure)        |
//|    + MTF Bias Scoring (High/Medium/Low quality)                  |
//|    + All [OPTIMIZED] comments added                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SIGNAL_MANAGER_MQH__
#define __SIGNAL_SIGNAL_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "ISignalSource.mqh"
#include "SignalFilter.mqh"
#include "../Analysis/Pattern/PatternManager.mqh"
#include "../Data/SRStruct.mqh"
#include "../Data/RegimeTypes.mqh"

#define SIGNAL_MAX_SOURCES 12   // raised from 8 to accommodate all Phase 3+4 sources

//+------------------------------------------------------------------+
//| [OPTIMIZED] Event Types for Event-Driven Architecture            |
//+------------------------------------------------------------------+
enum ENUM_EVENT_TYPE
  {
   EVENT_PRICE_UPDATE = 0,
   EVENT_NEW_BAR      = 1,
   EVENT_ZONE_UPDATE  = 2,
   EVENT_CONFIG_RELOAD = 3,
   EVENT_EMERGENCY_STOP = 4
  };

//+------------------------------------------------------------------+
//| [OPTIMIZED] Signal Cooldown Structure (from GitHub)              |
//| Prevents duplicate signals in same direction within N bars       |
//+------------------------------------------------------------------+
struct SignalCooldown
  {
   double   price;              // Price level of signal
   datetime expiry;             // Expiry timestamp
   
   void Set(double p, datetime exp)
     {
      price  = p;
      expiry = exp;
     }
     
   bool IsActive(datetime now) const
     {
      return (now < expiry);
     }
  };

//+------------------------------------------------------------------+
//| [OPTIMIZED] CachedConfig - Enhanced with 12+ parameters          |
//| Avoids repeated global input parameter lookups every tick        |
//+------------------------------------------------------------------+
struct CachedConfig
  {
   int      signalLookback;           // Bars to scan for patterns
   bool     useMTF;                   // Enable MTF alignment filter
   bool     exitOnOpposite;           // Exit on opposite signal
   double   zoneReuseATR;             // ATR multiplier for zone tolerance
   int      patternFailureCooldownBars; // Bars cooldown after failure
   ENUM_ENTRY_MODE entryMode;         // Entry mode (SAFE/AGGRESSIVE)
   double   maxSignalATR;             // Max candle size for valid signal
   double   antiBreakoutPct;          // Max body/pct ratio
   double   momentumThresholdATR;     // Min momentum in ATR
   double   minTPDistanceATR;         // Min TP distance in ATR
   int      signalCooldownBars;       // Bars between signals
   double   atrBufferMult;            // ATR buffer multiplier
   bool     debugMode;                // Enable debug logging
   datetime lastUpdate;               // Last cache update time
   
   void Init()
     {
      signalLookback                 = 20;
      useMTF                         = true;
      exitOnOpposite                 = false;
      zoneReuseATR                   = 0.5;
      patternFailureCooldownBars     = 5;
      entryMode                      = MODE_SAFE;
      maxSignalATR                   = 2.0;
      antiBreakoutPct                = 0.7;
      momentumThresholdATR           = 0.3;
      minTPDistanceATR               = 1.5;
      signalCooldownBars             = 3;
      atrBufferMult                  = 1.0;
      debugMode                      = false;
      lastUpdate                     = 0;
     }
     
   // [OPTIMIZED] Update cache from global inputs (call only on config change)
   void UpdateFromGlobals()
     {
      // Note: In real implementation, these would read from actual input globals
      // Example: signalLookback = InputSignalLookback; useMTF = InputUseMTF;
      lastUpdate = TimeCurrent();
     }
     
   bool IsStale(int maxAgeSeconds = 60) const
     {
      return (TimeCurrent() - lastUpdate) > maxAgeSeconds;
     }
  };

//+------------------------------------------------------------------+
//| [OPTIMIZED] CachedMarketData - Event-driven data caching         |
//| Stores market data received from ZoneUpdate events               |
//+------------------------------------------------------------------+
struct CachedMarketData
  {
   double atrPoints;
   double support, resistance;
   double htfSupport, htfResistance;
   bool   isSupBroken, isResBroken;
   double supBufferMult, resBufferMult;
   int    supHtfAlign, resHtfAlign;

   void Reset() 
     { 
      ZeroMemory(this); 
     }
  };

//+------------------------------------------------------------------+
//| [OPTIMIZED] FailedZone Structure for Zone Reuse & Cooldown       |
//| Tracks zones that caused StopLoss to prevent immediate re-entry  |
//+------------------------------------------------------------------+
struct FailedZone
  {
   double   priceLevel;         // Price level of failed zone
   datetime failTime;           // Time of failure
   int      failBar;            // Bar index of failure
   ENUM_SIGNAL_DIR failDir;     // Direction that failed
   int      cooldownRemaining;  // Bars remaining in cooldown
   
   void Set(double price, datetime time, int bar, ENUM_SIGNAL_DIR dir, int cooldown)
     {
      priceLevel      = price;
      failTime        = time;
      failBar         = bar;
      failDir         = dir;
      cooldownRemaining = cooldown;
     }
     
   bool IsActive() const
     {
      return cooldownRemaining > 0;
     }
     
   void Tick()
     {
      if(cooldownRemaining > 0) cooldownRemaining--;
     }
  };

//+------------------------------------------------------------------+
//| [OPTIMIZED] Signal Quality Score for MTF Bias Scoring            |
//| High Quality (>80), Medium (50-80), Low (<50)                    |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_QUALITY
  {
   SIGNAL_QUALITY_HIGH   = 0,   // Score > 80 (strong confluence)
   SIGNAL_QUALITY_MEDIUM = 1,   // Score 50-80 (moderate confluence)
   SIGNAL_QUALITY_LOW    = 2    // Score < 50 (weak signal)
  };

enum ENUM_SIGNAL_URGENCY
  {
   SIGNAL_URGENCY_HIGH   = 0,   // score >= 0.75
   SIGNAL_URGENCY_MEDIUM = 1,   // score >= 0.55
   SIGNAL_URGENCY_LOW    = 2    // score <  0.55 (filtered by default)
  };

// Final signal state emitted by SignalManager
struct FinalSignal
  {
   ENUM_SIGNAL_DIR     direction;
   double              score;        // 0.0-1.0 aggregate weighted score
   double              confidence;   // alias for score (backward-compat)
   int                 confluence;   // count of agreeing voter sources
   ENUM_SIGNAL_URGENCY urgency;      // HIGH / MEDIUM / LOW
   string              sources;      // names of agreeing sources
   datetime            time;

   void Clear()
     {
      direction=SIGNAL_NONE; score=0; confidence=0; confluence=0;
      urgency=SIGNAL_URGENCY_LOW; sources=""; time=0;
     }
  };

//+------------------------------------------------------------------+
//| CSignalManager — aggregates multiple ISignalSource votes         |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   ISignalSource   *m_sources[SIGNAL_MAX_SOURCES];
   int              m_sourceCount;
   double           m_weights[SIGNAL_MAX_SOURCES];  // >0=voter, 0=mult, <0=veto

   CPatternManager *m_pattern;
   CSRManager      *m_sr;
   CMarketRegime   *m_regime;
   CSignalFilter   *m_filter;

   FinalSignal      m_current;
   FinalSignal      m_previous;
   bool             m_signalReady;

   int              m_minConfluence;   // min voter sources that must agree
   double           m_minScore;        // min normalised weighted score (0-1)
   int              m_cooldownBars;    // bars before same direction repeatable
   int              m_barsSinceSignal; // counter: incremented each OnNewBar()
   ENUM_SIGNAL_DIR  m_lastDirection;  // direction of last emitted signal

   // [OPTIMIZED] Event-Driven State & Cache (from GitHub)
   bool             m_hasNewTick;
   bool             m_hasNewBar;
   MqlTick          m_cachedTick;
   datetime         m_lastProcessedBar;
   bool             m_signalPending;
   
   // [OPTIMIZED] Dual Cooldown Arrays (SignalCooldown + FailedZone)
   SignalCooldown   m_signalCooldowns[];  // Prevents duplicate signals
   FailedZone       m_failedZones[];      // Tracks failed zones
   
   // [OPTIMIZED] Cached data from events
   CachedConfig     m_cfgCache;           // Config parameters cache
   CachedMarketData m_marketData;         // Market data from ZoneUpdate events

   // ── Urgency helper ──────────────────────────────────────────────
   ENUM_SIGNAL_URGENCY ScoreToUrgency(double score) const
     {
      if(score >= 0.75) return SIGNAL_URGENCY_HIGH;
      if(score >= 0.55) return SIGNAL_URGENCY_MEDIUM;
      return SIGNAL_URGENCY_LOW;
     }

   // [OPTIMIZED] Config Cache Management (from GitHub)
   void RefreshConfigCache()
     {
      // Note: Replace with actual global input references in production
      m_cfgCache.signalLookback                 = 20;  // CFG.SignalLookback
      m_cfgCache.useMTF                         = true; // CFG.UseMTF
      m_cfgCache.exitOnOpposite                 = false; // CFG.ExitOnOpposite
      m_cfgCache.zoneReuseATR                   = 0.5; // CFG.ZoneReuseATR
      m_cfgCache.patternFailureCooldownBars     = 5; // CFG.PatternFailureCooldownBars
      m_cfgCache.entryMode                      = MODE_SAFE; // CFG.EntryMode
      m_cfgCache.maxSignalATR                   = 2.0; // CFG.MaxSignalATR
      m_cfgCache.antiBreakoutPct                = 0.7; // CFG.AntiBreakoutPct
      m_cfgCache.momentumThresholdATR           = 0.3; // CFG.MomentumThresholdATR
      m_cfgCache.minTPDistanceATR               = 1.5; // CFG.MinTPDistanceATR
      m_cfgCache.signalCooldownBars             = 3; // CFG.SignalCooldownBars
      m_cfgCache.atrBufferMult                  = 1.0; // CFG.ATRBufferMult
      m_cfgCache.debugMode                      = false; // CFG.DebugMode
     }

   // [OPTIMIZED] Batch Candle Fetching - Single CopyRates call (from GitHub)
   bool FetchCandleBatch(int shiftStart, int count, MqlRates &outRates[])
     {
      ArraySetAsSeries(outRates, true);
      int copied = CopyRates(_Symbol, _Period, shiftStart, count, outRates);
      return (copied > 0);
     }

   // [OPTIMIZED] Zone Reuse Check - Per-bar zone registration (from GitHub)
   bool IsZoneReuseBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      datetime currBar = iTime(_Symbol, _Period, 0);
      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;

      if(isBuy)
         return (m_lastBuyZoneBar == currBar && MathAbs(zonePrice - m_lastBuyZonePrice) <= tol);
      return (m_lastSellZoneBar == currBar && MathAbs(zonePrice - m_lastSellZonePrice) <= tol);
     }

   void RegisterZoneUse(bool isBuy, double zonePrice)
     {
      datetime currBar = iTime(_Symbol, _Period, 0);
      if(isBuy) {
         m_lastBuyZonePrice = zonePrice;
         m_lastBuyZoneBar = currBar;
      } else {
         m_lastSellZonePrice = zonePrice;
         m_lastSellZoneBar = currBar;
      }
     }

   // [OPTIMIZED] Pattern Failure Cooldown (from GitHub)
   bool IsPatternFailureBlocked(bool isBuy, double zonePrice, double atrPoints)
     {
      datetime now = TimeCurrent();
      double tol = atrPoints * m_cfgCache.zoneReuseATR * _Point;

      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--)
        {
         if(MathAbs(zonePrice - m_failedZones[i].priceLevel) <= tol)
            return true;
        }
      return false;
     }

   void CleanupFailedZones()
     {
      datetime now = TimeCurrent();
      int count = ArraySize(m_failedZones);
      if(count <= 0) return;

      for(int i = ArraySize(m_failedZones) - 1; i >= 0; i--) {
         if(now > m_failedZones[i].failTime + (m_cfgCache.patternFailureCooldownBars * PeriodSeconds())) {
            ArrayDelete(m_failedZones, i);
         }
      }
     }

   void RegisterFailure(bool isBuy, double zonePrice)
     {
      int sz = ArraySize(m_failedZones);
      ArrayResize(m_failedZones, sz + 1);
      m_failedZones[sz].priceLevel = zonePrice;
      m_failedZones[sz].failTime = TimeCurrent();
      m_failedZones[sz].failBar = iBars(_Symbol, _Period) - 1;
      m_failedZones[sz].failDir = isBuy ? SIGNAL_BUY : SIGNAL_SELL;
      m_failedZones[sz].cooldownRemaining = m_cfgCache.patternFailureCooldownBars;

      if(m_cfgCache.debugMode)
         PrintFormat("[PASR Signal] Level %.5f registered as FAILED. Cooldown %d candles.",
                    zonePrice, m_cfgCache.patternFailureCooldownBars);
     }

   // [OPTIMIZED] Signal Cooldown Management (from GitHub)
   bool IsSignalCooldownActive(double price, ENUM_ORDER_TYPE orderType)
     {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--)
        {
         if(now > m_signalCooldowns[i].expiry) continue;

         // Check if price is within tolerance
         double tol = m_data.GetATRPoints() * m_cfgCache.zoneReuseATR * _Point;
         if(MathAbs(price - m_signalCooldowns[i].price) <= tol)
           {
            // Check if same direction
            if((orderType == ORDER_TYPE_BUY && m_signalCooldowns[i].price < price) ||
               (orderType == ORDER_TYPE_SELL && m_signalCooldowns[i].price > price))
               return true;
           }
        }
      return false;
     }

   void RegisterSignalCooldown(double price, ENUM_ORDER_TYPE orderType)
     {
      int sz = ArraySize(m_signalCooldowns);
      ArrayResize(m_signalCooldowns, sz + 1);
      m_signalCooldowns[sz].price = price;
      m_signalCooldowns[sz].expiry = TimeCurrent() + (m_cfgCache.signalCooldownBars * PeriodSeconds());

      if(m_cfgCache.debugMode)
         PrintFormat("[PASR Signal] Signal cooldown registered @ %.5f for %d bars.",
                    price, m_cfgCache.signalCooldownBars);
     }

   void CleanupSignalCooldowns()
     {
      datetime now = TimeCurrent();
      for(int i = ArraySize(m_signalCooldowns) - 1; i >= 0; i--) {
         if(now > m_signalCooldowns[i].expiry) {
            ArrayDelete(m_signalCooldowns, i);
         }
      }
     }

   // [OPTIMIZED] MTF Bias Helper (from GitHub)
   int GetMTFBias(double price, double htfSupport, double htfResistance, double atrPoints)
     {
      if(!m_cfgCache.useMTF) return 0;

      double zone = (atrPoints * m_cfgCache.atrBufferMult) * _Point;
      bool nearHtfSupport = (price <= htfSupport + zone);
      bool nearHtfResistance = (price >= htfResistance - zone);

      if(nearHtfSupport && !nearHtfResistance) return 1;
      if(nearHtfResistance && !nearHtfSupport) return -1;
      return 0;
     }

   // ── Core aggregation ─────────────────────────────────────────────
   FinalSignal AggregateVotes()
     {
      FinalSignal sig;
      sig.Clear();
      sig.time = TimeCurrent();

      double bullScore   = 0.0, bearScore  = 0.0;
      double totalVoterW = 0.0;
      double multFactor  = 1.0;   // product of all multiplier confidences
      int    bullCount   = 0,    bearCount  = 0;
      string bullSrc     = "",   bearSrc    = "";

      for(int i = 0; i < m_sourceCount; i++)
        {
         if(m_sources[i] == NULL) continue;

         SignalResult r; r.Clear();
         if(!m_sources[i].Evaluate(r)) continue;

         double w = m_weights[i];

         // ── VETO source (weight < 0): if it returns NONE, suppress all
         if(w < 0.0)
           {
            if(r.direction == SIGNAL_NONE)
              {
               if(m_debugMode)
                  PrintFormat("[Signal] VETO by %s: %s",
                              m_sources[i].Name(), r.reason);
               return sig;   // early return: fully suppressed
              }
            continue;   // veto source voted a direction = no veto, skip weight
           }

         // ── MULTIPLIER source (weight == 0): direction ignored, confidence scales total
         if(w == 0.0)
           {
            if(r.confidence > 0.0) multFactor *= r.confidence;
            if(m_debugMode)
               PrintFormat("[Signal]   MULT %s: x%.2f (%s)",
                           m_sources[i].Name(), r.confidence, r.reason);
            continue;
           }

         // ── VOTER source (weight > 0): normal weighted contribution
         totalVoterW += w;

         if(r.direction == SIGNAL_BUY)
           {
            bullScore += r.confidence * w;
            bullCount++;
            bullSrc += (bullSrc=="" ? "" : ",") + m_sources[i].Name();
           }
         else if(r.direction == SIGNAL_SELL)
           {
            bearScore += r.confidence * w;
            bearCount++;
            bearSrc += (bearSrc=="" ? "" : ",") + m_sources[i].Name();
           }

         if(m_debugMode)
            PrintFormat("[Signal]   VOTE %s(w=%.1f): %s conf=%.2f %s",
                        m_sources[i].Name(), w,
                        r.direction==SIGNAL_BUY ? "BUY" :
                        r.direction==SIGNAL_SELL? "SELL": "NONE",
                        r.confidence, r.reason);
        }

      if(totalVoterW <= 0.0) return sig;

      // Normalise + apply multiplier
      double normBull = (bullScore / totalVoterW) * multFactor;
      double normBear = (bearScore / totalVoterW) * multFactor;

      if(m_debugMode)
         PrintFormat("[Signal] Scores  BUY=%.3f SELL=%.3f (x%.2f mult)",
                     normBull, normBear, multFactor);

      // Determine winner
      if(normBull > normBear
         && bullCount  >= m_minConfluence
         && normBull   >= m_minScore)
        {
         sig.direction  = SIGNAL_BUY;
         sig.score      = normBull;
         sig.confidence = normBull;
         sig.confluence = bullCount;
         sig.sources    = bullSrc;
         sig.urgency    = ScoreToUrgency(normBull);
        }
      else if(normBear > normBull
              && bearCount  >= m_minConfluence
              && normBear   >= m_minScore)
        {
         sig.direction  = SIGNAL_SELL;
         sig.score      = normBear;
         sig.confidence = normBear;
         sig.confluence = bearCount;
         sig.sources    = bearSrc;
         sig.urgency    = ScoreToUrgency(normBear);
        }

      return sig;
     }

   // ── Cooldown check ───────────────────────────────────────────────
   bool IsCoolingDown(ENUM_SIGNAL_DIR dir) const
     {
      if(m_cooldownBars <= 0) return false;
      if(dir != m_lastDirection) return false;   // different direction = OK
      return (m_barsSinceSignal < m_cooldownBars);
     }

public:
   CSignalManager()
      : IManager(), m_sourceCount(0),
        m_pattern(NULL), m_sr(NULL), m_regime(NULL), m_filter(NULL),
        m_signalReady(false),
        m_minConfluence(2), m_minScore(0.45),
        m_cooldownBars(3), m_barsSinceSignal(999),
        m_lastDirection(SIGNAL_NONE),
        m_hasNewTick(false), m_hasNewBar(false),
        m_lastProcessedBar(0), m_signalPending(false)
     {
      ArrayInitialize(m_weights, 1.0);
      for(int i=0;i<SIGNAL_MAX_SOURCES;i++) m_sources[i]=NULL;
      m_current.Clear(); m_previous.Clear();
      m_cfgCache.Init();
      m_marketData.Reset();
     }

   virtual void Deinit() override 
     { 
      ArrayFree(m_failedZones);
      ArrayFree(m_signalCooldowns);
      m_signalPending = false;
      if(m_filter != NULL) { delete m_filter; m_filter=NULL; } 
     }

   // ── Dependency injection
   void SetPatternManager(CPatternManager *p) { m_pattern = p; }
   void SetSRManager(CSRManager *sr)           { m_sr      = sr; }
   void SetRegimeManager(CMarketRegime *r)     { m_regime  = r; }

   // ── Register a signal source plugin
   // weight >0 = voter, =0 = multiplier, <0 = veto
   bool RegisterSource(ISignalSource *src, double weight=1.0)
     {
      if(m_sourceCount >= SIGNAL_MAX_SOURCES) return false;
      m_sources[m_sourceCount] = src;
      m_weights[m_sourceCount] = weight;
      m_sourceCount++;
      if(m_debugMode)
         PrintFormat("[Signal] Registered: %s (w=%.1f %s)",
                     src.Name(), weight,
                     weight<0 ? "VETO" : weight==0 ? "MULT" : "VOTER");
      return true;
     }

   // ── Configuration
   void SetMinConfluence(int v)    { m_minConfluence = MathMax(1, v); }
   void SetMinScore(double v)      { m_minScore      = MathMax(0.0, MathMin(1.0, v)); }
   void SetCooldownBars(int v)     { m_cooldownBars  = MathMax(0, v); }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      // [OPTIMIZED] Event-driven events from GitHub
      AddEvent("PriceUpdate");
      AddEvent("NewBar");
      AddEvent("ZoneUpdate");
      AddEvent("EmergencyStop");
      AddEvent("Heartbeat");
     }

   // [OPTIMIZED] Event Handler: PriceUpdate - Cache tick, don't process yet (from GitHub)
   virtual void OnPriceUpdate(PriceUpdateEvent* e) override
     {
      if(CheckPointer(e) == POINTER_INVALID) return;
      m_cachedTick = e.tick;
      m_hasNewTick = true;
     }

   // [OPTIMIZED] Event Handler: NewBar - MAIN SIGNAL DETECTION TRIGGER (from GitHub)
   virtual void OnNewBar(NewBarEvent* e) override
     {
      if(CheckPointer(e) == POINTER_INVALID || !m_initialized) return;
      if(e.barOpenTime == m_lastProcessedBar) return;
      if(!m_hasNewTick) return;

      ProcessSignalOnNewBar(e);
      m_lastProcessedBar = e.barOpenTime;
      m_hasNewTick = false;
      
      // Also run legacy OnNewBar for backward compatibility
      RunLegacyOnNewBar();
     }

   // [OPTIMIZED] Event Handler: ConfigReload (from GitHub)
   virtual void OnConfigReload(ConfigReloadEvent* e) override
     {
      RefreshConfigCache();
     }

   // [OPTIMIZED] Event Handler: EmergencyStop (from GitHub)
   virtual void OnEmergencyStop(EmergencyStopEvent* e) override
     {
      m_signalPending = false;
      if(m_cfgCache.debugMode) Log("Emergency Stop: Clearing pending signals.");
     }

   // [OPTIMIZED] Event Handler: Heartbeat - Cleanup expired cooldowns (from GitHub)
   virtual void OnHeartbeat(HeartbeatEvent* e) override
     {
      CleanupFailedZones();
      CleanupSignalCooldowns();
     }

   // [OPTIMIZED] Event Handler: Custom ZoneUpdate event (from GitHub)
   virtual void OnCustomEvent(Event* e) override 
     {
      if(e.Type() == "ZoneUpdate") 
        {
         ZoneUpdateEvent* ze = (ZoneUpdateEvent*)e;
         m_marketData.atrPoints      = ze.atrPoints;
         m_marketData.support        = ze.support;
         m_marketData.resistance     = ze.resistance;
         m_marketData.htfSupport     = ze.htfSupport;
         m_marketData.htfResistance  = ze.htfResistance;
         m_marketData.isSupBroken    = ze.isSupBroken;
         m_marketData.isResBroken    = ze.isResBroken;
         m_marketData.supBufferMult  = ze.supBufferMult;
         m_marketData.resBufferMult  = ze.resBufferMult;
         m_marketData.supHtfAlign    = ze.supHtfAlign;
         m_marketData.resHtfAlign    = ze.resHtfAlign;
        }
     }

   // Legacy OnNewBar for backward compatibility
   void RunLegacyOnNewBar()
     {
      m_barsSinceSignal++;
      m_signalReady = false;
      m_previous    = m_current;
      m_current.Clear();

      // 1) Pre-filter chain (session, spread, news, etc.)
      if(m_filter != NULL)
        {
         FilterResult fr = m_filter.Run();
         if(!fr.passed)
           {
            if(m_debugMode)
               PrintFormat("[Signal] PreFilter blocked: %s", fr.reason);
            return;
           }
        }

      if(m_debugMode)
         PrintFormat("[Signal] OnNewBar — evaluating %d sources:", m_sourceCount);

      // 2) Aggregate all registered sources (veto → mult → voters)
      m_current = AggregateVotes();

      if(m_current.direction == SIGNAL_NONE) return;

      // 3) Urgency filter: only emit MEDIUM+ by default
      if(m_current.urgency == SIGNAL_URGENCY_LOW)
        {
         if(m_debugMode)
            PrintFormat("[Signal] Score=%.2f below MEDIUM threshold (0.55) — suppressed",
                        m_current.score);
         m_current.Clear();
         return;
        }

      // 4) Cooldown: suppress same direction within N bars
      if(IsCoolingDown(m_current.direction))
        {
         if(m_debugMode)
            PrintFormat("[Signal] Cooldown: %s again in %d/%d bars — suppressed",
                        m_current.direction==SIGNAL_BUY?"BUY":"SELL",
                        m_barsSinceSignal, m_cooldownBars);
         m_current.Clear();
         return;
        }

      // 5) Signal is valid — emit
      m_signalReady         = true;
      m_lastDirection       = m_current.direction;
      m_barsSinceSignal     = 0;

      PrintFormat("[Signal] ★ %s score=%.2f urgency=%s confluence=%d src=[%s]",
                  m_current.direction==SIGNAL_BUY ? "BUY" : "SELL",
                  m_current.score,
                  m_current.urgency==SIGNAL_URGENCY_HIGH   ? "HIGH"   :
                  m_current.urgency==SIGNAL_URGENCY_MEDIUM ? "MEDIUM" : "LOW",
                  m_current.confluence, m_current.sources);

      PASREvent ev;
      ev.id       = EVENT_ID_SIGNAL_READY;
      ev.priority = 30;
      DispatchEvent(ev);
     }

   // ── Accessors
   FinalSignal GetCurrent()  const { return m_current;     }
   FinalSignal GetPrevious() const { return m_previous;    }
   bool        HasSignal()   const { return m_signalReady; }
   int         SourceCount() const { return m_sourceCount; }

   // [OPTIMIZED] Integration Methods (from GitHub) - Backward compatibility
   bool TryGenerateSignal(SignalDecision &outDecision,
                         double atrPoints,
                         double support, double resistance,
                         double htfSupport, double htfResistance,
                         bool isSupBroken, bool isResBroken,
                         double supBufferMult, double resBufferMult,
                         int supHtfAlign, int resHtfAlign)
     {
      // Direct call to core detection logic
      bool found = DetectSignalCore(outDecision, atrPoints, support, resistance,
                                   htfSupport, htfResistance, isSupBroken, isResBroken,
                                   supBufferMult, resBufferMult, supHtfAlign, resHtfAlign);

      // If signal found, also dispatch event for other modules
      if(found && outDecision.valid)
        {
         SignalGeneratedEvent* sigEvent = new SignalGeneratedEvent(
            outDecision, atrPoints, support, resistance
         );
         EventBus::Instance().Dispatch(sigEvent);
        }

      return found;
     }

   // Register a failed zone externally (e.g., from TradeManager on loss)
   void NotifyPatternFailure(bool isBuy, double zonePrice)
     {
      RegisterFailure(isBuy, zonePrice);
     }

   // Get pending signal (if any) - for polling-style integration
   bool HasPendingSignal(SignalDecision &outSignal)
     {
      if(m_signalPending) {
         outSignal = m_pendingSignal;
         m_signalPending = false;
         return true;
      }
      return false;
     }

private:
   // [OPTIMIZED] Main processing method called on NewBar event (from GitHub)
   void ProcessSignalOnNewBar(NewBarEvent* e)
     {
      // Use cached data from ZoneUpdateEvent
      double atrPoints      = m_marketData.atrPoints;
      double support        = m_marketData.support;
      double resistance     = m_marketData.resistance;
      double htfSupport     = m_marketData.htfSupport;
      double htfResistance  = m_marketData.htfResistance;
      bool   isSupBroken    = m_marketData.isSupBroken;
      bool   isResBroken    = m_marketData.isResBroken;
      double supBufferMult  = m_marketData.supBufferMult;
      double resBufferMult  = m_marketData.resBufferMult;
      int    supHtfAlign    = m_marketData.supHtfAlign;
      int    resHtfAlign    = m_marketData.resHtfAlign;

      if(atrPoints <= 0 || support <= 0 || resistance <= 0) {
         if(m_cfgCache.debugMode) Print("[SignalManager] Missing data for signal detection");
         return;
      }

      // Run core detection
      SignalDecision decision;
      if(DetectSignalCore(decision, atrPoints, support, resistance,
                         htfSupport, htfResistance, isSupBroken, isResBroken,
                         supBufferMult, resBufferMult, supHtfAlign, resHtfAlign))
        {
         // Signal found! Dispatch to ExecutionManager via event
         SignalGeneratedEvent* sigEvent = new SignalGeneratedEvent(
            decision, atrPoints, support, resistance
         );
         EventBus::Instance().Dispatch(sigEvent);

         RegisterSignalCooldown(decision.signalPrice, decision.orderType);
         
         // Also buffer for polling-style access (backward compat)
         m_pendingSignal = decision;
         m_signalPending = true;
        }
     }

   // [OPTIMIZED] Core Signal Detection Engine with Filter Pipeline (from GitHub)
   bool DetectSignalCore(SignalDecision &decision,
                        double atrPoints,
                        double support, double resistance,
                        double htfSupport, double htfResistance,
                        bool isSupBroken, bool isResBroken,
                        double supBufferMult, double resBufferMult,
                        int supHtfAlign, int resHtfAlign)
     {
      ZeroMemory(decision);
      string reason = "No pattern detected";

      // Validate data availability
      if(iBars(_Symbol, _Period) < m_cfgCache.signalLookback + 5) {
         decision.reason = "Insufficient history data";
         return false;
      }

      // === OPTIMIZATION: Batch fetch candles once ===
      MqlRates rates[];
      if(!FetchCandleBatch(1, m_cfgCache.signalLookback + 3, rates)) {
         decision.reason = "Failed to fetch candle data";
         return false;
      }

      // Scan patterns in lookback window
      for(int shift = 1; shift <= m_cfgCache.signalLookback; shift++)
        {
         string currentFilterReason = "";
         int dir = 0;
         double signalPrice = 0;
         ENUM_PATTERN_TYPE pType = PATTERN_NONE;
         string patternReason = "";

         // Pattern detection via PatternManager
         if(m_pattern == NULL || !m_pattern.Detect(rates, shift, atrPoints, pType, dir, signalPrice, patternReason))
            continue;

         double zonePrice = (dir == 1) ? support : resistance;
         double currentBufferMult = (dir == 1) ? supBufferMult : resBufferMult;
         int currentHtfAlign = (dir == 1) ? supHtfAlign : resHtfAlign;

         // === FILTER PIPELINE ===
         // 1. HTF Alignment Filter
         if(m_cfgCache.useMTF && currentHtfAlign < 0) {
            reason = (dir == 1) ? "HTF Contra-Support" : "HTF Contra-Resistance";
            continue;
         }

         // 2. Zone Broken Filter
         if((dir == 1 && isSupBroken) || (dir == -1 && isResBroken)) {
            reason = "Zone broken (Price closed outside)";
            continue;
         }

         // 3. Zone Touch Filter
         if(!PassZoneTouchFilter(shift, dir, zonePrice, atrPoints, currentBufferMult, currentFilterReason, rates)) {
            reason = currentFilterReason; continue;
         }

         // 4. Context/Momentum Filter
         if(!PassContextFilter(shift, atrPoints, currentFilterReason, rates, dir)) {
            reason = currentFilterReason; continue;
         }

         // 5. MTF Quality Filter
         int bias = 0;
         if(!PassMTFFilter(dir, rates[shift].close, htfSupport, htfResistance,
                          atrPoints, bias, currentFilterReason)) {
            reason = currentFilterReason; continue;
         }

         // 6. Opportunity/R:R Filter
         if(!PassOpportunityFilter(dir, shift, atrPoints, support, resistance,
                                  signalPrice, currentFilterReason, rates)) {
            reason = currentFilterReason; continue;
         }

         // 7. Zone Reuse Filter
         if(IsZoneReuseBlocked(dir == 1, zonePrice, atrPoints)) {
            reason = "Zone reuse blocked"; continue;
         }

         // 8. Pattern Failure Cooldown
         if(IsPatternFailureBlocked(dir == 1, zonePrice, atrPoints)) {
            reason = "Level failure cooldown"; continue;
         }

         // 9. Signal Cooldown Filter
         if(IsSignalCooldownActive(signalPrice, (dir==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL)) {
             reason = "Signal cooldown active"; continue;
         }

         // === SIGNAL FOUND: Populate decision struct ===
         decision.valid = true;
         decision.orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         decision.signalPrice = signalPrice;
         decision.patternType = pType;
         decision.zonePrice = zonePrice;
         decision.signalShift = shift;
         decision.bias = bias;
         decision.reason = patternReason + (currentFilterReason != "" ? " | " + currentFilterReason : "");

         // Register zone usage to prevent duplicate signals
         RegisterZoneUse(dir == 1, zonePrice);

         if(m_cfgCache.debugMode)
            PrintFormat("[PASR Signal] ✓ %s @ %.5f | Pattern: %s | %s",
                       (dir==1?"BUY":"SELL"), signalPrice, EnumToString(pType), decision.reason);

         return true; // Early return on first valid signal
        }

      // No signal found
      decision.reason = (reason == "") ? "No signal" : reason;
      return false;
     }

   // [OPTIMIZED] Filter 1: Zone Touch Filter (from GitHub)
   bool PassZoneTouchFilter(int shift, int dir, double zonePrice,
                           double atrPoints, double dynamicMult, string &reason,
                           const MqlRates &rates)
     {
      double extreme = (dir == 1) ? rates[shift].low : rates[shift].high;
      double zoneWidth = (atrPoints * dynamicMult) * _Point;
      double multiplier = (m_cfgCache.entryMode == MODE_SAFE) ? 0.5 : 1.0;

      bool ok = (dir == 1) ?
                (extreme <= zonePrice + (zoneWidth * multiplier)) :
                (extreme >= zonePrice - (zoneWidth * multiplier));

      if(!ok) reason = "Not touching zone";
      return ok;
     }

   // [OPTIMIZED] Filter 2: Context/Momentum Filter (from GitHub)
   bool PassContextFilter(int shift, double atrPoints, string &reason,
                         const MqlRates &rates, int dir)
     {
      double o = rates[shift].open, h = rates[shift].high;
      double l = rates[shift].low, c = rates[shift].close;
      double range = h - l;
      double body = MathAbs(o - c);

      if(range > m_cfgCache.maxSignalATR * atrPoints * _Point)
         { reason = "Signal too large"; return false; }
      if((body / range) > m_cfgCache.antiBreakoutPct)
         { reason = "Body too long"; return false; }

      // Filter Momentum: Cek 1-3 candle sebelumnya
      double threshold = atrPoints * m_cfgCache.momentumThresholdATR * _Point;
      int pushCount = 0;

      for(int i = 1; i <= 3 && (shift + i) < ArraySize(rates); i++)
        {
         double curO = rates[shift + i].open, curC = rates[shift + i].close;
         double curH = rates[shift + i].high, curL = rates[shift + i].low;
         double prevH = rates[shift + i + 1].high, prevL = rates[shift + i + 1].low;
         double curBody = MathAbs(curO - curC);

         bool isPush = (dir == 1) ?
                      (curH < prevH || (curC < curO && curBody > threshold)) :
                      (curL > prevL || (curC > curO && curBody > threshold));

         if(isPush) pushCount++;
         else break;
        }

      if(pushCount < 1) { reason = "No momentum push to zone"; return false; }
      return true;
     }

   // [OPTIMIZED] Filter 3: MTF Quality Filter (from GitHub)
   bool PassMTFFilter(int dir, double referencePrice,
                     double htfSupport, double htfResistance,
                     double atrPoints, int &bias, string &reason)
     {
      bias = GetMTFBias(referencePrice, htfSupport, htfResistance, atrPoints);

      if(!m_cfgCache.useMTF) return true;

      int qualityScore = dir * bias;

      if(qualityScore == 1) {
         reason = "High Quality Signal (MTF Aligned)";
         return true;
      }
      if(qualityScore == 0) {
         reason = "Standard Quality Signal (MTF Neutral)";
         return true;
      }

      reason = "Low Quality (Blocked by MTF Contra-Bias)";
      return false;
     }

   // [OPTIMIZED] Filter 4: Opportunity/R:R Filter (from GitHub)
   bool PassOpportunityFilter(int dir, int shift, double atrPoints,
                             double support, double resistance,
                             double signalPrice, string &reason,
                             const MqlRates &rates)
     {
      double target = (dir == 1) ? resistance : support;
      double profitDist = (dir == 1) ? (target - signalPrice) : (signalPrice - target);

      double minTPDist = (atrPoints * m_cfgCache.minTPDistanceATR) * _Point;
      if(profitDist < minTPDist) { reason = "TP distance < Min ATR"; return false; }

      return true;
     }

public:
   // Zone tracking variables for IsZoneReuseBlocked
   double         m_lastBuyZonePrice;
   double         m_lastSellZonePrice;
   datetime       m_lastBuyZoneBar;
   datetime       m_lastSellZoneBar;
   SignalDecision m_pendingSignal;
  };

typedef CSignalManager SignalManager;
#endif // __SIGNAL_SIGNAL_MANAGER_MQH__
