//+------------------------------------------------------------------+
//| Infra/AdaptiveConfig.mqh — v1.00                                  |
//| Adaptive parameter engine: regime + session + volatility policy.  |
//|                                                                   |
//| PURPOSE (Phase 7):                                                |
//|   Single static config (SLMult, TPMult, MinScore, etc.) performs  |
//|   poorly across different market regimes, sessions, and ATR       |
//|   levels. This engine merges 3 policy layers into one resolved    |
//|   EffectivePolicy snapshot per entry — frozen per-ticket so       |
//|   mid-trade regime change does NOT alter active behaviour.        |
//|                                                                   |
//| POLICY LAYERS (applied in order):                                 |
//|   1. RegimePolicy    — TRENDING / RANGING / VOLATILE / QUIET      |
//|   2. SessionPolicy   — ASIAN / LONDON / NEWYORK / OVERLAP         |
//|   3. VolatilityPolicy— LOW_ATR / NORMAL_ATR / HIGH_ATR tier       |
//|                                                                   |
//| OUTPUT:                                                           |
//|   EffectivePolicy    — resolved struct used by RiskManager,       |
//|                        SignalManager, ExecutionManager at entry    |
//|                                                                   |
//| CHANGE LOG:                                                       |
//|   v1.00 (2026-05-21) — Phase 7 initial                            |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_ADAPTIVE_CONFIG_MQH__
#define __INFRA_ADAPTIVE_CONFIG_MQH__

#include "../Core/IManager.mqh"

// ── Regime enum (matches RegimeFilter output) ─────────────────────
enum ENUM_MARKET_REGIME
  {
   REGIME_TRENDING  = 0,
   REGIME_RANGING   = 1,
   REGIME_VOLATILE  = 2,
   REGIME_QUIET     = 3
  };

// ── Session enum ─────────────────────────────────────────────────
enum ENUM_TRADING_SESSION
  {
   SESSION_ASIAN    = 0,
   SESSION_LONDON   = 1,
   SESSION_NEWYORK  = 2,
   SESSION_OVERLAP  = 3,   // London-NY overlap 13:00-17:00 UTC
   SESSION_OFF      = 4    // outside main sessions
  };

// ── ATR volatility tier ──────────────────────────────────────────
enum ENUM_VOL_TIER
  {
   VOL_LOW    = 0,
   VOL_NORMAL = 1,
   VOL_HIGH   = 2
  };

// ── Policy per regime ────────────────────────────────────────────
struct RegimePolicy
  {
   ENUM_MARKET_REGIME regime;
   double  SLMultiplier;     // ATR × this = SL distance
   double  TPMultiplier;     // ATR × this = TP1 distance
   double  MinScore;         // minimum signal score to trade
   int     MinConfluence;    // minimum confluence count
   ENUM_TRAIL_MODE TrailMode;
   double  BEFactor;         // beLevel = entry + ATR*BEFactor
   double  LotFraction;      // fraction of base lot (1.0 = full)
  };

// ── Policy per session ───────────────────────────────────────────
struct SessionPolicy
  {
   ENUM_TRADING_SESSION session;
   double  LotFraction;      // multiply effective lot by this
   double  MinScoreOffset;   // add to MinScore (positive = stricter)
   int     MaxTrades;        // max trades in this session
  };

// ── Policy per volatility tier ───────────────────────────────────
struct VolPolicy
  {
   ENUM_VOL_TIER tier;
   double  DeviationAtrFactor; // ExecutionManager adaptive deviation
   double  SLMultOffset;       // add to SLMultiplier
   double  TrailAtrFactor;     // PositionManager trail distance
  };

// ── Final resolved policy (captured at trade open) ───────────────
struct EffectivePolicy
  {
   double  SLMultiplier;
   double  TPMultiplier;
   double  MinScore;
   int     MinConfluence;
   ENUM_TRAIL_MODE TrailMode;
   double  BEFactor;
   double  LotFraction;        // combined regime × session
   double  DeviationAtrFactor;
   double  TrailAtrFactor;
   // Capture context for audit log
   ENUM_MARKET_REGIME regime;
   ENUM_TRADING_SESSION session;
   ENUM_VOL_TIER volTier;
  };

