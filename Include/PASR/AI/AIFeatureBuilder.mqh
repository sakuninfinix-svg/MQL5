//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh                                          |
//| 26-dimensional feature engineering for PASR AI subsystem        |
//| Sprint 10: Path fix ../Core/ -> ../../Core/                      |
//|            Path fix ../Data/ -> ../../Data/                      |
//| FIX #4:  AI Feature Leakage Prevention - Strict bar indexing    |
//| FIX AI-002: ATR multi-period handles (3,5,10,20) - was all ATR14|
//| FIX AI-006: UpdateBaselines() uses shift=1 (closed bar only)    |
//| FIX AI-001: InjectStructure/InjectRegime write into pending buf  |
//|             Build() applies pending injection before copy-out    |
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
//|                                                                  |
//| FIX #4:   All features use shift>=1 to prevent lookahead bias   |
//| FIX AI-002: Separate ATR handles per period (3,5,10,20)         |
//+------------------------------------------------------------------+
class CAIFeatureBuilder : public IManager
{
private:
   double   m_last_features[AI_FEATURE_DIM];
   bool     m_last_valid;
   datetime m_last_built;

   // Normalisation helpers
   double   m_atr_baseline;   // running ATR14 EMA for normalisation
   double   m_vol_baseline;   // running volume EMA
   int      m_build_count;

   //--- Cached indicator handles
   int      m_hRSI;
   int      m_hMACD;
   int      m_hCCI;
   int      m_hStoch;
   int      m_hMFI;
   int      m_hATR14;         // baseline ATR (period 14)
   // FIX AI-002: separate handles for ATR periods 3, 5, 10, 20
   int      m_hATR3;
   int      m_hATR5;
   int      m_hATR10;
   int      m_hATR20;

   //--- FIX #4: Feature leakage guard
   bool     m_useClosedBarsOnly;

   // FIX AI-001: pending injection buffer (applied inside Build() before copy-out)
   double   m_pending_sr_dist;
   double   m_pending_zone_str;
   double   m_pending_pattern;
   bool     m_pending_struct_valid;
   int      m_pending_regime;   // -1 = not set

