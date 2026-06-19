//+------------------------------------------------------------------+
//| AI/AIOrchestrator.mqh — v1.00                                    |
//| Business constants are sourced from StrategyConfig.AI            |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "SequenceFeatureBuilder.mqh"
#include "AIEnsemble.mqh"
#include "AITrainer.mqh"
#include "ConfidenceCalibrator.mqh"
#include "OnlineLearningGuard.mqh"
#include "AIFeatureValidator.mqh"
#include "LSTMInference.mqh"
#include "AttentionFusion.mqh"
#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

class CAIOrchestrator : public IManager
  {
private:
   CAIFeatureBuilder        *m_feat;
   CSequenceFeatureBuilder  *m_seq_feat;
   SAISequenceTensor         m_last_sequence;
   bool                      m_last_sequence_valid;
   CAIEnsemble              *m_ensemble;
   CAITrainer               *m_trainer;
   CConfidenceCalibrator    *m_calib;
   COnlineLearningGuard     *m_guard;
   CAIFeatureValidator       m_validator;
   AIFeatureValidationResult m_last_validation;

   CLSTMInference           *m_lstm;
   CAttentionFusion         *m_attention;
   bool                      m_use_lstm;
   bool                      m_use_attention;

   SAIInferenceResult        m_last_result;
   SAIRiskDecision           m_last_decision;
   SAITradeLabel             m_last_label;
   SAIModelPerf              m_perf;
   bool                      m_ready;
   int                       m_min_bars_required;
   SAIFeatureVector          m_open_features;
   bool                      m_open_features_valid;

   EActiveStrategy           m_currentStrategy;
   EMarketRegime             m_detectedRegime;
   double                    m_strategyConfidence;
   datetime                  m_lastStrategyChange;
   int                       m_regimeStreak;
   double                    m_entryThreshold;
   double                    m_risk_multiplier;

   bool                      m_useAI;
   double                    m_vetoThreshold;
   double                    m_driftVetoThreshold;
   double                    m_highConfidenceThreshold;

   int                       m_hATRRegime;
   int                       m_hADXRegime;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }
   double Clamp(double v, double lo, double hi) const { return MathMax(lo, MathMin(hi, v)); }
   bool CopyLastSequence(SAISequenceTensor &dest)
     {
      if(!m_last_sequence_valid)
         return false;

      dest = m_last_sequence;
      return true;
     }

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
      m_last_validation.Clear();
      m_last_validation.reason = reason;
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
      int atrPeriod = MathMax(1, m_cfg.AI.RegimeATRPeriod);
      int adxPeriod = MathMax(1, m_cfg.AI.RegimeADXPeriod);
      if(m_hATRRegime == INVALID_HANDLE)
         m_hATRRegime = iATR(_Symbol, _Period, atrPeriod);
      if(m_hADXRegime == INVALID_HANDLE)
         m_hADXRegime = iADX(_Symbol, _Period, adxPeriod);
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
      if(m_seq_feat != NULL) { m_seq_feat.Deinit(); delete m_seq_feat; m_seq_feat = NULL; }
      if(m_lstm     != NULL) { delete m_lstm;        m_lstm     = NULL; }
      if(m_attention!= NULL) { delete m_attention;   m_attention= NULL; }
      ReleaseIndicator(m_hATRRegime);
      ReleaseIndicator(m_hADXRegime);
      m_open_features_valid = false;
      m_open_features.Reset();
      m_last_sequence_valid = false;
      m_last_sequence.Reset();
     }

   void DetectRegime()
     {
      double trendStr = CalculateTrendStrength(m_cfg.AI.RegimeADXPeriod);
      double vol      = CalculateVolatility(m_cfg.AI.RegimeATRPeriod);

      EMarketRegime newRegime = REGIME_UNKNOWN;
      if(trendStr > m_cfg.AI.StrongTrendLevel && vol > m_cfg.AI.RangeVolatilityMax)
         newRegime = REGIME_TREND_UP;
      else if(trendStr < m_cfg.AI.RangeTrendMax && vol < m_cfg.AI.RangeVolatilityMax)
         newRegime = REGIME_RANGE;
      else if(vol > m_cfg.AI.VolatileLevel)
         newRegime = REGIME_VOLATILE;
      else if(trendStr > m_cfg.AI.TrendLevel)
         newRegime = REGIME_TREND_UP;
      else
         newRegime = REGIME_TRANSITION;

      if(newRegime == m_detectedRegime)
         m_regimeStreak++;
      else
        {
         if(m_regimeStreak >= MathMax(1, m_cfg.AI.RegimeConfirmBars))
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
            m_entryThreshold = m_cfg.AI.TrendEntryThreshold;
            m_risk_multiplier = m_cfg.AI.TrendRiskMultiplier;
            m_strategyConfidence = m_cfg.AI.TrendStrategyConfidence;
            break;
         case REGIME_RANGE:
            m_currentStrategy = STRAT_RANGE_TRADING;
            m_entryThreshold = m_cfg.AI.RangeEntryThreshold;
            m_risk_multiplier = m_cfg.AI.RangeRiskMultiplier;
            m_strategyConfidence = m_cfg.AI.RangeStrategyConfidence;
            break;
         case REGIME_VOLATILE:
            m_currentStrategy = STRAT_BREAKOUT;
            m_entryThreshold = m_cfg.AI.VolatileEntryThreshold;
            m_risk_multiplier = m_cfg.AI.VolatileRiskMultiplier;
            m_strategyConfidence = m_cfg.AI.VolatileStrategyConfidence;
            break;
         case REGIME_CRASH:
         case REGIME_UNKNOWN:
            m_currentStrategy = STRAT_CONSERVATIVE;
            m_entryThreshold = m_cfg.AI.ConservativeEntryThreshold;
            m_risk_multiplier = m_cfg.AI.ConservativeRiskMultiplier;
            m_strategyConfidence = m_cfg.AI.ConservativeStrategyConfidence;
            break;
         default:
            m_currentStrategy = STRAT_SCALP_AI;
            m_entryThreshold = m_cfg.AI.ScalpEntryThreshold;
            m_risk_multiplier = m_cfg.AI.ScalpRiskMultiplier;
            m_strategyConfidence = m_cfg.AI.ScalpStrategyConfidence;
            break;
        }
      m_entryThreshold = Clamp(m_entryThreshold, AI_MIN_CONF_THRESHOLD, AI_MAX_CONF_THRESHOLD);
      m_strategyConfidence = Clamp01(m_strategyConfidence);
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
         th = MathMax(th, m_cfg.AI.ConservativeEntryThreshold);
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
      decision.failureProbability = Clamp01(1.0 - res.confidence +
                                            driftPenalty * m_cfg.AI.DriftFailureWeight +
                                            (1.0 - regimeQuality) * m_cfg.AI.RegimeFailureWeight);
      decision.expectedR = (res.confidence * m_cfg.AI.ConfidenceRewardWeight +
                            edge * m_cfg.AI.EdgeRewardWeight +
                            regimeQuality * m_cfg.AI.RegimeRewardWeight) -
                           (decision.failureProbability * m_cfg.AI.FailurePenaltyWeight);
      decision.noTradePenalty = Clamp01((threshold - res.confidence) +
                                        driftPenalty * m_cfg.AI.NoTradeDriftWeight +
                                        (m_currentStrategy == STRAT_CONSERVATIVE ? m_cfg.AI.ConservativeNoTradePenalty : 0.0));

      if(margin < 0.0 || decision.expectedR < m_cfg.AI.MinExpectedR || decision.failureProbability > m_cfg.AI.MaxFailureProbability)
        {
         decision.decisionClass = AI_DECISION_NO_TRADE;
         decision.risk_multiplier = 0.0;
         decision.reason = StringFormat("AI_NO_TRADE conf=%.2f th=%.2f expR=%.2f fail=%.2f",
                                        res.confidence, threshold, decision.expectedR, decision.failureProbability);
         return false;
        }

      bool strong = (res.confidence >= MathMax(threshold + m_cfg.AI.StrongConfidenceBuffer, m_cfg.AI.StrongConfidenceMin) &&
                     decision.expectedR >= m_cfg.AI.StrongExpectedR &&
                     decision.failureProbability <= m_cfg.AI.StrongMaxFailureProbability);
      if(res.direction > 0)
         decision.decisionClass = strong ? AI_DECISION_STRONG_BUY : AI_DECISION_WEAK_BUY;
      else
         decision.decisionClass = strong ? AI_DECISION_STRONG_SELL : AI_DECISION_WEAK_SELL;

      double volBoost = (m_detectedRegime == REGIME_VOLATILE) ? m_cfg.AI.VolatileSLBoost : 1.0;
      double rangeTighten = (m_detectedRegime == REGIME_RANGE) ? m_cfg.AI.RangeSLTighten : 1.0;
      decision.recommendedSL_ATR = Clamp(1.0 * volBoost * rangeTighten / MathMax(0.7, m_risk_multiplier),
                                         m_cfg.AI.MinSL_ATR, m_cfg.AI.MaxSL_ATR);
      decision.recommendedTP_ATR = Clamp(decision.recommendedSL_ATR * MathMax(m_cfg.AI.MinTPExpectedR, decision.expectedR),
                                         m_cfg.AI.MinTP_ATR, m_cfg.AI.MaxTP_ATR);
      decision.risk_multiplier = Clamp(m_risk_multiplier * res.confidence * (1.0 - decision.failureProbability * m_cfg.AI.RiskFailureWeight),
                                      m_cfg.AI.MinRiskMultiplier, m_cfg.AI.MaxRiskMultiplier);
      decision.reason = StringFormat("AI_RISK_AWARE %s conf=%.2f expR=%.2f fail=%.2f SL=%.2fATR TP=%.2fATR risk=%.2f",
                                     GetStrategyDescription(), decision.confidence, decision.expectedR,
                                     decision.failureProbability, decision.recommendedSL_ATR,
                                     decision.recommendedTP_ATR, decision.risk_multiplier);
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
      : IManager(), m_feat(NULL), m_seq_feat(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_lstm(NULL), m_attention(NULL), m_use_lstm(true), m_use_attention(true),
        m_ready(false), m_min_bars_required(50),
        m_open_features_valid(false), m_last_sequence_valid(false),
        m_currentStrategy(STRAT_NONE), m_detectedRegime(REGIME_UNKNOWN),
        m_strategyConfidence(0.0), m_lastStrategyChange(0), m_regimeStreak(0),
        m_entryThreshold(0.70), m_risk_multiplier(1.0),
        m_useAI(true), m_vetoThreshold(AI_DEFAULT_CONF_THRESHOLD),
        m_driftVetoThreshold(0.75), m_highConfidenceThreshold(0.80),
        m_hATRRegime(INVALID_HANDLE), m_hADXRegime(INVALID_HANDLE)
     {
      m_last_result.Reset();
      m_last_decision.Reset();
      m_last_label.Reset();
      m_perf.Reset();
      m_open_features.Reset();
      m_last_validation.Clear();
     }

   ~CAIOrchestrator() { ReleaseComponents(); }

   virtual string HandlerName() const override { return "AIOrchestrator"; }

   EActiveStrategy GetActiveStrategy() const { return m_currentStrategy; }
   EMarketRegime   GetCurrentRegime() const { return m_detectedRegime; }
   double          GetStrategyConfidence() const { return m_strategyConfidence; }
   double          GetEntryThreshold() const { return m_entryThreshold; }
   double          GetRiskMultiplier() const { return m_risk_multiplier; }
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
      RefreshConfig();

      m_feat     = new CAIFeatureBuilder();
      m_seq_feat = new CSequenceFeatureBuilder();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();

      if(m_feat == NULL || m_seq_feat == NULL || m_ensemble == NULL || m_trainer == NULL ||
         m_calib == NULL || m_guard == NULL)
        {
         Print("AI: allocation failed");
         ReleaseComponents();
         return false;
        }

      if(!m_feat.Init(data, bus))     { Print("AI: FeatureBuilder init failed"); ReleaseComponents(); return false; }
      if(!m_seq_feat.Init(data, bus)) { Print("AI: SequenceFeatureBuilder init failed"); ReleaseComponents(); return false; }
      if(!m_ensemble.Init(data, bus)) { Print("AI: Ensemble init failed");       ReleaseComponents(); return false; }
      if(!m_trainer.Init(data, bus))  { Print("AI: Trainer init failed");        ReleaseComponents(); return false; }
      if(!m_calib.Init(data, bus))    { Print("AI: Calibrator init failed");     ReleaseComponents(); return false; }
      if(!m_guard.Init(data, bus))    { Print("AI: Guard init failed");          ReleaseComponents(); return false; }

      if(m_use_lstm)
        {
         m_lstm = new CLSTMInference(42);
         if(m_lstm == NULL || !m_lstm.Init(data, bus))
           {
            Print("AI: LSTM init failed, falling back to ensemble");
            if(m_lstm != NULL) { delete m_lstm; m_lstm = NULL; }
            m_use_lstm = false;
           }
         else Print("AI: LSTM inference engine initialized successfully");
        }

      if(m_use_attention)
        {
         m_attention = new CAttentionFusion(43);
         if(m_attention == NULL || !m_attention.Init(data, bus))
           {
            Print("AI: Attention fusion init failed, falling back to standard fusion");
            if(m_attention != NULL) { delete m_attention; m_attention = NULL; }
            m_use_attention = false;
           }
         else Print("AI: Attention fusion initialized successfully");
        }

      ConfigureParameters(m_cfg.AI.EnableAI, m_cfg.AI.MinConfidence, m_driftVetoThreshold,
                          MathMax(m_cfg.AI.MinConfidence, m_cfg.AI.StrongConfidenceMin));
      m_trainer.SetEnsemble(m_ensemble);

      m_ready = true;
      DetectRegime();
      SelectStrategy();

      Print("CAIOrchestrator v3.30: unified risk-aware AI strategy brain initialized");
      Print("  Active Strategy: ", GetStrategyDescription());
      Print("  Current Regime: ", EnumToString(m_detectedRegime));
      Print("  LSTM Enabled: ", m_use_lstm ? "Yes" : "No");
      Print("  Attention Enabled: ", m_use_attention ? "Yes" : "No");
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
            if(m_feat.GetLastFeatures(m_open_features.features))
              {
               m_open_features.valid = true;
               m_open_features.bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);
               m_open_features_valid = true;
              }
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

      if(fv.timestamp <= 0) fv.timestamp = TimeCurrent();
      if(fv.symbol == "") fv.symbol = _Symbol;
      if(fv.timeframe == PERIOD_CURRENT) fv.timeframe = _Period;

      if(!m_validator.Validate(fv, m_ensemble, m_last_validation))
        {
         SetUnavailable(out_result, "AI validation failed: " + m_last_validation.reason);
         return false;
        }

      m_last_sequence_valid = false;
      m_last_sequence.Reset();
      if(m_seq_feat != NULL)
        {
         SAISequenceTensor seq;
         AIFeatureValidationResult seqValidation;
         seq.Reset();
         if(m_seq_feat.Build(seq) && m_validator.ValidateSequence(seq, seqValidation))
           {
            m_last_sequence = seq;
            m_last_sequence_valid = true;
           }
        }

      double drift = m_guard.ComputeDrift(fv);
      if(m_guard.ShouldVeto(drift))
        {
         SetUnavailable(out_result, StringFormat("Drift veto: %.3f", drift));
         out_result.drift_score = drift;
         m_last_result = out_result;
         return false;
        }

      double lstm_score = 0.0;
      bool lstm_used = false;
      if(m_use_lstm && m_lstm != NULL)
         {
            if(m_lstm.ForwardSequence(fv.features, lstm_score))
            {
            lstm_used = true;
            if(m_debugMode) PrintFormat("[AIOrchestrator] LSTM prediction: %.4f", lstm_score);
            }
         }

      SAIEnsembleVote vote;
      vote.Reset();
      if(!m_ensemble.Vote(fv, vote) || vote.n_models <= 0)
        {
         SetUnavailable(out_result, "Ensemble vote failed");
         return false;
        }

      double final_score = vote.final_score;
      if(lstm_used)
        {
         double lstmW = MathMax(0.0, m_cfg.AI.LSTMBlendWeight);
         double ensW  = MathMax(0.0, m_cfg.AI.EnsembleBlendWeight);
         double total = lstmW + ensW;
         if(total <= 0.0) { lstmW = 0.6; ensW = 0.4; total = 1.0; }
         final_score = (lstmW * lstm_score + ensW * vote.final_score) / total;
         out_result.model_id = "lstm+ensemble";
        }
      else
        {
         if(m_ensemble.IsOnnxLoaded() && m_last_sequence_valid)
            out_result.model_id = "ensemble_mlp+onnx_seq";
         else
            out_result.model_id = "ensemble_mlp";
        }

      double raw_conf = MathAbs(final_score);
      double cal_conf = m_calib.Calibrate(raw_conf, vote.agreement);

      out_result.score = final_score;
      out_result.confidence = cal_conf;
      out_result.direction = (final_score > 0.0) ? 1 : ((final_score < 0.0) ? -1 : 0);
      out_result.valid = (cal_conf >= DynamicThreshold() && out_result.direction != 0);
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
      else if(m_feat.GetLastFeatures(sample.features))
        {
         // feature vector copied successfully
        }

      m_last_label.Reset();
      m_last_label.valid = true;
      m_last_label.timestamp = TimeCurrent();
      m_last_label.direction = m_last_result.direction;
      m_last_label.realizedR = was_profitable ? MathMax(0.1, m_last_decision.expectedR) : -1.0;
      m_last_label.hitTPBeforeSL = was_profitable;
      m_last_label.durationBars = 0.0;
      if(m_last_result.direction > 0)
         m_last_label.label_class = was_profitable ? AI_LABEL_GOOD_BUY : AI_LABEL_BAD_BUY;
      else if(m_last_result.direction < 0)
         m_last_label.label_class = was_profitable ? AI_LABEL_GOOD_SELL : AI_LABEL_BAD_SELL;
      else
         m_last_label.label_class = AI_LABEL_NO_TRADE;

      sample.label = was_profitable ? MathMax(0.25, MathMin(1.0, m_last_label.realizedR)) : -1.0;
      sample.weight = MathMax(0.1, MathMin(2.0, m_last_result.confidence + MathAbs(m_last_label.realizedR) * 0.25));
      sample.timestamp = TimeCurrent();
      m_trainer.AddSample(sample);
      m_trainer.MaybeRetrain();
      m_perf.Update(was_profitable, m_last_result.confidence, m_last_result.drift_score);
     }

   void InjectContext(double sr_dist, double zone_str, double pattern_score, EMarketRegime regime)
     {
      if(m_feat != NULL)
        {
         m_feat.InjectStructure(sr_dist, zone_str, pattern_score);
         m_feat.InjectRegime(regime);
        }
      if(m_seq_feat != NULL)
        {
         m_seq_feat.InjectStructure(sr_dist, zone_str, pattern_score);
         m_seq_feat.InjectRegime(regime);
        }
     }

   bool IsReady() const { return m_ready; }
   virtual bool IsHealthy() const override { return IsInitialized() && m_ready && m_useAI; }
   SAIInferenceResult GetLastResult() const { return m_last_result; }
   AIFeatureValidationResult GetLastValidation() const { return m_last_validation; }
   SAIRiskDecision GetLastDecision() const { return m_last_decision; }
   SAITradeLabel GetLastLabel() const { return m_last_label; }
   SAIModelPerf GetPerf() const { return m_perf; }
   CAIFeatureBuilder *GetFeatureBuilder() { return m_feat; }
   CSequenceFeatureBuilder *GetSequenceFeatureBuilder() { return m_seq_feat; }
   bool GetLastSequence(SAISequenceTensor &dest) const
     {
      if(!m_last_sequence_valid) return false;
      dest = m_last_sequence;
      return true;
     }
   bool HasValidSequence() const { return m_last_sequence_valid; }
   CAIEnsemble *GetEnsemble() { return m_ensemble; }

   virtual void OnConfigReload() override
     {
      IManager::OnConfigReload();
      ConfigureParameters(m_cfg.AI.EnableAI, m_cfg.AI.MinConfidence, m_driftVetoThreshold,
                          MathMax(m_cfg.AI.MinConfidence, m_cfg.AI.StrongConfidenceMin));
      DetectRegime();
      SelectStrategy();
     }
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
      return (signalStrength > (int)m_cfg.AI.ConservativeSignalThreshold);
   if(m_strategyConfidence < m_cfg.AI.LowStrategyConfidence && signalStrength < m_cfg.AI.LowStrategySignalThreshold)
      return false;
   if(m_currentStrategy == STRAT_RANGE_TRADING)
      return (signalStrength >= m_cfg.AI.RangeSignalThreshold);
   if(m_currentStrategy == STRAT_MEAN_REVERT && signalStrength < m_cfg.AI.MeanRevertSignalThreshold)
      return false;
   double normalizedSignal = signalStrength / 100.0;
   return (normalizedSignal >= m_entryThreshold);
  }

void CAIOrchestrator::AdjustRiskParameters(double &riskPercent, double &maxDrawdown)
  {
   if(m_currentStrategy == STRAT_CONSERVATIVE)
     {
      riskPercent *= MathMax(0.0, m_cfg.AI.ConservativeRiskMultiplier);
      maxDrawdown *= 0.5;
     }
   else
      riskPercent *= m_risk_multiplier;
  }

#endif // __AI_ORCHESTRATOR_MQH__
