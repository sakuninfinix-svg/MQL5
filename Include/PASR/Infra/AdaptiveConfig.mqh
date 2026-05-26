#property strict
#ifndef __INFRA_ADAPTIVE_CONFIG_MQH__
#define __INFRA_ADAPTIVE_CONFIG_MQH__

#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

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

#define PASR_REGIME_POLICY_COUNT 8

struct RegimePolicy
  {
   EMarketRegime regime;
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
   EMarketRegime         regime;
   ENUM_TRADING_SESSION  session;
   ENUM_VOL_TIER         volTier;
  };

class CAdaptiveConfig
  {
private:
   RegimePolicy  m_regimePolicies[PASR_REGIME_POLICY_COUNT];
   SessionPolicy m_sessionPolicies[5];
   VolPolicy     m_volPolicies[3];
   double        m_atrLowThresh;
   double        m_atrHighThresh;

   bool IsValidRegime(EMarketRegime r) const
     { return ((int)r >= 0 && (int)r < PASR_REGIME_POLICY_COUNT); }

   bool IsValidSession(ENUM_TRADING_SESSION s) const
     { return ((int)s >= 0 && (int)s < 5); }

   void PutRegime(EMarketRegime r, double sl, double tp, double score, int conf, ENUM_TRAIL_MODE trail, double be, double lot)
     {
      int i=(int)r;
      if(i<0 || i>=PASR_REGIME_POLICY_COUNT) return;
      m_regimePolicies[i].regime=r;
      m_regimePolicies[i].SLMultiplier=sl;
      m_regimePolicies[i].TPMultiplier=tp;
      m_regimePolicies[i].MinScore=score;
      m_regimePolicies[i].MinConfluence=conf;
      m_regimePolicies[i].TrailMode=trail;
      m_regimePolicies[i].BEFactor=be;
      m_regimePolicies[i].LotFraction=lot;
     }

   void InitDefaults()
     {
      PutRegime(REGIME_UNKNOWN,    1.0, 1.5, 0.65, 3, TRAIL_NONE,  0.3, 0.7);
      PutRegime(REGIME_TREND_UP,   1.5, 3.0, 0.60, 2, TRAIL_ATR,   0.5, 0.9);
      PutRegime(REGIME_TREND_DOWN, 1.5, 3.0, 0.60, 2, TRAIL_ATR,   0.5, 0.9);
      PutRegime(REGIME_RANGE,      1.2, 1.8, 0.65, 3, TRAIL_NONE,  0.4, 0.9);
      PutRegime(REGIME_VOLATILE,   2.0, 2.5, 0.80, 3, TRAIL_SWING, 0.6, 0.5);
      PutRegime(REGIME_TRANSITION, 1.4, 2.0, 0.75, 3, TRAIL_SWING, 0.5, 0.6);
      PutRegime(REGIME_CRASH,      3.0, 1.0, 0.95, 4, TRAIL_NONE,  0.0, 0.0);
      PutRegime(REGIME_SQUEEZE,    1.2, 1.5, 0.90, 4, TRAIL_NONE,  0.3, 0.4);
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

   ENUM_TRADING_SESSION DetectSession() const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      if(h >= 13 && h < 17) return SESSION_OVERLAP;
      if(h >=  8 && h < 13) return SESSION_LONDON;
      if(h >= 17 && h < 22) return SESSION_NEWYORK;
      if(h >=  0 && h <  8) return SESSION_ASIAN;
      return SESSION_OFF;
     }

public:
   CAdaptiveConfig() { InitDefaults(); }

   void SetATRThresholds(double low, double high)
     {
      if(low <= 0 || high <= 0) return;
      if(low >= high) { double tmp=low; low=high; high=tmp; }
      m_atrLowThresh = low;
      m_atrHighThresh = high;
     }

   void SetRegimePolicy(const RegimePolicy &p)
     {
      if(!IsValidRegime(p.regime)) return;
      m_regimePolicies[(int)p.regime] = p;
     }

   void SetSessionPolicy(const SessionPolicy &p)
     {
      if(!IsValidSession(p.session)) return;
      m_sessionPolicies[(int)p.session] = p;
     }

   EffectivePolicy GetEffectivePolicy(EMarketRegime regime, double atrPoints) const
     {
      if(!IsValidRegime(regime)) regime = REGIME_RANGE;
      ENUM_TRADING_SESSION session = DetectSession();
      ENUM_VOL_TIER volTier = ClassifyATR(atrPoints);
      const RegimePolicy &rp = m_regimePolicies[(int)regime];
      const SessionPolicy &sp = m_sessionPolicies[(int)session];
      const VolPolicy &vp = m_volPolicies[(int)volTier];
      EffectivePolicy ep;
      ep.SLMultiplier       = MathMax(0.5, rp.SLMultiplier + vp.SLMultOffset);
      ep.TPMultiplier       = MathMax(ep.SLMultiplier, rp.TPMultiplier);
      ep.MinScore           = MathMax(0.3, MathMin(0.99, rp.MinScore + sp.MinScoreOffset));
      ep.MinConfluence      = rp.MinConfluence;
      ep.TrailMode          = rp.TrailMode;
      ep.BEFactor           = rp.BEFactor;
      ep.LotFraction        = MathMax(0.0, MathMin(rp.LotFraction * sp.LotFraction, 1.0));
      ep.DeviationAtrFactor = vp.DeviationAtrFactor;
      ep.TrailAtrFactor     = vp.TrailAtrFactor;
      ep.regime             = regime;
      ep.session            = session;
      ep.volTier            = volTier;
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

   string RegimeName(EMarketRegime r) const { return MarketRegimeName(r); }

   void LogEffectivePolicy(const EffectivePolicy &ep) const
     {
      PrintFormat("[AdaptiveCfg] Regime=%s Session=%s Vol=%s SL=%.1f TP=%.1f Score>=%.2f Conf>=%d Lot=%.0f%% Trail=%d DEV=%.1f",
         RegimeName(ep.regime), SessionName(ep.session),
         ep.volTier==VOL_LOW?"LOW":ep.volTier==VOL_HIGH?"HIGH":"NORM",
         ep.SLMultiplier, ep.TPMultiplier, ep.MinScore, ep.MinConfluence,
         ep.LotFraction*100.0, (int)ep.TrailMode, ep.DeviationAtrFactor);
     }
  };

#endif // __INFRA_ADAPTIVE_CONFIG_MQH__