//+------------------------------------------------------------------+
//| CAdaptiveConfig                                                   |
//+------------------------------------------------------------------+
class CAdaptiveConfig
  {
private:
   // Default regime policies
   RegimePolicy m_regimePolicies[4];
   // Default session policies
   SessionPolicy m_sessionPolicies[5];
   // Default volatility policies
   VolPolicy    m_volPolicies[3];

   // ATR thresholds for tier classification (in points)
   double  m_atrLowThresh;    // below this = VOL_LOW
   double  m_atrHighThresh;   // above this = VOL_HIGH

   void InitDefaults()
     {
      // ── Regime policies ──────────────────────────────────────────
      // TRENDING: wider TP, trail active, lower min score OK
      m_regimePolicies[REGIME_TRENDING] =
        { REGIME_TRENDING, 1.5, 3.0, 0.55, 2, TRAIL_ATR,    0.5, 1.0 };

      // RANGING: tighter TP, no trail (exit at TP), stricter score
      m_regimePolicies[REGIME_RANGING]  =
        { REGIME_RANGING,  1.2, 1.8, 0.65, 3, TRAIL_NONE,   0.4, 0.9 };

      // VOLATILE: wider SL needed, trail by swing, extra confluence
      m_regimePolicies[REGIME_VOLATILE] =
        { REGIME_VOLATILE, 2.0, 2.5, 0.70, 3, TRAIL_SWING,  0.6, 0.8 };

      // QUIET: smallest lot, no trail, strictest score (low reward)
      m_regimePolicies[REGIME_QUIET]    =
        { REGIME_QUIET,    1.0, 1.5, 0.75, 3, TRAIL_NONE,   0.3, 0.7 };

      // ── Session policies ─────────────────────────────────────────
      // Asian: low vol, half lot, stricter score
      m_sessionPolicies[SESSION_ASIAN]   =
        { SESSION_ASIAN,   0.6, +0.05, 2 };

      // London: full vol, standard
      m_sessionPolicies[SESSION_LONDON]  =
        { SESSION_LONDON,  1.0,  0.00, 4 };

      // New York: full vol, slight score relaxation (momentum)
      m_sessionPolicies[SESSION_NEWYORK] =
        { SESSION_NEWYORK, 1.0, -0.02, 4 };

      // Overlap London-NY: best liquidity, allow max trades
      m_sessionPolicies[SESSION_OVERLAP] =
        { SESSION_OVERLAP, 1.0, -0.03, 5 };

      // Off-session: minimal lot, very strict — safety valve
      m_sessionPolicies[SESSION_OFF]     =
        { SESSION_OFF,     0.3, +0.15, 1 };

      // ── Volatility tier policies ─────────────────────────────────
      m_volPolicies[VOL_LOW]    = { VOL_LOW,    0.8, -0.1, 1.2 };
      m_volPolicies[VOL_NORMAL] = { VOL_NORMAL, 1.0,  0.0, 1.5 };
      m_volPolicies[VOL_HIGH]   = { VOL_HIGH,   1.4, +0.3, 2.0 };

      m_atrLowThresh  =  80.0;  // < 80 pts = LOW
      m_atrHighThresh = 200.0;  // > 200 pts = HIGH
     }

   // Classify current ATR into tier
   ENUM_VOL_TIER ClassifyATR(double atrPts) const
     {
      if(atrPts < m_atrLowThresh)  return VOL_LOW;
      if(atrPts > m_atrHighThresh) return VOL_HIGH;
      return VOL_NORMAL;
     }

   // Detect current session from server time (UTC)
   ENUM_TRADING_SESSION DetectSession() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int h = dt.hour;
      // Overlap: London-NY 13:00-17:00 UTC
      if(h >= 13 && h < 17) return SESSION_OVERLAP;
      // London: 08:00-17:00 UTC
      if(h >= 8  && h < 17) return SESSION_LONDON;
      // New York: 13:00-22:00 UTC
      if(h >= 13 && h < 22) return SESSION_NEWYORK;
      // Asian: 00:00-08:00 UTC
      if(h >= 0  && h <  8) return SESSION_ASIAN;
      return SESSION_OFF;
     }

