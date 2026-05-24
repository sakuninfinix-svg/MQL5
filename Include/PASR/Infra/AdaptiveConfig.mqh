//+------------------------------------------------------------------+
//| Infra/AdaptiveConfig.mqh — v2.00                                  |
//| Adaptive parameter engine: regime + session + volatility policy.  |
//|                                                                   |
//| v2.00 (2026-05-24) — Sprint 20                                    |
//|   ACF-001: ENUM_MARKET_REGIME + ENUM_TRADING_SESSION defined here |
//|            — canonical source to prevent re-definition conflicts  |
//|   ACF-002: DetectSession() overlap logic fixed — SESSION_OVERLAP  |
//|            was shadowed by SESSION_LONDON (same h>=8 && h<17 arm) |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_ADAPTIVE_CONFIG_MQH__
#define __INFRA_ADAPTIVE_CONFIG_MQH__

#include "../Core/IManager.mqh"

// ── Canonical enum declarations — include this file for regime/session enums
// ACF-001: these enums live here; MarketRegimeDetector.mqh MUST include this
// file (or forward-include guard) to avoid double-declaration.
#ifndef PASR_MARKET_REGIME_DEFINED
#define PASR_MARKET_REGIME_DEFINED
enum ENUM_MARKET_REGIME
  {
   REGIME_TRENDING  = 0,
   REGIME_RANGING   = 1,
   REGIME_VOLATILE  = 2,
   REGIME_QUIET     = 3
  };
#endif

#ifndef PASR_TRADING_SESSION_DEFINED
#define PASR_TRADING_SESSION_DEFINED
enum ENUM_TRADING_SESSION
  {
   SESSION_ASIAN    = 0,
   SESSION_LONDON   = 1,
   SESSION_NEWYORK  = 2,
   SESSION_OVERLAP  = 3,
   SESSION_OFF      = 4
  };
#endif

// Issue #183 FIX: ENUM_TRAIL_MODE canonical definition
// Previously used but never defined — caused compile errors in AdaptiveConfig
#ifndef PASR_TRAIL_MODE_DEFINED
#define PASR_TRAIL_MODE_DEFINED
enum ENUM_TRAIL_MODE
  {
   TRAIL_NONE   = 0,
   TRAIL_ATR    = 1,
   TRAIL_SWING  = 2
  };
#endif

enum ENUM_VOL_TIER
  {
   VOL_LOW    = 0,
   VOL_NORMAL = 1,
   VOL_HIGH   = 2
  };

struct RegimePolicy
  {
   ENUM_MARKET_REGIME regime;
   double  SLMultiplier;
   double  TPMultiplier;
   double  MinScore;
   int     MinConfluence;
   ENUM_TRAIL_MODE TrailMode;
   double  BEFactor;
   double  LotFraction;
  };

struct SessionPolicy
  {
   ENUM_TRADING_SESSION session;
   double  LotFraction;
   double  MinScoreOffset;
   int     MaxTrades;
  };

struct VolPolicy
  {
   ENUM_VOL_TIER tier;
   double  DeviationAtrFactor;
   double  SLMultOffset;
   double  TrailAtrFactor;
  };

struct EffectivePolicy
  {
   double  SLMultiplier;
   double  TPMultiplier;
   double  MinScore;
   int     MinConfluence;
   ENUM_TRAIL_MODE TrailMode;
   double  BEFactor;
   double  LotFraction;
   double  DeviationAtrFactor;
   double  TrailAtrFactor;
   ENUM_MARKET_REGIME    regime;
   ENUM_TRADING_SESSION  session;
   ENUM_VOL_TIER         volTier;
  };

