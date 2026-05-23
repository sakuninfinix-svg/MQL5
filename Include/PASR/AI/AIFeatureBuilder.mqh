//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh                                          |
//| 26-dimensional feature engineering for PASR AI subsystem        |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//|            Path fix ../Data/ -> ../../Data/                      |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"
#include "../../Data/RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| CAIFeatureBuilder                                                |
//| Builds 26-dim normalised feature vector from market state        |
//| Feature layout:                                                  |
//|   [0-3]   Price action (returns: 1,2,3,5 bars)                  |
//|   [4-7]   Volatility (ATR ratios at 3,5,10,20 bars)             |
//|   [8-11]  Momentum (RSI-norm, MACD-norm, CCI-norm, Stoch-norm)  |
//|   [12-15] Volume (vol ratio, OBV delta, vol-spike, mfi-norm)    |
//|   [16-18] Structure (SR distance, zone strength, pattern score) |
//|   [19-21] Regime (one-hot: trend/sideways/volatile)             |
//|   [22-23] Time (hour-norm, day-of-week-norm)                    |
//|   [24]    Z-score (20-bar price z-score)                        |
//|   [25]    Skew (20-bar return skewness)                         |
//+------------------------------------------------------------------+
class CAIFeatureBuilder : public IManager
{
private:
   double   m_last_features[AI_FEATURE_DIM];
   bool     m_last_valid;
   datetime m_last_built;
   
   // Normalisation helpers
   double   m_atr_baseline;    // running ATR for normalisation
   double   m_vol_baseline;    // running volume for normalisation
   int      m_build_count;     // how many successful builds
   
   //--- Price return helpers
   double PriceReturn(int bars_back)
   {
      double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
      double cn = iClose(_Symbol, PERIOD_CURRENT, bars_back);
      if(cn == 0.0) return 0.0;
      return (c0 - cn) / cn;
   }
   
   //--- ATR ratio
   double ATRRatio(int period)
   {
      double atr = iATR(_Symbol, PERIOD_CURRENT, period, 0);
      if(m_atr_baseline <= 0.0) return 0.5;
      return MathMin(atr / m_atr_baseline, 3.0) / 3.0;  // clamp + normalize [0..1]
   }
   
   //--- Normalise indicator to [0..1]
   double NormIndicator(double val, double mn, double mx)
   {
      if(mx <= mn) return 0.5;
      return MathMax(0.0, MathMin(1.0, (val - mn) / (mx - mn)));
   }
   
   //--- Z-score of close over n bars
   double ZScore(int n)
   {
      double arr[]; ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, n, arr) < n) return 0.0;
      double mean = 0.0, sq = 0.0;
      for(int i=0; i<n; i++) mean += arr[i];
      mean /= n;
      for(int i=0; i<n; i++) sq += MathPow(arr[i]-mean, 2);
      double sd = MathSqrt(sq / n);
      if(sd <= 0.0) return 0.0;
      return (arr[0] - mean) / sd;
   }
   
   //--- Return skewness over n bars
   double ReturnSkew(int n)
   {
      double arr[]; ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 0, n+1, arr) < n+1) return 0.0;
      double ret[]; ArrayResize(ret, n);
      for(int i=0; i<n; i++) ret[i] = (arr[i]-arr[i+1]) / MathMax(arr[i+1], 1e-10);
      double mean=0.0, sd=0.0, sk=0.0;
      for(int i=0;i<n;i++) mean += ret[i]; mean/=n;
      for(int i=0;i<n;i++) sd   += MathPow(ret[i]-mean,2); sd=MathSqrt(sd/n);
      if(sd<=0.0) return 0.0;
      for(int i=0;i<n;i++) sk += MathPow((ret[i]-mean)/sd, 3);
      return MathMax(-3.0, MathMin(3.0, sk/n)) / 3.0;  // normalize to [-1..1]
   }
   
   //--- Update running baselines
   void UpdateBaselines()
   {
      double atr = iATR(_Symbol, PERIOD_CURRENT, 14, 0);
      double vol = iVolume(_Symbol, PERIOD_CURRENT, 0);
      double alpha = 0.05;  // EMA smoothing
      if(m_atr_baseline <= 0.0) m_atr_baseline = atr;
      else m_atr_baseline = alpha*atr + (1.0-alpha)*m_atr_baseline;
      if(m_vol_baseline <= 0.0) m_vol_baseline = (double)vol;
      else m_vol_baseline = alpha*(double)vol + (1.0-alpha)*m_vol_baseline;
   }
   