   //--- Initialize indicator handles
   bool InitIndicators()
   {
      if(m_hRSI   == INVALID_HANDLE) m_hRSI   = iRSI        (_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      if(m_hMACD  == INVALID_HANDLE) m_hMACD  = iMACD       (_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
      if(m_hCCI   == INVALID_HANDLE) m_hCCI   = iCCI        (_Symbol, PERIOD_CURRENT, 14, PRICE_TYPICAL);
      if(m_hStoch == INVALID_HANDLE) m_hStoch = iStochastic (_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
      if(m_hMFI   == INVALID_HANDLE) m_hMFI   = iMFI        (_Symbol, PERIOD_CURRENT, 14);
      // ATR handles
      if(m_hATR14 == INVALID_HANDLE) m_hATR14 = iATR(_Symbol, PERIOD_CURRENT, 14);
      if(m_hATR3  == INVALID_HANDLE) m_hATR3  = iATR(_Symbol, PERIOD_CURRENT,  3); // FIX AI-002
      if(m_hATR5  == INVALID_HANDLE) m_hATR5  = iATR(_Symbol, PERIOD_CURRENT,  5); // FIX AI-002
      if(m_hATR10 == INVALID_HANDLE) m_hATR10 = iATR(_Symbol, PERIOD_CURRENT, 10); // FIX AI-002
      if(m_hATR20 == INVALID_HANDLE) m_hATR20 = iATR(_Symbol, PERIOD_CURRENT, 20); // FIX AI-002

      return (m_hRSI != INVALID_HANDLE && m_hMACD != INVALID_HANDLE &&
              m_hCCI != INVALID_HANDLE && m_hStoch != INVALID_HANDLE &&
              m_hMFI != INVALID_HANDLE && m_hATR14 != INVALID_HANDLE &&
              m_hATR3 != INVALID_HANDLE && m_hATR5 != INVALID_HANDLE &&   // FIX AI-002
              m_hATR10 != INVALID_HANDLE && m_hATR20 != INVALID_HANDLE);  // FIX AI-002
   }

   void CleanupIndicators()
   {
      if(m_hRSI   != INVALID_HANDLE) { IndicatorRelease(m_hRSI);   m_hRSI   = INVALID_HANDLE; }
      if(m_hMACD  != INVALID_HANDLE) { IndicatorRelease(m_hMACD);  m_hMACD  = INVALID_HANDLE; }
      if(m_hCCI   != INVALID_HANDLE) { IndicatorRelease(m_hCCI);   m_hCCI   = INVALID_HANDLE; }
      if(m_hStoch != INVALID_HANDLE) { IndicatorRelease(m_hStoch); m_hStoch = INVALID_HANDLE; }
      if(m_hMFI   != INVALID_HANDLE) { IndicatorRelease(m_hMFI);   m_hMFI   = INVALID_HANDLE; }
      if(m_hATR14 != INVALID_HANDLE) { IndicatorRelease(m_hATR14); m_hATR14 = INVALID_HANDLE; }
      if(m_hATR3  != INVALID_HANDLE) { IndicatorRelease(m_hATR3);  m_hATR3  = INVALID_HANDLE; } // FIX AI-002
      if(m_hATR5  != INVALID_HANDLE) { IndicatorRelease(m_hATR5);  m_hATR5  = INVALID_HANDLE; } // FIX AI-002
      if(m_hATR10 != INVALID_HANDLE) { IndicatorRelease(m_hATR10); m_hATR10 = INVALID_HANDLE; } // FIX AI-002
      if(m_hATR20 != INVALID_HANDLE) { IndicatorRelease(m_hATR20); m_hATR20 = INVALID_HANDLE; } // FIX AI-002
   }

   //--- FIX #4: Enforce closed bar shift
   double GetIndicatorValue(int handle, int buffer, int shift)
   {
      if(m_useClosedBarsOnly && shift < 1) shift = 1;
      double val[1];
      if(handle == INVALID_HANDLE || CopyBuffer(handle, buffer, shift, 1, val) <= 0)
         return 0.0;
      return val[0];
   }

   double PriceReturn(int bars_back)
   {
      int shift = m_useClosedBarsOnly ? MathMax(1, bars_back) : bars_back;
      double c0 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double cn = iClose(_Symbol, PERIOD_CURRENT, shift);
      if(cn == 0.0) return 0.0;
      return (c0 - cn) / cn;
   }

   // FIX AI-002: ATRRatio now uses the correct per-period handle
   double ATRRatioByHandle(int handle)
   {
      double atr = GetIndicatorValue(handle, 0, 1); // shift=1: closed bar
      if(m_atr_baseline <= 0.0) return 0.5;
      return MathMin(atr / m_atr_baseline, 3.0) / 3.0;
   }

   double NormIndicator(double val, double mn, double mx)
   {
      if(mx <= mn) return 0.5;
      return MathMax(0.0, MathMin(1.0, (val - mn) / (mx - mn)));
   }

   double ZScore(int n)
   {
      double arr[]; ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, n, arr) < n) return 0.0;
      double mean = 0.0, sq = 0.0;
      for(int i=0; i<n; i++) mean += arr[i];
      mean /= n;
      for(int i=0; i<n; i++) sq += MathPow(arr[i]-mean, 2);
      double sd = MathSqrt(sq / n);
      if(sd <= 0.0) return 0.0;
      return (arr[0] - mean) / sd;
   }

   double ReturnSkew(int n)
   {
      double arr[]; ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, n+1, arr) < n+1) return 0.0;
      double ret[]; ArrayResize(ret, n);
      for(int i=0; i<n; i++) ret[i] = (arr[i]-arr[i+1]) / MathMax(arr[i+1], 1e-10);
      double mean=0.0, sd=0.0, sk=0.0;
      for(int i=0;i<n;i++) mean += ret[i]; mean/=n;
      for(int i=0;i<n;i++) sd   += MathPow(ret[i]-mean,2); sd=MathSqrt(sd/n);
      if(sd<=0.0) return 0.0;
      for(int i=0;i<n;i++) sk += MathPow((ret[i]-mean)/sd, 3);
      return MathMax(-3.0, MathMin(3.0, sk/n)) / 3.0;
   }

   // FIX AI-006: UpdateBaselines uses shift=1 (closed bar), not shift=0
   void UpdateBaselines()
   {
      // FIX AI-006: explicit shift=1 bypasses GetIndicatorValue guard for clarity
      double atrVal[1];
      double atr = (CopyBuffer(m_hATR14, 0, 1, 1, atrVal) > 0) ? atrVal[0] : 0.0;
      double vol  = (double)iVolume(_Symbol, PERIOD_CURRENT, 1); // shift=1 closed bar
      double alpha = 0.05;
      if(m_atr_baseline <= 0.0) m_atr_baseline = atr;
      else m_atr_baseline = alpha*atr + (1.0-alpha)*m_atr_baseline;
      if(m_vol_baseline <= 0.0) m_vol_baseline = vol;
      else m_vol_baseline = alpha*vol + (1.0-alpha)*m_vol_baseline;
   }