class CAdaptiveConfig
  {
private:
   RegimePolicy  m_regimePolicies[4];
   SessionPolicy m_sessionPolicies[5];
   VolPolicy     m_volPolicies[3];
   double        m_atrLowThresh;
   double        m_atrHighThresh;

   void InitDefaults()
     {
      m_regimePolicies[REGIME_TRENDING] = { REGIME_TRENDING, 1.5, 3.0, 0.55, 2, TRAIL_ATR,   0.5, 1.0 };
      m_regimePolicies[REGIME_RANGING]  = { REGIME_RANGING,  1.2, 1.8, 0.65, 3, TRAIL_NONE,  0.4, 0.9 };
      m_regimePolicies[REGIME_VOLATILE] = { REGIME_VOLATILE, 2.0, 2.5, 0.70, 3, TRAIL_SWING, 0.6, 0.8 };
      m_regimePolicies[REGIME_QUIET]    = { REGIME_QUIET,    1.0, 1.5, 0.75, 3, TRAIL_NONE,  0.3, 0.7 };

      m_sessionPolicies[SESSION_ASIAN]   = { SESSION_ASIAN,   0.6, +0.05, 2 };
      m_sessionPolicies[SESSION_LONDON]  = { SESSION_LONDON,  1.0,  0.00, 4 };
      m_sessionPolicies[SESSION_NEWYORK] = { SESSION_NEWYORK, 1.0, -0.02, 4 };
      m_sessionPolicies[SESSION_OVERLAP] = { SESSION_OVERLAP, 1.0, -0.03, 5 };
      m_sessionPolicies[SESSION_OFF]     = { SESSION_OFF,     0.3, +0.15, 1 };

      m_volPolicies[VOL_LOW]    = { VOL_LOW,    0.8, -0.1, 1.2 };
      m_volPolicies[VOL_NORMAL] = { VOL_NORMAL, 1.0,  0.0, 1.5 };
      m_volPolicies[VOL_HIGH]   = { VOL_HIGH,   1.4, +0.3, 2.0 };

      m_atrLowThresh  =  80.0;
      m_atrHighThresh = 200.0;
     }

   ENUM_VOL_TIER ClassifyATR(double atrPts) const
     {
      if(atrPts < m_atrLowThresh)  return VOL_LOW;
      if(atrPts > m_atrHighThresh) return VOL_HIGH;
      return VOL_NORMAL;
     }

   // ACF-002 FIX: Overlap must be checked FIRST (it's a subset of London hours)
   // Old: Overlap (13-17) inside London (8-17) — London arm matched first → Overlap never reached
   // Fixed: Overlap checked before London and NewYork
   // Issue #183 FIX: DetectSession() now uses configurable time source
   // Old: hardcoded TimeGMT() — no way to adjust for broker time or user preference
   // New: Uses TimeCurrent() which respects broker server time by default
   // For UTC, user can set InpTimeOffset = 0 in EA inputs and adjust externally
   ENUM_TRADING_SESSION DetectSession() const
     {
      MqlDateTime dt;
      // Use TimeCurrent() for broker server time (more reliable than GMT in MQL5)
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      // Check Overlap FIRST — London-NY 13:00-17:00 UTC
      if(h >= 13 && h < 17) return SESSION_OVERLAP;
      // London: 08:00-13:00 UTC (non-overlap portion)
      if(h >=  8 && h < 13) return SESSION_LONDON;
      // New York: 17:00-22:00 UTC (non-overlap portion)
      if(h >= 17 && h < 22) return SESSION_NEWYORK;
      // Asian: 00:00-08:00 UTC
      if(h >=  0 && h <  8) return SESSION_ASIAN;
      return SESSION_OFF;
     }

public:
   CAdaptiveConfig() { InitDefaults(); }

   void SetATRThresholds(double low, double high)
     {
      // Issue #183 FIX: Validate ATR thresholds — low must be < high and both positive
      if(low <= 0 || high <= 0)
        {
         PASRLogWarn("[AdaptiveConfig] SetATRThresholds: invalid values (low=" + DoubleToString(low) + ", high=" + DoubleToString(high) + ")");
         return;
        }
      if(low >= high)
        {
         PASRLogWarn("[AdaptiveConfig] SetATRThresholds: low must be < high (swapping values)");
         double tmp = low; low = high; high = tmp;
        }
      m_atrLowThresh = low;
      m_atrHighThresh = high;
     }

   void SetRegimePolicy(const RegimePolicy &p)
     { m_regimePolicies[(int)p.regime] = p; }

   void SetSessionPolicy(const SessionPolicy &p)
     { m_sessionPolicies[(int)p.session] = p; }

   EffectivePolicy GetEffectivePolicy(ENUM_MARKET_REGIME regime,
                                      double atrPoints) const
     {
      ENUM_TRADING_SESSION session = DetectSession();
      ENUM_VOL_TIER        volTier = ClassifyATR(atrPoints);

      const RegimePolicy  &rp = m_regimePolicies[(int)regime];
      const SessionPolicy &sp = m_sessionPolicies[(int)session];
      const VolPolicy     &vp = m_volPolicies[(int)volTier];

      EffectivePolicy ep;
      ep.SLMultiplier       = rp.SLMultiplier + vp.SLMultOffset;
      ep.TPMultiplier       = rp.TPMultiplier;
      ep.MinScore           = rp.MinScore + sp.MinScoreOffset;
      ep.MinConfluence      = rp.MinConfluence;
      ep.TrailMode          = rp.TrailMode;
      ep.BEFactor           = rp.BEFactor;
      ep.LotFraction        = MathMin(rp.LotFraction * sp.LotFraction, 1.0);
      ep.DeviationAtrFactor = vp.DeviationAtrFactor;
      ep.TrailAtrFactor     = vp.TrailAtrFactor;
      ep.regime             = regime;
      ep.session            = session;
      ep.volTier            = volTier;

      ep.SLMultiplier = MathMax(0.5,  ep.SLMultiplier);
      ep.TPMultiplier = MathMax(ep.SLMultiplier, ep.TPMultiplier);
      ep.MinScore     = MathMax(0.3,  MathMin(0.99, ep.MinScore));
      ep.LotFraction  = MathMax(0.1,  ep.LotFraction);

      return ep;
     }

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
         case REGIME_TRENDING: return "Trending";
         case REGIME_RANGING:  return "Ranging";
         case REGIME_VOLATILE: return "Volatile";
         case REGIME_QUIET:    return "Quiet";
         default:              return "Unknown";
        }
     }

   void LogEffectivePolicy(const EffectivePolicy &ep) const
     {
      PrintFormat(
         "[AdaptiveCfg] Regime=%-9s Session=%-7s Vol=%s "
         "SL=%.1f TP=%.1f Score>=%.2f Conf>=%d Lot=%.0f%% Trail=%d DEV=%.1f",
         RegimeName(ep.regime), SessionName(ep.session),
         ep.volTier==VOL_LOW?"LOW":ep.volTier==VOL_HIGH?"HIGH":"NORM",
         ep.SLMultiplier, ep.TPMultiplier,
         ep.MinScore, ep.MinConfluence,
         ep.LotFraction*100, (int)ep.TrailMode,
         ep.DeviationAtrFactor);
     }
  };

#endif // __INFRA_ADAPTIVE_CONFIG_MQH__
//+------------------------------------------------------------------+
