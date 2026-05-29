//+------------------------------------------------------------------+
//| AI/AIOrchestrator.mqh — v3.10                                    |
//| AI-first, risk-aware strategy brain for PASR                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "AIEnsemble.mqh"
#include "AITrainer.mqh"
#include "ConfidenceCalibrator.mqh"
#include "OnlineLearningGuard.mqh"
#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

class CAIOrchestrator : public IManager
  {
private:
   CAIFeatureBuilder     *m_feat;
   CAIEnsemble           *m_ensemble;
   CAITrainer            *m_trainer;
   CConfidenceCalibrator *m_calib;
   COnlineLearningGuard  *m_guard;

   SAIInferenceResult     m_last_result;
   SAIRiskDecision        m_last_decision;
   SAITradeLabel          m_last_label;
   SAIModelPerf           m_perf;
   bool                   m_ready;
   int                    m_min_bars_required;
   SAIFeatureVector       m_open_features;
   bool                   m_open_features_valid;

   EActiveStrategy        m_currentStrategy;
   EMarketRegime          m_detectedRegime;
   double                 m_strategyConfidence;
   datetime               m_lastStrategyChange;
   int                    m_regimeStreak;
   double                 m_entryThreshold;
   double                 m_riskMultiplier;

   bool                   m_useAI;
   double                 m_vetoThreshold;
   double                 m_driftVetoThreshold;
   double                 m_highConfidenceThreshold;

   int                    m_hATRRegime;
   int                    m_hADXRegime;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }
   double Clamp(double v, double lo, double hi) const { return MathMax(lo, MathMin(hi, v)); }

   void SetUnavailable(SAIInferenceResult &out_result, string reason)
     {
      out_result.Reset();
      out_result.valid = false;
      out_result.vetoed = true;
      out_result.veto_reason = reason;
      out_result.timestamp = TimeCurrent();
      m_last_result = out_result;
      m_last_decision.Reset();
      m_last_decision.reason = reason;
     }

   void ReleaseIndicator(int &handle)
     {
      if(handle != INVALID_HANDLE)
        {
         IndicatorRelease(handle);
         handle = INVALID_HANDLE;
        }
     }

   double ReadIndicator(int handle, int buffer = 0, int shift = 1) const
     {
      if(handle == INVALID_HANDLE) return 0.0;
      double value[1];
      if(CopyBuffer(handle, buffer, shift, 1, value) <= 0) return 0.0;
      return value[0];
     }

   bool EnsureRegimeIndicators()
     {
      if(m_hATRRegime == INVALID_HANDLE)
         m_hATRRegime = iATR(_Symbol, _Period, 20);
      if(m_hADXRegime == INVALID_HANDLE)
         m_hADXRegime = iADX(_Symbol, _Period, 50);
      return (m_hATRRegime != INVALID_HANDLE && m_hADXRegime != INVALID_HANDLE);
     }

   void ReleaseComponents()
     {
      m_ready = false;
      if(m_guard    != NULL) { m_guard.Deinit();    delete m_guard;    m_guard    = NULL; }
      if(m_calib    != NULL) { m_calib.Deinit();    delete m_calib;    m_calib    = NULL; }
      if(m_trainer  != NULL) { m_trainer.Deinit();  delete m_trainer;  m_trainer  = NULL; }
      if(m_ensemble != NULL) { m_ensemble.Deinit(); delete m_ensemble; m_ensemble = NULL; }
      if(m_feat     != NULL) { m_feat.Deinit();     delete m_feat;     m_feat     = NULL; }
      ReleaseIndicator(m_hATRRegime);
      ReleaseIndicator(m_hADXRegime);
      m_open_features_valid = false;
      m_open_features.Reset();
     }

   void DetectRegime()
     {
      double trendStr = CalculateTrendStrength(50);
      double vol      = CalculateVolatility(20);

      EMarketRegime newRegime = REGIME_UNKNOWN;
      if(trendStr > 0.8 && vol > 0.4)
         newRegime = REGIME_TREND_UP;
      else if(trendStr < 0.3 && vol < 0.3)
         newRegime = REGIME_RANGE;
      else if(vol > 0.8)
         newRegime = REGIME_VOLATILE;
      else if(trendStr > 0.5)
         newRegime = REGIME_TREND_UP;
      else
         newRegime = REGIME_TRANSITION;

      if(newRegime == m_detectedRegime)
         m_regimeStreak++;
      else
        {
         if(m_regimeStreak >= 3)
           {
            m_detectedRegime = newRegime;
            m_regimeStreak = 1;
           }
         else
            m_regimeStreak = 1;
        }
     }

   void SelectStrategy()
     {
      switch(m_detectedRegime)
        {
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN:
            m_currentStrategy = STRAT_TREND_FOLLOW;
            m_entryThreshold = 0.60;
            m_riskMultiplier = 1.20;
            m_strategyConfidence = 0.85;
            break;
         case REGIME_RANGE:
            m_currentStrategy = STRAT_RANGE_TRADING;
            m_entryThreshold = 0.65;
            m_riskMultiplier = 1.30;
            m_strategyConfidence = 0.85;
            break;
         case REGIME_VOLATILE:
            m_currentStrategy = STRAT_BREAKOUT;
            m_entryThreshold = 0.85;
            m_riskMultiplier = 0.90;
            m_strategyConfidence = 0.70;
            break;
         case REGIME_CRASH:
         case REGIME_UNKNOWN:
            m_currentStrategy = STRAT_CONSERVATIVE;
            m_entryThreshold = 0.95;
            m_riskMultiplier = 0.10;
            m_strategyConfidence = 0.0;
            break;
         default:
            m_currentStrategy = STRAT_SCALP_AI;
            m_entryThreshold = 0.70;
            m_riskMultiplier = 1.00;
            m_strategyConfidence = 0.75;
            break;
        }
      m_lastStrategyChange = TimeCurrent();
     }

   double CalculateVolatility(int period)
     {
      if(!EnsureRegimeIndicators()) return 0.0;
      double atr = ReadIndicator(m_hATRRegime, 0, 1);
      if(atr <= 0.0) return 0.0;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double avgPrice = (bid + ask) / 2.0;
      if(avgPrice <= 0.0) return 0.0;
      double normVol = (atr / avgPrice) * 100.0;
      return MathMin(normVol * 10.0, 1.0);
     }

   double CalculateTrendStrength(int maPeriod)
     {
      if(!EnsureRegimeIndicators()) return 0.0;
      double adx = ReadIndicator(m_hADXRegime, 0, 1);
      if(adx <= 0.0) return 0.0;
      return MathMin(adx / 50.0, 1.0);
     }

   double DynamicThreshold() const
     {
      double th = MathMax(m_vetoThreshold, m_entryThreshold);
      if(m_currentStrategy == STRAT_CONSERVATIVE)
         th = MathMax(th, 0.90);
      if(m_highConfidenceThreshold > 0.0)
         th = MathMin(th, m_highConfidenceThreshold);
      return MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, th));
     }

   bool BuildRiskDecision(const SAIInferenceResult &res, SAIRiskDecision &decision)
     {
      decision.Reset();
      if(!res.valid || res.vetoed || res.direction == 0)
        {
         decision.reason = res.vetoed ? res.veto_reason : "invalid inference";
         return false;
        }

      double threshold = DynamicThreshold();
      double edge = MathAbs(res.score);
      double margin = res.confidence - threshold;
      double regimeQuality = Clamp01(m_strategyConfidence);
      double driftPenalty = Clamp01(res.drift_score);

      decision.direction = res.direction;
      decision.confidence = res.confidence;
      decision.failureProbability = Clamp01(1.0 - res.confidence + driftPenalty * 0.35 + (1.0 - regimeQuality) * 0.15);
      decision.expectedR = (res.confidence * 2.0 + edge * 1.25 + regimeQuality * 0.75) - (decision.failureProbability * 1.4);
      decision.noTradePenalty = Clamp01((threshold - res.confidence) + driftPenalty * 0.50 + (m_currentStrategy == STRAT_CONSERVATIVE ? 0.25 : 0.0));

      if(margin < 0.0 || decision.expectedR < 0.35 || decision.failureProbability > 0.72)
        {
         decision.decisionClass = AI_DECISION_NO_TRADE;
         decision.riskMultiplier = 0.0;
         decision.reason = StringFormat("AI_NO_TRADE conf=%.2f th=%.2f expR=%.2f fail=%.2f",
                                        res.confidence, threshold, decision.expectedR, decision.failureProbability);
         return false;
        }

      bool strong = (res.confidence >= MathMax(threshold + 0.10, 0.75) && decision.expectedR >= 1.20 && decision.failureProbability <= 0.45);
      if(res.direction > 0)
         decision.decisionClass = strong ? AI_DECISION_STRONG_BUY : AI_DECISION_WEAK_BUY;
      else
         decision.decisionClass = strong ? AI_DECISION_STRONG_SELL : AI_DECISION_WEAK_SELL;

      double volBoost = (m_detectedRegime == REGIME_VOLATILE) ? 1.25 : 1.0;
      double rangeTighten = (m_detectedRegime == REGIME_RANGE) ? 0.90 : 1.0;
      decision.recommendedSL_ATR = Clamp(1.0 * volBoost * rangeTighten / MathMax(0.7, m_riskMultiplier), 0.60, 3.00);
      decision.recommendedTP_ATR = Clamp(decision.recommendedSL_ATR * MathMax(1.15, decision.expectedR), 1.00, 5.00);
      decision.riskMultiplier = Clamp(m_riskMultiplier * res.confidence * (1.0 - decision.failureProbability * 0.45), 0.05, 1.50);
      decision.reason = StringFormat("AI_RISK_AWARE %s conf=%.2f expR=%.2f fail=%.2f SL=%.2fATR TP=%.2fATR risk=%.2f",
                                     GetStrategyDescription(), decision.confidence, decision.expectedR,
                                     decision.failureProbability, decision.recommendedSL_ATR,
                                     decision.recommendedTP_ATR, decision.riskMultiplier);
      return true;
     }

   bool BuildSignalFromDecision(const SAIInferenceResult &res, const SAIRiskDecision &decision, SSignal &out)
     {
      out.Clear();
      if(decision.decisionClass == AI_DECISION_NO_TRADE || decision.direction == 0) return false;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(ask <= 0.0 || bid <= 0.0 || point <= 0.0) return false;

      double atrPrice = (m_data != NULL) ? m_data.GetATRPoints() : 0.0;
      double atrPts = (atrPrice > 0.0) ? atrPrice / point : 0.0;
      if(atrPts <= 0.0) return false;

      out.direction = (decision.direction > 0) ? SIGNAL_BUY : SIGNAL_SELL;
      out.confidence = decision.confidence;
      out.primarySource = StringFormat("AI_PRIMARY:%s|%s|score=%.3f|expR=%.2f|fail=%.2f",
                                       GetStrategyDescription(), res.model_id, res.score,
                                       decision.expectedR, decision.failureProbability);
      out.entryPrice = (out.direction == SIGNAL_BUY) ? ask : bid;
      out.slPoints = atrPts * decision.recommendedSL_ATR;
      out.tpPoints = atrPts * decision.recommendedTP_ATR;
      return true;
     }

