//+------------------------------------------------------------------+
//| AI/AIOrchestrator.mqh — v2.04                                    |
//| Top-level AI subsystem manager                                    |
//|                                                                   |
//| v2.04 CHANGES:                                                    |
//| - Added STRAT_RANGE_TRADING for optimal S/R bounce trading       |
//| - Sideways regime now INCREASES risk (1.3x) due to S/R conf.     |
//| - Better gatekeeper logic for range-bound markets                |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "AIInference.mqh"
#include "AIEnsemble.mqh"
#include "AITrainer.mqh"
#include "ConfidenceCalibrator.mqh"
#include "OnlineLearningGuard.mqh"
#include "../../Core/IManager.mqh"

class CAIOrchestrator : public IManager
  {
private:
   CAIFeatureBuilder     *m_feat;
   CAIInference          *m_infer;
   CAIEnsemble           *m_ensemble;
   CAITrainer            *m_trainer;
   CConfidenceCalibrator *m_calib;
   COnlineLearningGuard  *m_guard;

   SAIInferenceResult     m_last_result;
   SAIModelPerf           m_perf;
   bool                   m_ready;
   string                 m_model_path;
   int                    m_min_bars_required;
   SAIFeatureVector       m_open_features;
   bool                   m_open_features_valid;

   void ReleaseComponents()
     {
      m_ready = false;
      if(m_guard    != NULL) { m_guard.Deinit();    delete m_guard;    m_guard    = NULL; }
      if(m_calib    != NULL) { m_calib.Deinit();    delete m_calib;    m_calib    = NULL; }
      if(m_trainer  != NULL) { m_trainer.Deinit();  delete m_trainer;  m_trainer  = NULL; }
      if(m_ensemble != NULL) { m_ensemble.Deinit(); delete m_ensemble; m_ensemble = NULL; }
      if(m_infer    != NULL) { m_infer.Deinit();    delete m_infer;    m_infer    = NULL; }
      if(m_feat     != NULL) { m_feat.Deinit();     delete m_feat;     m_feat     = NULL; }
      m_open_features_valid = false;
      m_open_features.Reset();
     }

public:
   CAIOrchestrator()
      : IManager(), m_feat(NULL), m_infer(NULL), m_ensemble(NULL),
        m_trainer(NULL), m_calib(NULL), m_guard(NULL),
        m_ready(false), m_model_path(""), m_min_bars_required(50),
        m_open_features_valid(false),
        // Initialize new orchestrator fields
        m_currentStrategy(STRAT_NONE),
        m_detectedRegime(REGIME_UNKNOWN),
        m_strategyConfidence(0.0),
        m_lastStrategyChange(0),
        m_regimeStreak(0),
        m_entryThreshold(0.7),
        m_riskMultiplier(1.0)
     {
      m_last_result.Reset();
      m_perf.Reset();
      m_open_features.Reset();
     }

   ~CAIOrchestrator() { ReleaseComponents(); }

   virtual string HandlerName() const override { return "AIOrchestrator"; }

   // --- NEW: Public API for Dynamic Strategy Orchestration ---
   EActiveStrategy GetActiveStrategy() const { return m_currentStrategy; }
   EMarketRegime   GetCurrentRegime() const { return m_detectedRegime; }
   double          GetStrategyConfidence() const { return m_strategyConfidence; }
   double          GetEntryThreshold() const { return m_entryThreshold; }
   double          GetRiskMultiplier() const { return m_riskMultiplier; }
   string          GetStrategyDescription() const;
   
   // Gatekeeper: AI memutuskan apakah sinyal boleh dieksekusi
   bool ShouldAllowTrade(int signalStrength);
   
   // Dynamic Risk Adjustment: AI mengontrol parameter risiko
   void AdjustRiskParameters(double &riskPercent, double &maxDrawdown);

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ReleaseComponents();

      m_feat     = new CAIFeatureBuilder();
      m_infer    = new CAIInference();
      m_ensemble = new CAIEnsemble();
      m_trainer  = new CAITrainer();
      m_calib    = new CConfidenceCalibrator();
      m_guard    = new COnlineLearningGuard();

      if(m_feat == NULL || m_infer == NULL || m_ensemble == NULL ||
         m_trainer == NULL || m_calib == NULL || m_guard == NULL)
        {
         Print("AI: allocation failed");
         ReleaseComponents();
         return false;
        }

      if(!m_feat.Init(data, bus))     { Print("AI: FeatureBuilder init failed"); ReleaseComponents(); return false; }
      if(!m_infer.Init(data, bus))    { Print("AI: Inference init failed");      ReleaseComponents(); return false; }
      if(!m_ensemble.Init(data, bus)) { Print("AI: Ensemble init failed");       ReleaseComponents(); return false; }
      if(!m_trainer.Init(data, bus))  { Print("AI: Trainer init failed");        ReleaseComponents(); return false; }
      if(!m_calib.Init(data, bus))    { Print("AI: Calibrator init failed");     ReleaseComponents(); return false; }
      if(!m_guard.Init(data, bus))    { Print("AI: Guard init failed");          ReleaseComponents(); return false; }

      m_trainer.SetEnsemble(m_ensemble);
      m_ready = true;
      
      // Initial regime detection and strategy selection
      DetectRegime();
      SelectStrategy();
      
      Print("CAIOrchestrator v14.01-ORCHESTRATOR: Initialized as Dynamic Strategy Orchestrator");
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
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD) { OnConfigReload(); return; }
      if(!m_ready) return;

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
      if(!m_ready || m_feat == NULL || m_guard == NULL || m_ensemble == NULL || m_calib == NULL)
         return false;

      SAIFeatureVector fv;
      fv.Reset();
      if(!m_feat.Build(fv))
        {
         out_result.valid = false;
         out_result.vetoed = true;
         out_result.veto_reason = "Feature build failed";
         return false;
        }

      double drift = m_guard.ComputeDrift(fv);
      if(m_guard.ShouldVeto(drift))
        {
         out_result.drift_score = drift;
         out_result.vetoed = true;
         out_result.veto_reason = StringFormat("Drift veto: %.3f", drift);
         out_result.valid = false;
         return false;
        }

      SAIEnsembleVote vote;
      vote.Reset();
      m_ensemble.Vote(fv, vote);

      double raw_conf = MathAbs(vote.final_score);
      double cal_conf = m_calib.Calibrate(raw_conf, vote.agreement);

      out_result.score = vote.final_score;
      out_result.confidence = cal_conf;
      out_result.direction = (vote.final_score > 0.0) ? 1 : ((vote.final_score < 0.0) ? -1 : 0);
      out_result.valid = (cal_conf >= AI_DEFAULT_CONF_THRESHOLD);
      out_result.model_id = "ensemble_v2.03";
      out_result.timestamp = TimeCurrent();
      out_result.drift_score = drift;
      out_result.vetoed = false;

      m_last_result = out_result;
      return out_result.valid;
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

      sample.label = was_profitable ? 1.0 : -1.0;
      sample.weight = m_last_result.confidence;
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
   virtual bool IsHealthy() const override { return IsInitialized() && m_ready; }
   const SAIInferenceResult &GetLastResult() const { return m_last_result; }
   const SAIModelPerf &GetPerf() const { return m_perf; }
   CAIFeatureBuilder *GetFeatureBuilder() { return m_feat; }
   CAIEnsemble *GetEnsemble() { return m_ensemble; }

