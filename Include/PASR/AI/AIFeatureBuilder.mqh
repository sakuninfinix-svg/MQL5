//+------------------------------------------------------------------+
//| AI/AIFeatureBuilder.mqh                                          |
//| copyright agsicentre                                             |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_FEATURE_BUILDER_MQH__
#define __AI_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

class CAIFeatureBuilder : public IManager
  {
private:
   double   m_last_features[AI_FEATURE_DIM];
   bool     m_last_valid;
   datetime m_last_built;
   double   m_atr_baseline;
   double   m_vol_baseline;
   int      m_build_count;

   int      m_hRSI;
   int      m_hMACD;
   int      m_hCCI;
   int      m_hStoch;
   int      m_hMFI;
   int      m_hATR14;
   int      m_hATR3;
   int      m_hATR5;
   int      m_hATR10;
   int      m_hATR20;

   bool     m_useClosedBarsOnly;
   double   m_pending_sr_dist;
   double   m_pending_zone_str;
   double   m_pending_pattern;
   bool     m_pending_struct_valid;
   int      m_pending_regime;

   double   m_pending_pattern_buy;
   double   m_pending_pattern_sell;
   double   m_pending_pattern_conflict;
   double   m_pending_pattern_gap;
   double   m_pending_pattern_rejection;
   double   m_pending_pattern_trap;
   double   m_pending_pattern_reclaim;
   double   m_pending_pattern_follow;
   bool     m_pending_pattern_features_valid;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

   bool InitIndicators()
     {
      if(m_hRSI   == INVALID_HANDLE) m_hRSI   = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      if(m_hMACD  == INVALID_HANDLE) m_hMACD  = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
      if(m_hCCI   == INVALID_HANDLE) m_hCCI   = iCCI(_Symbol, PERIOD_CURRENT, 14, PRICE_TYPICAL);
      if(m_hStoch == INVALID_HANDLE) m_hStoch = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
      if(m_hMFI   == INVALID_HANDLE) m_hMFI   = iMFI(_Symbol, PERIOD_CURRENT, 14, VOLUME_TICK);
      if(m_hATR14 == INVALID_HANDLE) m_hATR14 = iATR(_Symbol, PERIOD_CURRENT, 14);
      if(m_hATR3  == INVALID_HANDLE) m_hATR3  = iATR(_Symbol, PERIOD_CURRENT, 3);
      if(m_hATR5  == INVALID_HANDLE) m_hATR5  = iATR(_Symbol, PERIOD_CURRENT, 5);
      if(m_hATR10 == INVALID_HANDLE) m_hATR10 = iATR(_Symbol, PERIOD_CURRENT, 10);
      if(m_hATR20 == INVALID_HANDLE) m_hATR20 = iATR(_Symbol, PERIOD_CURRENT, 20);

      return (m_hRSI != INVALID_HANDLE && m_hMACD != INVALID_HANDLE &&
              m_hCCI != INVALID_HANDLE && m_hStoch != INVALID_HANDLE &&
              m_hMFI != INVALID_HANDLE && m_hATR14 != INVALID_HANDLE &&
              m_hATR3 != INVALID_HANDLE && m_hATR5 != INVALID_HANDLE &&
              m_hATR10 != INVALID_HANDLE && m_hATR20 != INVALID_HANDLE);
     }

   void CleanupIndicators()
     {
      if(m_hRSI   != INVALID_HANDLE) { IndicatorRelease(m_hRSI);   m_hRSI   = INVALID_HANDLE; }
      if(m_hMACD  != INVALID_HANDLE) { IndicatorRelease(m_hMACD);  m_hMACD  = INVALID_HANDLE; }
      if(m_hCCI   != INVALID_HANDLE) { IndicatorRelease(m_hCCI);   m_hCCI   = INVALID_HANDLE; }
      if(m_hStoch != INVALID_HANDLE) { IndicatorRelease(m_hStoch); m_hStoch = INVALID_HANDLE; }
      if(m_hMFI   != INVALID_HANDLE) { IndicatorRelease(m_hMFI);   m_hMFI   = INVALID_HANDLE; }
      if(m_hATR14 != INVALID_HANDLE) { IndicatorRelease(m_hATR14); m_hATR14 = INVALID_HANDLE; }
      if(m_hATR3  != INVALID_HANDLE) { IndicatorRelease(m_hATR3);  m_hATR3  = INVALID_HANDLE; }
      if(m_hATR5  != INVALID_HANDLE) { IndicatorRelease(m_hATR5);  m_hATR5  = INVALID_HANDLE; }
      if(m_hATR10 != INVALID_HANDLE) { IndicatorRelease(m_hATR10); m_hATR10 = INVALID_HANDLE; }
      if(m_hATR20 != INVALID_HANDLE) { IndicatorRelease(m_hATR20); m_hATR20 = INVALID_HANDLE; }
     }

   double GetIndicatorValue(int handle, int buffer, int shift)
     {
      if(m_useClosedBarsOnly && shift < 1) shift = 1;
      double val[1];
      if(handle == INVALID_HANDLE || CopyBuffer(handle, buffer, shift, 1, val) <= 0) return 0.0;
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

   double ATRRatioByHandle(int handle)
     {
      double atr = GetIndicatorValue(handle, 0, 1);
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
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, n, arr) < n) return 0.0;
      double mean = 0.0, sq = 0.0;
      for(int i = 0; i < n; i++) mean += arr[i];
      mean /= n;
      for(int i = 0; i < n; i++) sq += MathPow(arr[i] - mean, 2);
      double sd = MathSqrt(sq / n);
      if(sd <= 0.0) return 0.0;
      return (arr[0] - mean) / sd;
     }

   double ReturnSkew(int n)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyClose(_Symbol, PERIOD_CURRENT, 1, n + 1, arr) < n + 1) return 0.0;
      double ret[];
      ArrayResize(ret, n);
      for(int i = 0; i < n; i++) ret[i] = (arr[i] - arr[i+1]) / MathMax(arr[i+1], 1e-10);
      double mean = 0.0, sd = 0.0, sk = 0.0;
      for(int i = 0; i < n; i++) mean += ret[i];
      mean /= n;
      for(int i = 0; i < n; i++) sd += MathPow(ret[i] - mean, 2);
      sd = MathSqrt(sd / n);
      if(sd <= 0.0) return 0.0;
      for(int i = 0; i < n; i++) sk += MathPow((ret[i] - mean) / sd, 3);
      return MathMax(-3.0, MathMin(3.0, sk / n)) / 3.0;
     }

   void UpdateBaselines()
     {
      double atrVal[1];
      double atr = (m_hATR14 != INVALID_HANDLE && CopyBuffer(m_hATR14, 0, 1, 1, atrVal) > 0) ? atrVal[0] : 0.0;
      double vol = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
      double alpha = 0.05;
      if(m_atr_baseline <= 0.0) m_atr_baseline = atr;
      else m_atr_baseline = alpha * atr + (1.0 - alpha) * m_atr_baseline;
      if(m_vol_baseline <= 0.0) m_vol_baseline = vol;
      else m_vol_baseline = alpha * vol + (1.0 - alpha) * m_vol_baseline;
     }

