#property strict
#ifndef __INFRA_ADAPTIVE_CONFIG_MQH__
#define __INFRA_ADAPTIVE_CONFIG_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"
#include "../Data/RegimeTypes.mqh"

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
   double        m_aiConfidenceThreshold;
   double        m_lastAIAccuracy;

   bool IsValidRegime(EMarketRegime r) const
     { return ((int)r >= 0 && (int)r < PASR_REGIME_POLICY_COUNT); }

   int SessionIndex(ENUM_TRADING_SESSION s) const
     {
      switch(s)
        {
         case SESSION_TOKYO:    return 0;
         case SESSION_LONDON:   return 1;
         case SESSION_NEW_YORK: return 2;
         case SESSION_OVERLAP:  return 3;
         default:               return 4;
        }
     }

   bool IsValidSession(ENUM_TRADING_SESSION s) const
     { int idx = SessionIndex(s); return (idx >= 0 && idx < 5); }

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

      m_sessionPolicies[0] = { SESSION_TOKYO,    0.6, +0.05, 2 };
      m_sessionPolicies[1] = { SESSION_LONDON,   1.0,  0.00, 4 };
      m_sessionPolicies[2] = { SESSION_NEW_YORK, 1.0, -0.02, 4 };
      m_sessionPolicies[3] = { SESSION_OVERLAP,  1.0, -0.03, 5 };
      m_sessionPolicies[4] = { SESSION_UNKNOWN,  0.3, +0.15, 1 };

      m_volPolicies[VOL_LOW]    = { VOL_LOW,    0.8, -0.1, 1.2 };
      m_volPolicies[VOL_NORMAL] = { VOL_NORMAL, 1.0,  0.0, 1.5 };
      m_volPolicies[VOL_HIGH]   = { VOL_HIGH,   1.4, +0.3, 2.0 };
      m_atrLowThresh  =  80.0;
      m_atrHighThresh = 200.0;
      m_aiConfidenceThreshold = AI_DEFAULT_CONF_THRESHOLD;
      m_lastAIAccuracy = 0.0;
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
      if(h >= 17 && h < 22) return SESSION_NEW_YORK;
      if(h >=  0 && h <  8) return SESSION_TOKYO;
      return SESSION_UNKNOWN;
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
      int idx = SessionIndex(p.session);
      if(idx < 0 || idx >= 5) return;
      m_sessionPolicies[idx] = p;
     }

   EffectivePolicy GetEffectivePolicy(EMarketRegime regime, double atrPoints) const
     {
      if(!IsValidRegime(regime)) regime = REGIME_RANGE;
      ENUM_TRADING_SESSION session = DetectSession();
      ENUM_VOL_TIER volTier = ClassifyATR(atrPoints);
      const RegimePolicy &rp = m_regimePolicies[(int)regime];
      const SessionPolicy &sp = m_sessionPolicies[SessionIndex(session)];
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
         case SESSION_TOKYO:    return "Tokyo";
         case SESSION_LONDON:   return "London";
         case SESSION_NEW_YORK: return "NewYork";
         case SESSION_OVERLAP:  return "Overlap";
         case SESSION_SYDNEY:   return "Sydney";
         default:               return "Off";
        }
     }

   string RegimeName(EMarketRegime r) const { return MarketRegimeName(r); }

   double GetAIConfidenceThreshold() const { return m_aiConfidenceThreshold; }

   void SetAIConfidenceThreshold(double threshold)
     {
      m_aiConfidenceThreshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, threshold));
     }

   void OnAIAccuracyUpdate(double accuracy)
     {
      m_lastAIAccuracy = MathMax(0.0, MathMin(1.0, accuracy));
      if(m_lastAIAccuracy > 0.65)
         m_aiConfidenceThreshold = MathMax(AI_MIN_CONF_THRESHOLD, m_aiConfidenceThreshold - 0.01);
      else if(m_lastAIAccuracy < 0.45)
         m_aiConfidenceThreshold = MathMin(AI_MAX_CONF_THRESHOLD, m_aiConfidenceThreshold + 0.01);
     }

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