public:
   CAIFeatureBuilder()
      : m_last_valid(false), m_last_built(0),
        m_atr_baseline(0.0), m_vol_baseline(0.0), m_build_count(0)
   {
      ArrayInitialize(m_last_features, 0.0);
   }
   
   virtual bool Initialize(CEventBus *bus) override
   {
      return IManager::Initialize(bus);
   }
   
   virtual void Shutdown() override { IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}
   
   //--- Build 26-dim feature vector (called by CAIOrchestrator::Predict)
   bool Build(SAIFeatureVector &out)
   {
      out.Reset();
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars < 50) return false;
      
      UpdateBaselines();
      
      double f[AI_FEATURE_DIM];
      
      // [0-3] Price returns
      f[0]  = MathMax(-0.05, MathMin(0.05, PriceReturn(1)))  / 0.05;   // normalize
      f[1]  = MathMax(-0.05, MathMin(0.05, PriceReturn(2)))  / 0.05;
      f[2]  = MathMax(-0.05, MathMin(0.05, PriceReturn(3)))  / 0.05;
      f[3]  = MathMax(-0.05, MathMin(0.05, PriceReturn(5)))  / 0.05;
      
      // [4-7] ATR ratios
      f[4]  = ATRRatio(3);
      f[5]  = ATRRatio(5);
      f[6]  = ATRRatio(10);
      f[7]  = ATRRatio(20);
      
      // [8-11] Momentum indicators
      double rsi  = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE, 0);
      double macd_main, macd_sig, macd_hist;
      {
         int h = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN,   0);
         macd_main = h;
         macd_sig  = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
         macd_hist = macd_main - macd_sig;
      }
      double cci  = iCCI(_Symbol, PERIOD_CURRENT, 14, PRICE_TYPICAL, 0);
      double stoch= iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 0);
      
      f[8]  = NormIndicator(rsi,   0.0, 100.0);
      f[9]  = MathMax(-1.0, MathMin(1.0, macd_hist / MathMax(m_atr_baseline, 1e-8))) * 0.5 + 0.5;
      f[10] = NormIndicator(cci,  -200.0, 200.0);
      f[11] = NormIndicator(stoch,  0.0, 100.0);
      
      // [12-15] Volume
      double vol0 = (double)iVolume(_Symbol, PERIOD_CURRENT, 0);
      double vol1 = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
      double vol_ratio = (vol1 > 0.0) ? vol0 / vol1 : 1.0;
      f[12] = NormIndicator(vol_ratio, 0.0, 5.0);
      // OBV delta approximation
      double obv_delta = (iClose(_Symbol,PERIOD_CURRENT,0) > iClose(_Symbol,PERIOD_CURRENT,1)) ? vol0 : -vol0;
      f[13] = NormIndicator(obv_delta / MathMax(m_vol_baseline,1.0), -3.0, 3.0);
      // Vol spike: is vol > 2x baseline?
      f[14] = (m_vol_baseline > 0.0 && vol0 > 2.0*m_vol_baseline) ? 1.0 : 0.0;
      // MFI approximation
      double mfi = iMFI(_Symbol, PERIOD_CURRENT, 14, 0);
      f[15] = NormIndicator(mfi, 0.0, 100.0);
      
      // [16-18] Structure (pass-through if no zone/SR managers, default 0.5)
      f[16] = 0.5;  // SR distance — updated by external injection if available
      f[17] = 0.5;  // Zone strength
      f[18] = 0.5;  // Pattern score
      
      // [19-21] Regime one-hot (default sideways)
      f[19] = 0.0;  // trending
      f[20] = 1.0;  // sideways
      f[21] = 0.0;  // volatile
      
      // [22-23] Time
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      f[22] = (double)dt.hour / 23.0;
      f[23] = (double)dt.day_of_week / 6.0;
      
      // [24-25] Statistical
      double z = ZScore(20);
      f[24] = MathMax(-3.0, MathMin(3.0, z)) / 3.0;  // normalize to [-1..1]
      f[25] = ReturnSkew(20);
      
      // Copy to output
      ArrayCopy(out.features, f);
      out.valid    = true;
      out.bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      // Cache
      ArrayCopy(m_last_features, f);
      m_last_valid = true;
      m_last_built = TimeCurrent();
      m_build_count++;
      
      return true;
   }
   
   //--- Inject structure features from external managers
   void InjectStructure(double sr_dist_norm, double zone_strength_norm, double pattern_score_norm)
   {
      m_last_features[16] = sr_dist_norm;
      m_last_features[17] = zone_strength_norm;
      m_last_features[18] = pattern_score_norm;
   }
   
   //--- Inject regime one-hot
   void InjectRegime(EMarketRegime regime)
   {
      m_last_features[19] = (regime == REGIME_TRENDING)  ? 1.0 : 0.0;
      m_last_features[20] = (regime == REGIME_SIDEWAYS)  ? 1.0 : 0.0;
      m_last_features[21] = (regime == REGIME_VOLATILE)  ? 1.0 : 0.0;
   }
   
   //--- Accessor
   const double *GetLastFeatures() const { return m_last_features; }
   bool          IsValid()         const { return m_last_valid;    }
   int           GetBuildCount()   const { return m_build_count;   }
};

#endif // __AI_FEATURE_BUILDER_MQH__