private:
   // --- NEW: Dynamic Strategy Orchestration Methods ---
   
   // DetectRegime: Analisis kondisi pasar real-time
   void DetectRegime()
     {
      // Hitung indikator regime sederhana (bisa diganti dengan ONNX model)
      double trendStr = CalculateTrendStrength(50);
      double vol      = CalculateVolatility(20);
      
      EMarketRegime newRegime = REGIME_UNKNOWN;
      
      if(trendStr > 0.8 && vol > 0.4)
         newRegime = REGIME_TRENDING_STRONG;
      else if(trendStr < 0.3 && vol < 0.3)
         newRegime = REGIME_SIDEWAYS;
      else if(vol > 0.8)
         newRegime = REGIME_VOLATILE;
      else if(trendStr > 0.5)
         newRegime = REGIME_TRENDING_WEAK;
      else
         newRegime = REGIME_CHAOS;
         
      // Cek streak (butuh 3 bar konfirmasi untuk ganti regime)
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
            m_regimeStreak = 1; // Reset streak untuk regime baru
        }
     }
   
   // SelectStrategy: Pilih strategi optimal berdasarkan regime
   void SelectStrategy()
     {
      switch(m_detectedRegime)
        {
         case REGIME_TRENDING_STRONG:
            m_currentStrategy = STRAT_TREND_FOLLOW;
            m_entryThreshold = 0.6;      // Lebih longgar untuk entry
            m_riskMultiplier = 1.2;      // Tingkatkan risiko 20%
            m_strategyConfidence = 0.85;
            break;
            
         case REGIME_SIDEWAYS:
            // CORRECTION: Price Action & S/R work BEST here! Bounce trading is optimal.
            m_currentStrategy = STRAT_RANGE_TRADING;   // NEW: Bounce off S/R zones
            m_entryThreshold = 0.65;     // Moderate threshold - trust S/R touches
            m_riskMultiplier = 1.3;      // INCREASED: High confidence in S/R bounces
            m_strategyConfidence = 0.85; // High confidence when price at S/R
            break;
            
         case REGIME_VOLATILE:
            m_currentStrategy = STRAT_BREAKOUT;
            m_entryThreshold = 0.85;     // Tunggu konfirmasi breakout
            m_riskMultiplier = 0.9;      // Risiko sedang
            m_strategyConfidence = 0.70;
            break;
            
         case REGIME_CHAOS:
         case REGIME_UNKNOWN:
            m_currentStrategy = STRAT_CONSERVATIVE;
            m_entryThreshold = 0.95;     // Hampir tidak pernah trade
            m_riskMultiplier = 0.1;      // Risiko minimal
            m_strategyConfidence = 0.0;  // Tidak yakin sama sekali
            break;
            
         default: // REGIME_TRENDING_WEAK
            m_currentStrategy = STRAT_SCALP_AI;
            m_entryThreshold = 0.7;
            m_riskMultiplier = 1.0;
            m_strategyConfidence = 0.75;
            break;
        }
      m_lastStrategyChange = TimeCurrent();
     }
   
   // Helper: Hitung volatilitas (normalized 0-1)
   double CalculateVolatility(int period)
     {
      double atr = iATR(_Symbol, _Period, period);
      if(atr == 0) return 0;
      
      double avgPrice = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;
      double normVol = (atr / avgPrice) * 100.0; // Persentase
      
      // Normalisasi kasar (adjust sesuai karakteristik pair)
      return MathMin(normVol * 10.0, 1.0);
     }
   
   // Helper: Hitung kekuatan trend (normalized 0-1)
   double CalculateTrendStrength(int maPeriod)
     {
      double adx = iADX(_Symbol, _Period, maPeriod);
      if(adx == 0) return 0;
      
      // Normalisasi ADX (0-100) ke 0.0-1.0
      return MathMin(adx / 50.0, 1.0);
     }
  };