public:
   CAIOrchestrator()
      : IManager(), m_feat(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_ready(false), m_min_bars_required(50),
        m_open_features_valid(false),
        m_currentStrategy(STRAT_NONE), m_detectedRegime(REGIME_UNKNOWN),
        m_strategyConfidence(0.0), m_lastStrategyChange(0), m_regimeStreak(0),
        m_entryThreshold(0.70), m_riskMultiplier(1.0),
        m_useAI(true), m_vetoThreshold(AI_DEFAULT_CONF_THRESHOLD),
        m_driftVetoThreshold(0.75), m_highConfidenceThreshold(0.80),
        m_hATRRegime(INVALID_HANDLE), m_hADXRegime(INVALID_HANDLE)
     {
      m_last_result.Reset();
      m_last_decision.Reset();
      m_last_label.Reset();
      m_perf.Reset();
      m_open_features.Reset();
     }

   ~CAIOrchestrator() { ReleaseComponents(); }

   virtual string HandlerName() const override { return "AIOrchestrator"; }

   EActiveStrategy GetActiveStrategy() const { return m_currentStrategy; }
   EMarketRegime   GetCurrentRegime() const { return m_detectedRegime; }
   double          GetStrategyConfidence() const { return m_strategyConfidence; }
   double          GetEntryThreshold() const { return m_entryThreshold; }
   double          GetRiskMultiplier() const { return m_riskMultiplier; }
   string          GetStrategyDescription() const;

   void ConfigureParameters(bool useAI, double vetoThresh, double driftVeto, double highThresh)
     {
      m_useAI = useAI;
      m_vetoThreshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, vetoThresh));
      m_driftVetoThreshold = MathMax(0.1, MathMin(1.0, driftVeto));
      m_highConfidenceThreshold = MathMax(AI_MIN_CONF_THRESHOLD, MathMin(AI_MAX_CONF_THRESHOLD, highThresh));
      if(m_guard != NULL) m_guard.SetVetoThreshold(m_driftVetoThreshold);
      if(m_calib != NULL) m_calib.SetThreshold(m_vetoThreshold);
      PrintFormat("[AIOrchestrator] Configured: useAI=%s veto=%.2f drift=%.2f high=%.2f",
                  useAI ? "true" : "false", m_vetoThreshold, m_driftVetoThreshold, m_highConfidenceThreshold);
     }

   bool ShouldAllowTrade(int signalStrength);
   void AdjustRiskParameters(double &riskPercent, double &maxDrawdown);

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReleaseComponents();

      m_feat     = new CAIFeatureBuilder();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();

      if(m_feat == NULL || m_ensemble == NULL || m_trainer == NULL ||
         m_calib == NULL || m_guard == NULL)
        {
         Print("AI: allocation failed");
         ReleaseComponents();
         return false;
        }

      if(!m_feat.Init(data, bus))     { Print("AI: FeatureBuilder init failed"); ReleaseComponents(); return false; }
      if(!m_ensemble.Init(data, bus)) { Print("AI: Ensemble init failed");       ReleaseComponents(); return false; }
      if(!m_trainer.Init(data, bus))  { Print("AI: Trainer init failed");        ReleaseComponents(); return false; }
      if(!m_calib.Init(data, bus))    { Print("AI: Calibrator init failed");     ReleaseComponents(); return false; }
      if(!m_guard.Init(data, bus))    { Print("AI: Guard init failed");          ReleaseComponents(); return false; }

      m_calib.SetThreshold(m_vetoThreshold);
      m_guard.SetVetoThreshold(m_driftVetoThreshold);
      m_trainer.SetEnsemble(m_ensemble);
      m_ready = true;

      DetectRegime();
      SelectStrategy();

      Print("CAIOrchestrator v3.10: risk-aware AI strategy brain initialized");
      Print("  Active Strategy: ", GetStrategyDescription());
      Print("  Current Regime: ", EnumToString(m_detectedRegime));
      return true;
     }

   virtual void Deinit() override
     {
      ReleaseComponents();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_NEW_BAR);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         OnConfigReload();
         ConfigureParameters(m_useAI, m_vetoThreshold, m_driftVetoThreshold, m_highConfidenceThreshold);
         return;
        }
      if(!m_ready) return;

      if(ev.id == EVENT_ID_NEW_BAR)
        {
         DetectRegime();
         SelectStrategy();
         return;
        }

      if(ev.id == EVENT_ID_TRADE_CLOSE)
        {
         OnTradeResult(ev.profit > 0.0);
         return;
        }

      if(ev.id == EVENT_ID_TRADE_OPEN)
        {
         if(m_last_result.valid && m_feat != NULL)
           {
            const double *last = m_feat.GetLastFeatures();
            if(last != NULL) ArrayCopy(m_open_features.features, last);
            m_open_features.valid = true;
            m_open_features.bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);
            m_open_features_valid = true;
           }
        }
     }

   bool Predict(SAIInferenceResult &out_result)
     {
      out_result.Reset();
      if(!m_useAI)
        {
         SetUnavailable(out_result, "AI disabled");
         return false;
        }
      if(!m_ready || m_feat == NULL || m_guard == NULL || m_ensemble == NULL || m_calib == NULL)
        {
         SetUnavailable(out_result, "AI not ready");
         return false;
        }

      SAIFeatureVector fv;
      fv.Reset();
      if(!m_feat.Build(fv))
        {
         SetUnavailable(out_result, "Feature build failed");
         return false;
        }

      double drift = m_guard.ComputeDrift(fv);
      if(m_guard.ShouldVeto(drift))
        {
         SetUnavailable(out_result, StringFormat("Drift veto: %.3f", drift));
         out_result.drift_score = drift;
         m_last_result = out_result;
         return false;
        }

      SAIEnsembleVote vote;
      vote.Reset();
      if(!m_ensemble.Vote(fv, vote) || vote.n_models <= 0)
        {
         SetUnavailable(out_result, "Ensemble vote failed");
         return false;
        }

      double raw_conf = MathAbs(vote.final_score);
      double cal_conf = m_calib.Calibrate(raw_conf, vote.agreement);

      out_result.score = vote.final_score;
      out_result.confidence = cal_conf;
      out_result.direction = (vote.final_score > 0.0) ? 1 : ((vote.final_score < 0.0) ? -1 : 0);
      out_result.valid = (cal_conf >= DynamicThreshold() && out_result.direction != 0);
      out_result.model_id = "ensemble_v3_ai_primary";
      out_result.timestamp = TimeCurrent();
      out_result.drift_score = drift;
      out_result.vetoed = false;

      m_last_result = out_result;
      return out_result.valid;
     }

   bool PredictDecision(SAIRiskDecision &out_decision)
     {
      out_decision.Reset();
      SAIInferenceResult result;
      if(!Predict(result))
        {
         out_decision = m_last_decision;
         return false;
        }
      bool ok = BuildRiskDecision(result, out_decision);
      m_last_decision = out_decision;
      return ok;
     }

   bool PredictSignal(SSignal &out_signal)
     {
      out_signal.Clear();
      SAIInferenceResult result;
      if(!Predict(result)) return false;

      SAIRiskDecision decision;
      if(!BuildRiskDecision(result, decision))
        {
         m_last_decision = decision;
         return false;
        }

      m_last_decision = decision;
      return BuildSignalFromDecision(result, decision, out_signal);
     }

   double Evaluate()
     {
      SAIInferenceResult result;
      Predict(result);
      return result.score;
     }

   bool GetLastVeto() const { return m_last_result.vetoed; }
   double GetLastDriftScore() const { return m_last_result.drift_score; }

   void OnTradeResult(bool was_profitable)
     {
      if(!m_ready || m_trainer == NULL || m_feat == NULL) return;

      SAITrainSample sample;
      sample.Reset();
      if(m_open_features_valid)
        {
         ArrayCopy(sample.features, m_open_features.features);
         m_open_features_valid = false;
         m_open_features.Reset();
        }
      else
        {
         const double *last = m_feat.GetLastFeatures();
         if(last != NULL) ArrayCopy(sample.features, last);
        }

      m_last_label.Reset();
      m_last_label.valid = true;
      m_last_label.timestamp = TimeCurrent();
      m_last_label.direction = m_last_result.direction;
      m_last_label.realizedR = was_profitable ? MathMax(0.1, m_last_decision.expectedR) : -1.0;
      m_last_label.hitTPBeforeSL = was_profitable;
      m_last_label.durationBars = 0.0;
      if(m_last_result.direction > 0)
         m_last_label.labelClass = was_profitable ? AI_LABEL_GOOD_BUY : AI_LABEL_BAD_BUY;
      else if(m_last_result.direction < 0)
         m_last_label.labelClass = was_profitable ? AI_LABEL_GOOD_SELL : AI_LABEL_BAD_SELL;
      else
         m_last_label.labelClass = AI_LABEL_NO_TRADE;

      sample.label = was_profitable ? MathMax(0.25, MathMin(1.0, m_last_label.realizedR)) : -1.0;
      sample.weight = MathMax(0.1, MathMin(2.0, m_last_result.confidence + MathAbs(m_last_label.realizedR) * 0.25));
      sample.timestamp = TimeCurrent();
      m_trainer.AddSample(sample);
      m_trainer.MaybeRetrain();
      m_perf.Update(was_profitable, m_last_result.confidence, m_last_result.drift_score);
     }

   void InjectContext(double sr_dist, double zone_str, double pattern_score, EMarketRegime regime)
     {
      if(m_feat == NULL) return;
      m_feat.InjectStructure(sr_dist, zone_str, pattern_score);
      m_feat.InjectRegime(regime);
     }

   bool IsReady() const { return m_ready; }
   virtual bool IsHealthy() const override { return IsInitialized() && m_ready && m_useAI; }
   const SAIInferenceResult &GetLastResult() const { return m_last_result; }
   const SAIRiskDecision &GetLastDecision() const { return m_last_decision; }
   const SAITradeLabel &GetLastLabel() const { return m_last_label; }
   const SAIModelPerf &GetPerf() const { return m_perf; }
   CAIFeatureBuilder *GetFeatureBuilder() { return m_feat; }
   CAIEnsemble *GetEnsemble() { return m_ensemble; }
  };