public:
   CAdaptiveConfig() { InitDefaults(); }

   void SetATRThresholds(double low, double high)
     { m_atrLowThresh = low; m_atrHighThresh = high; }

   // Override a regime policy (for custom tuning)
   void SetRegimePolicy(const RegimePolicy &p)
     { m_regimePolicies[(int)p.regime] = p; }

   // Override a session policy
   void SetSessionPolicy(const SessionPolicy &p)
     { m_sessionPolicies[(int)p.session] = p; }

   //+----------------------------------------------------------------+
   //| GetEffectivePolicy — merge all 3 layers into one struct         |
   //| Call at signal confirmation; freeze result in TradePlan.        |
   //+----------------------------------------------------------------+
   EffectivePolicy GetEffectivePolicy(ENUM_MARKET_REGIME regime,
                                      double atrPoints) const
     {
      ENUM_TRADING_SESSION session = DetectSession();
      ENUM_VOL_TIER        volTier = ClassifyATR(atrPoints);

      const RegimePolicy  &rp = m_regimePolicies[(int)regime];
      const SessionPolicy &sp = m_sessionPolicies[(int)session];
      const VolPolicy     &vp = m_volPolicies[(int)volTier];

      EffectivePolicy ep;
      // Base from regime
      ep.SLMultiplier       = rp.SLMultiplier + vp.SLMultOffset;
      ep.TPMultiplier       = rp.TPMultiplier;
      ep.MinScore           = rp.MinScore + sp.MinScoreOffset;
      ep.MinConfluence      = rp.MinConfluence;
      ep.TrailMode          = rp.TrailMode;
      ep.BEFactor           = rp.BEFactor;
      // Combined lot fraction: regime × session (capped at 1.0)
      ep.LotFraction        = MathMin(rp.LotFraction * sp.LotFraction, 1.0);
      // Volatility-specific
      ep.DeviationAtrFactor = vp.DeviationAtrFactor;
      ep.TrailAtrFactor     = vp.TrailAtrFactor;
      // Capture context
      ep.regime   = regime;
      ep.session  = session;
      ep.volTier  = volTier;

      // Safety clamps
      ep.SLMultiplier  = MathMax(0.5, ep.SLMultiplier);
      ep.TPMultiplier  = MathMax(ep.SLMultiplier, ep.TPMultiplier);
      ep.MinScore      = MathMax(0.3, MathMin(0.99, ep.MinScore));
      ep.LotFraction   = MathMax(0.1, ep.LotFraction);

      return ep;
     }

   // Convenience: get session string for logging
   string SessionName(ENUM_TRADING_SESSION s) const
     {
      switch(s)
        {
         case SESSION_ASIAN:   return "Asian";
         case SESSION_LONDON:  return "London";
         case SESSION_NEWYORK: return "NewYork";
         case SESSION_OVERLAP: return "Overlap";
         default:              return "Off";
        }
     }

   string RegimeName(ENUM_MARKET_REGIME r) const
     {
      switch(r)
        {
         case REGIME_TRENDING:  return "Trending";
         case REGIME_RANGING:   return "Ranging";
         case REGIME_VOLATILE:  return "Volatile";
         case REGIME_QUIET:     return "Quiet";
         default:               return "Unknown";
        }
     }

   void LogEffectivePolicy(const EffectivePolicy &ep) const
     {
      PrintFormat(
         "[AdaptiveCfg] Regime=%-9s Session=%-7s Vol=%s "
         "SL=%.1f TP=%.1f Score>=%.2f Conf>=%d "
         "Lot=%.0f%% Trail=%d DEV=%.1f",
         RegimeName(ep.regime),
         SessionName(ep.session),
         ep.volTier==VOL_LOW?"LOW":ep.volTier==VOL_HIGH?"HIGH":"NORM",
         ep.SLMultiplier, ep.TPMultiplier,
         ep.MinScore, ep.MinConfluence,
         ep.LotFraction*100,
         (int)ep.TrailMode,
         ep.DeviationAtrFactor);
     }
  };

#endif // __INFRA_ADAPTIVE_CONFIG_MQH__