//+------------------------------------------------------------------+
//| Implementation: GetStrategyDescription                           |
//+------------------------------------------------------------------+
string CAIOrchestrator::GetStrategyDescription() const
{
   switch(m_currentStrategy)
     {
      case STRAT_TREND_FOLLOW:  return "Trend Following (Aggressive)";
      case STRAT_RANGE_TRADING: return "Range Trading (S/R Bounce) - OPTIMAL FOR SIDEWAYS";
      case STRAT_MEAN_REVERT:   return "Mean Reversion (Fade Extremes)";
      case STRAT_BREAKOUT:      return "Volatility Breakout";
      case STRAT_SCALP_AI:      return "AI Scalping (High Freq)";
      case STRAT_CONSERVATIVE:  return "Capital Preservation (No Trade)";
      default:                  return "Unknown Strategy";
     }
}

//+------------------------------------------------------------------+
//| Implementation: ShouldAllowTrade                                 |
//+------------------------------------------------------------------+
bool CAIOrchestrator::ShouldAllowTrade(int signalStrength)
{
   // Jika strategi konservatif, tolak semua kecuali sinyal sangat kuat
   if(m_currentStrategy == STRAT_CONSERVATIVE)
      return (signalStrength > 90); // Hampir tidak pernah trade
      
   // Jika confidence rendah, tolak sinyal lemah
   if(m_strategyConfidence < 0.4 && signalStrength < 70)
      return false;
      
   // RANGE TRADING (Sideways): Prioritaskan sinyal di area S/R
   if(m_currentStrategy == STRAT_RANGE_TRADING)
     {
      // Di sideways, sinyal 60+ di area S/R sudah cukup bagus
      if(signalStrength < 60)
         return false;
      return true;
     }
      
   // MEAN REVERT: Hati-hati dengan sinyal lemah
   if(m_currentStrategy == STRAT_MEAN_REVERT && signalStrength < 50)
      return false; // Jangan ambil sinyal lemah saat mean reversion
      
   // Check against dynamic entry threshold
   double normalizedSignal = signalStrength / 100.0;
   if(normalizedSignal < m_entryThreshold)
      return false;
      
   return true;
}

//+------------------------------------------------------------------+
//| Implementation: AdjustRiskParameters                             |
//+------------------------------------------------------------------+
void CAIOrchestrator::AdjustRiskParameters(double &riskPercent, double &maxDrawdown)
{
   // AI berhak menurunkan risiko jika kondisi tidak pasti
   if(m_currentStrategy == STRAT_CONSERVATIVE)
     {
      riskPercent *= 0.1; // Kurangi risiko jadi 10% dari setting awal
      maxDrawdown *= 0.5;
     }
   else if(m_currentStrategy == STRAT_TREND_FOLLOW && m_strategyConfidence > 0.8)
     {
      riskPercent *= m_riskMultiplier; // Tingkatkan risiko sesuai multiplier
     }
   else if(m_currentStrategy == STRAT_RANGE_TRADING)
     {
      // RANGE TRADING: Risiko lebih tinggi karena S/R memberikan konfirmasi kuat
      riskPercent *= m_riskMultiplier; // 1.3x - high confidence at S/R zones
     }
   else if(m_currentStrategy == STRAT_MEAN_REVERT)
     {
      riskPercent *= m_riskMultiplier; // Mean reversion lebih berisiko
     }
   else if(m_currentStrategy == STRAT_BREAKOUT)
     {
      riskPercent *= m_riskMultiplier; // Breakout butuh risiko terukur
     }
}

#endif // __AI_ORCHESTRATOR_MQH__