string CAIOrchestrator::GetStrategyDescription() const
  {
   switch(m_currentStrategy)
     {
      case STRAT_TREND_FOLLOW:  return "Trend Following";
      case STRAT_RANGE_TRADING: return "Range Trading (S/R Bounce)";
      case STRAT_MEAN_REVERT:   return "Mean Reversion";
      case STRAT_BREAKOUT:      return "Volatility Breakout";
      case STRAT_SCALP_AI:      return "AI Scalping";
      case STRAT_CONSERVATIVE:  return "Capital Preservation";
      default:                  return "Unknown Strategy";
     }
  }

bool CAIOrchestrator::ShouldAllowTrade(int signalStrength)
  {
   if(m_currentStrategy == STRAT_CONSERVATIVE)
      return (signalStrength > 90);
   if(m_strategyConfidence < 0.4 && signalStrength < 70)
      return false;
   if(m_currentStrategy == STRAT_RANGE_TRADING)
      return (signalStrength >= 60);
   if(m_currentStrategy == STRAT_MEAN_REVERT && signalStrength < 50)
      return false;
   double normalizedSignal = signalStrength / 100.0;
   return (normalizedSignal >= m_entryThreshold);
  }

void CAIOrchestrator::AdjustRiskParameters(double &riskPercent, double &maxDrawdown)
  {
   if(m_currentStrategy == STRAT_CONSERVATIVE)
     {
      riskPercent *= 0.1;
      maxDrawdown *= 0.5;
     }
   else
      riskPercent *= m_riskMultiplier;
  }

#endif // __AI_ORCHESTRATOR_MQH__