public:
   CAIFeatureBuilder()
      : IManager(), m_last_valid(false), m_last_built(0),
        m_atr_baseline(0.0), m_vol_baseline(0.0), m_build_count(0),
        m_hRSI(INVALID_HANDLE), m_hMACD(INVALID_HANDLE), m_hCCI(INVALID_HANDLE),
        m_hStoch(INVALID_HANDLE), m_hMFI(INVALID_HANDLE), m_hATR14(INVALID_HANDLE),
        m_hATR3(INVALID_HANDLE), m_hATR5(INVALID_HANDLE),
        m_hATR10(INVALID_HANDLE), m_hATR20(INVALID_HANDLE),
        m_useClosedBarsOnly(true),
        m_pending_sr_dist(0.5), m_pending_zone_str(0.5), m_pending_pattern(0.5),
        m_pending_struct_valid(false), m_pending_regime(-1),
        m_pending_pattern_buy(0.0), m_pending_pattern_sell(0.0),
        m_pending_pattern_conflict(0.0), m_pending_pattern_gap(0.0),
        m_pending_pattern_rejection(0.0), m_pending_pattern_trap(0.0),
        m_pending_pattern_reclaim(0.0), m_pending_pattern_follow(0.0),
        m_pending_pattern_features_valid(false)
     {
      ArrayInitialize(m_last_features, 0.0);
     }

   ~CAIFeatureBuilder() { CleanupIndicators(); }

   virtual string HandlerName() const override { return "AIFeatureBuilder"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!InitIndicators())
        {
         Print("[AIFeatureBuilder] Indicator init failed");
         CleanupIndicators();
         IManager::Deinit();
         return false;
        }
      return true;
     }

   virtual void Deinit() override
     {
      CleanupIndicators();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override 
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
        {
         RefreshConfig();
        }
     }

   bool Build(SAIFeatureVector &out)
     {
      out.Reset();
      if(!IsInitialized() && !InitIndicators()) return false;
      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars < 50) return false;

      UpdateBaselines();

      double f[AI_FEATURE_DIM];
      ArrayInitialize(f, 0.0);
      f[0] = MathMax(-0.05, MathMin(0.05, PriceReturn(1))) / 0.05;
      f[1] = MathMax(-0.05, MathMin(0.05, PriceReturn(2))) / 0.05;
      f[2] = MathMax(-0.05, MathMin(0.05, PriceReturn(3))) / 0.05;
      f[3] = MathMax(-0.05, MathMin(0.05, PriceReturn(5))) / 0.05;

      f[4] = ATRRatioByHandle(m_hATR3);
      f[5] = ATRRatioByHandle(m_hATR5);
      f[6] = ATRRatioByHandle(m_hATR10);
      f[7] = ATRRatioByHandle(m_hATR20);

      double rsi = GetIndicatorValue(m_hRSI, 0, 1);
      double macd_main = GetIndicatorValue(m_hMACD, 0, 1);
      double macd_sig = GetIndicatorValue(m_hMACD, 1, 1);
      double macd_hist = macd_main - macd_sig;
      double cci = GetIndicatorValue(m_hCCI, 0, 1);
      double stoch = GetIndicatorValue(m_hStoch, 0, 1);

      f[8]  = NormIndicator(rsi, 0.0, 100.0);
      f[9]  = MathMax(-1.0, MathMin(1.0, macd_hist / MathMax(m_atr_baseline, 1e-8))) * 0.5 + 0.5;
      f[10] = NormIndicator(cci, -200.0, 200.0);
      f[11] = NormIndicator(stoch, 0.0, 100.0);

      double vol0 = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
      double vol1 = (double)iVolume(_Symbol, PERIOD_CURRENT, 2);
      double vol_ratio = (vol1 > 0.0) ? vol0 / vol1 : 1.0;
      double obv_delta = (iClose(_Symbol, PERIOD_CURRENT, 1) > iClose(_Symbol, PERIOD_CURRENT, 2)) ? vol0 : -vol0;
      double mfi = GetIndicatorValue(m_hMFI, 0, 1);
      f[12] = NormIndicator(vol_ratio, 0.0, 5.0);
      f[13] = NormIndicator(obv_delta / MathMax(m_vol_baseline, 1.0), -3.0, 3.0);
      f[14] = (m_vol_baseline > 0.0 && vol0 > 2.0 * m_vol_baseline) ? 1.0 : 0.0;
      f[15] = NormIndicator(mfi, 0.0, 100.0);

      f[16] = m_pending_struct_valid ? Clamp01(m_pending_sr_dist)  : 0.5;
      f[17] = m_pending_struct_valid ? Clamp01(m_pending_zone_str) : 0.5;
      f[18] = m_pending_struct_valid ? Clamp01(m_pending_pattern)  : 0.5;

      if(m_pending_regime == (int)REGIME_TREND_UP || m_pending_regime == (int)REGIME_TREND_DOWN)
        { f[19] = 1.0; f[20] = 0.0; f[21] = 0.0; }
      else if(m_pending_regime == (int)REGIME_VOLATILE || m_pending_regime == (int)REGIME_CRASH)
        { f[19] = 0.0; f[20] = 0.0; f[21] = 1.0; }
      else
        { f[19] = 0.0; f[20] = 1.0; f[21] = 0.0; }

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      f[22] = (double)dt.hour / 23.0;
      f[23] = (double)dt.day_of_week / 6.0;
      f[24] = MathMax(-3.0, MathMin(3.0, ZScore(20))) / 3.0;
      f[25] = ReturnSkew(20);

      f[26] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_buy)       : 0.0;
      f[27] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_sell)      : 0.0;
      f[28] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_conflict)  : 0.0;
      f[29] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_gap)       : 0.0;
      f[30] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_rejection) : 0.0;
      f[31] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_trap)      : 0.0;
      f[32] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_reclaim)   : 0.0;
      f[33] = m_pending_pattern_features_valid ? Clamp01(m_pending_pattern_follow)    : 0.0;

      ArrayCopy(out.features, f);
      out.valid = true;
      out.bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);

      ArrayCopy(m_last_features, f);
      m_last_valid = true;
      m_last_built = TimeCurrent();
      m_build_count++;

      m_pending_struct_valid = false;
      m_pending_pattern_features_valid = false;
      m_pending_regime = -1;
      return true;
     }

   void InjectStructure(double sr_dist_norm, double zone_strength_norm, double pattern_score_norm)
     {
      m_pending_sr_dist = Clamp01(sr_dist_norm);
      m_pending_zone_str = Clamp01(zone_strength_norm);
      m_pending_pattern = Clamp01(pattern_score_norm);
      m_pending_struct_valid = true;
     }

   void InjectPatternFeatures(double buyProb, double sellProb, double conflict, double dominanceGap,
                              double rejectionQuality, double trapQuality, double reclaimQuality,
                              double followThrough)
     {
      m_pending_pattern_buy = Clamp01(buyProb);
      m_pending_pattern_sell = Clamp01(sellProb);
      m_pending_pattern_conflict = Clamp01(conflict);
      m_pending_pattern_gap = Clamp01(dominanceGap);
      m_pending_pattern_rejection = Clamp01(rejectionQuality);
      m_pending_pattern_trap = Clamp01(trapQuality);
      m_pending_pattern_reclaim = Clamp01(reclaimQuality);
      m_pending_pattern_follow = Clamp01(followThrough);
      m_pending_pattern_features_valid = true;
     }

   void InjectRegime(EMarketRegime regime)
     {
      m_pending_regime = (int)regime;
     }

   bool GetLastFeatures(double &dest[]) const
     {
      if(!m_last_valid) return false;
      ArrayCopy(dest, m_last_features);
      return true;
     }
   bool IsValid() const { return m_last_valid; }
   int GetBuildCount() const { return m_build_count; }
  };

#endif // __AI_FEATURE_BUILDER_MQH__