public:
   CAIFeatureBuilder()
      : m_last_valid(false), m_last_built(0),
        m_atr_baseline(0.0), m_vol_baseline(0.0), m_build_count(0),
        m_hRSI(INVALID_HANDLE), m_hMACD(INVALID_HANDLE), m_hCCI(INVALID_HANDLE),
        m_hStoch(INVALID_HANDLE), m_hMFI(INVALID_HANDLE), m_hATR14(INVALID_HANDLE),
        m_hATR3(INVALID_HANDLE), m_hATR5(INVALID_HANDLE),                   // FIX AI-002
        m_hATR10(INVALID_HANDLE), m_hATR20(INVALID_HANDLE),                  // FIX AI-002
        m_useClosedBarsOnly(true),
        m_pending_sr_dist(0.5), m_pending_zone_str(0.5), m_pending_pattern(0.5),
        m_pending_struct_valid(false), m_pending_regime(-1)                   // FIX AI-001
   {
      ArrayInitialize(m_last_features, 0.0);
   }

   ~CAIFeatureBuilder() { CleanupIndicators(); }

   virtual bool Initialize(CEventBus *bus) override
   {
      if(!IManager::Initialize(bus)) return false;
      return InitIndicators();
   }

   virtual void Shutdown() override { CleanupIndicators(); IManager::Shutdown(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   //--- Build 26-dim feature vector
   //    FIX AI-001: pending injections are applied BEFORE copy-out so
   //    callers that call InjectStructure/InjectRegime before Build() work correctly.
   bool Build(SAIFeatureVector &out)
   {
      out.Reset();
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars < 50) return false;

      UpdateBaselines();

      double f[AI_FEATURE_DIM];

      // [0-3] Price returns
      f[0] = MathMax(-0.05, MathMin(0.05, PriceReturn(1))) / 0.05;
      f[1] = MathMax(-0.05, MathMin(0.05, PriceReturn(2))) / 0.05;
      f[2] = MathMax(-0.05, MathMin(0.05, PriceReturn(3))) / 0.05;
      f[3] = MathMax(-0.05, MathMin(0.05, PriceReturn(5))) / 0.05;

      // [4-7] ATR ratios — FIX AI-002: use correct per-period handle
      f[4] = ATRRatioByHandle(m_hATR3);
      f[5] = ATRRatioByHandle(m_hATR5);
      f[6] = ATRRatioByHandle(m_hATR10);
      f[7] = ATRRatioByHandle(m_hATR20);

      // [8-11] Momentum
      double rsi       = GetIndicatorValue(m_hRSI,   0, 0);
      double macd_main = GetIndicatorValue(m_hMACD,  0, 0);
      double macd_sig  = GetIndicatorValue(m_hMACD,  1, 0);
      double macd_hist = macd_main - macd_sig;
      double cci       = GetIndicatorValue(m_hCCI,   0, 0);
      double stoch     = GetIndicatorValue(m_hStoch, 0, 0);

      f[8]  = NormIndicator(rsi, 0.0, 100.0);
      f[9]  = MathMax(-1.0, MathMin(1.0, macd_hist / MathMax(m_atr_baseline, 1e-8))) * 0.5 + 0.5;
      f[10] = NormIndicator(cci, -200.0, 200.0);
      f[11] = NormIndicator(stoch, 0.0, 100.0);

      // [12-15] Volume
      double vol0      = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
      double vol1      = (double)iVolume(_Symbol, PERIOD_CURRENT, 2);
      double vol_ratio = (vol1 > 0.0) ? vol0 / vol1 : 1.0;
      double obv_delta = (iClose(_Symbol,PERIOD_CURRENT,1) > iClose(_Symbol,PERIOD_CURRENT,2)) ? vol0 : -vol0;
      double mfi       = GetIndicatorValue(m_hMFI, 0, 0);
      f[12] = NormIndicator(vol_ratio, 0.0, 5.0);
      f[13] = NormIndicator(obv_delta / MathMax(m_vol_baseline,1.0), -3.0, 3.0);
      f[14] = (m_vol_baseline > 0.0 && vol0 > 2.0*m_vol_baseline) ? 1.0 : 0.0;
      f[15] = NormIndicator(mfi, 0.0, 100.0);

      // [16-18] Structure — FIX AI-001: apply pending injection into f[] directly
      f[16] = m_pending_struct_valid ? m_pending_sr_dist   : 0.5;
      f[17] = m_pending_struct_valid ? m_pending_zone_str  : 0.5;
      f[18] = m_pending_struct_valid ? m_pending_pattern   : 0.5;

      // [19-21] Regime one-hot — FIX AI-001: apply pending regime into f[]
      if(m_pending_regime == (int)REGIME_TRENDING)
         { f[19]=1.0; f[20]=0.0; f[21]=0.0; }
      else if(m_pending_regime == (int)REGIME_VOLATILE)
         { f[19]=0.0; f[20]=0.0; f[21]=1.0; }
      else
         { f[19]=0.0; f[20]=1.0; f[21]=0.0; } // default: sideways

      // [22-23] Time
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      f[22] = (double)dt.hour        / 23.0;
      f[23] = (double)dt.day_of_week / 6.0;

      // [24-25] Statistical
      double z = ZScore(20);
      f[24] = MathMax(-3.0, MathMin(3.0, z)) / 3.0;
      f[25] = ReturnSkew(20);

      // Copy to output (features include injections)
      ArrayCopy(out.features, f);
      out.valid    = true;
      out.bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);

      // Cache for training use
      ArrayCopy(m_last_features, f);
      m_last_valid  = true;
      m_last_built  = TimeCurrent();
      m_build_count++;

      // Reset pending injections after consumption
      m_pending_struct_valid = false;
      m_pending_regime       = -1;

      return true;
   }

   // FIX AI-001: InjectStructure/InjectRegime write to pending buffer.
   // Must be called BEFORE Build() each bar to take effect.
   void InjectStructure(double sr_dist_norm, double zone_strength_norm, double pattern_score_norm)
   {
      m_pending_sr_dist      = sr_dist_norm;
      m_pending_zone_str     = zone_strength_norm;
      m_pending_pattern      = pattern_score_norm;
      m_pending_struct_valid = true;
   }

   void InjectRegime(EMarketRegime regime)
   {
      m_pending_regime = (int)regime;
   }

   const double *GetLastFeatures() const { return m_last_features; }
   bool          IsValid()         const { return m_last_valid;    }
   int           GetBuildCount()   const { return m_build_count;   }
};

#endif // __AI_FEATURE_BUILDER_MQH__
