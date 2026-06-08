//+------------------------------------------------------------------+
//| AI/SequenceFeatureBuilder.mqh — v1.00                            |
//| Builds [AI_SEQ_LEN x AI_SEQ_FEATURE_DIM] tensors for Transformer |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_SEQUENCE_FEATURE_BUILDER_MQH__
#define __AI_SEQUENCE_FEATURE_BUILDER_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

// Per-bar feature indices (row-major tensor)
#define SEQ_FEAT_NORM_RETURN    0
#define SEQ_FEAT_HL_ATR_RATIO   1
#define SEQ_FEAT_VOL_RATIO      2
#define SEQ_FEAT_BODY_RATIO     3
#define SEQ_FEAT_UPPER_WICK     4
#define SEQ_FEAT_LOWER_WICK     5
#define SEQ_FEAT_CLOSE_POS      6
#define SEQ_FEAT_SR_DIST        7
#define SEQ_FEAT_ZONE_STR       8
#define SEQ_FEAT_PATTERN        9
#define SEQ_FEAT_REGIME_TREND   10
#define SEQ_FEAT_BAR_AGE        11

class CSequenceFeatureBuilder : public IManager
  {
private:
   SAISequenceTensor m_last_tensor;
   bool              m_last_valid;
   datetime          m_last_built;
   int               m_build_count;
   int               m_hATR14;

   double            m_pending_sr_dist;
   double            m_pending_zone_str;
   double            m_pending_pattern;
   bool              m_pending_struct_valid;
   int               m_pending_regime;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

   void CleanupIndicators()
     {
      if(m_hATR14 != INVALID_HANDLE)
        {
         IndicatorRelease(m_hATR14);
         m_hATR14 = INVALID_HANDLE;
        }
     }

   bool InitIndicators()
     {
      if(m_hATR14 == INVALID_HANDLE)
         m_hATR14 = iATR(_Symbol, PERIOD_CURRENT, 14);
      return (m_hATR14 != INVALID_HANDLE);
     }

   double ATRAtShift(const int shift) const
     {
      if(m_hATR14 == INVALID_HANDLE) return 0.0;
      double buf[1];
      if(CopyBuffer(m_hATR14, 0, shift, 1, buf) <= 0) return 0.0;
      return buf[0];
     }

   double MeanVolume(const int startShift, const int count) const
     {
      if(count <= 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < count; i++)
         sum += (double)iVolume(_Symbol, PERIOD_CURRENT, startShift + i);
      return sum / (double)count;
     }

   bool IsTrendRegime() const
     {
      return (m_pending_regime == (int)REGIME_TREND_UP ||
              m_pending_regime == (int)REGIME_TREND_DOWN);
     }

public:
   CSequenceFeatureBuilder()
      : IManager(), m_last_valid(false), m_last_built(0), m_build_count(0),
        m_hATR14(INVALID_HANDLE),
        m_pending_sr_dist(0.5), m_pending_zone_str(0.5), m_pending_pattern(0.5),
        m_pending_struct_valid(false), m_pending_regime(-1)
     {
      m_last_tensor.Reset();
     }

   ~CSequenceFeatureBuilder() { CleanupIndicators(); }

   virtual string HandlerName() const override { return "SequenceFeatureBuilder"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      if(!InitIndicators())
        {
         Print("[SequenceFeatureBuilder] ATR indicator init failed");
         CleanupIndicators();
         IManager::Deinit();
         return false;
        }
      return true;
     }

   virtual void Deinit() override
     {
      CleanupIndicators();
      m_last_valid = false;
      m_last_tensor.Reset();
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_CONFIG_RELOAD)
         RefreshConfig();
     }

   void InjectStructure(double sr_dist_norm, double zone_strength_norm, double pattern_score_norm)
     {
      m_pending_sr_dist = Clamp01(sr_dist_norm);
      m_pending_zone_str = Clamp01(zone_strength_norm);
      m_pending_pattern = Clamp01(pattern_score_norm);
      m_pending_struct_valid = true;
     }

   void InjectRegime(EMarketRegime regime)
     {
      m_pending_regime = (int)regime;
     }

   bool Build(SAISequenceTensor &out)
     {
      out.Reset();
      if(!IsInitialized() && !InitIndicators()) return false;

      int bars = iBars(_Symbol, PERIOD_CURRENT);
      if(bars < AI_SEQ_LEN + 2) return false;

      out.seq_len = AI_SEQ_LEN;
      out.feat_dim = AI_SEQ_FEATURE_DIM;
      out.symbol = _Symbol;
      out.timeframe = _Period;
      out.regime = (m_pending_regime >= 0) ? (EMarketRegime)m_pending_regime : REGIME_UNKNOWN;
      out.newest_bar_time = iTime(_Symbol, PERIOD_CURRENT, 1);
      out.timestamp = TimeCurrent();

      const double srDist = m_pending_struct_valid ? Clamp01(m_pending_sr_dist) : 0.5;
      const double zoneStr = m_pending_struct_valid ? Clamp01(m_pending_zone_str) : 0.5;
      const double pattern = m_pending_struct_valid ? Clamp01(m_pending_pattern) : 0.5;
      const double regimeTrend = IsTrendRegime() ? 1.0 : 0.0;

      for(int b = 0; b < AI_SEQ_LEN; b++)
        {
         int shift = AI_SEQ_LEN - b;
         double open  = iOpen(_Symbol, PERIOD_CURRENT, shift);
         double high  = iHigh(_Symbol, PERIOD_CURRENT, shift);
         double low   = iLow(_Symbol, PERIOD_CURRENT, shift);
         double close = iClose(_Symbol, PERIOD_CURRENT, shift);
         double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
         if(open <= 0.0 || high <= 0.0 || low <= 0.0 || close <= 0.0 || prevClose <= 0.0)
            return false;

         double range = MathMax(high - low, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
         double body = MathAbs(close - open);
         double upperWick = high - MathMax(open, close);
         double lowerWick = MathMin(open, close) - low;

         double ret = (close - prevClose) / prevClose;
         ret = MathMax(-0.05, MathMin(0.05, ret)) / 0.05;
         double normRet = Clamp01(ret * 0.5 + 0.5);

         double atr = ATRAtShift(shift);
         double hlAtr = (atr > 0.0) ? Clamp01(range / (atr * 3.0)) : 0.5;

         double vol = (double)iVolume(_Symbol, PERIOD_CURRENT, shift);
         double volMean = MeanVolume(shift, 20);
         double volRatio = (volMean > 0.0) ? Clamp01(vol / (volMean * 3.0)) : 0.5;

         double bodyRatio = Clamp01(body / range);
         double upperRatio = Clamp01(upperWick / range);
         double lowerRatio = Clamp01(lowerWick / range);
         double closePos = Clamp01((close - low) / range);
         double barAge = (double)b / (double)MathMax(1, AI_SEQ_LEN - 1);

         out.Set(b, SEQ_FEAT_NORM_RETURN, normRet);
         out.Set(b, SEQ_FEAT_HL_ATR_RATIO, hlAtr);
         out.Set(b, SEQ_FEAT_VOL_RATIO, volRatio);
         out.Set(b, SEQ_FEAT_BODY_RATIO, bodyRatio);
         out.Set(b, SEQ_FEAT_UPPER_WICK, upperRatio);
         out.Set(b, SEQ_FEAT_LOWER_WICK, lowerRatio);
         out.Set(b, SEQ_FEAT_CLOSE_POS, closePos);
         out.Set(b, SEQ_FEAT_SR_DIST, srDist);
         out.Set(b, SEQ_FEAT_ZONE_STR, zoneStr);
         out.Set(b, SEQ_FEAT_PATTERN, pattern);
         out.Set(b, SEQ_FEAT_REGIME_TREND, regimeTrend);
         out.Set(b, SEQ_FEAT_BAR_AGE, barAge);
        }

      out.valid = true;
      m_last_tensor = out;
      m_last_valid = true;
      m_last_built = TimeCurrent();
      m_build_count++;

      m_pending_struct_valid = false;
      m_pending_regime = -1;
      return true;
     }

   bool GetLastTensor(SAISequenceTensor &dest) const
     {
      if(!m_last_valid) return false;
      dest = m_last_tensor;
      return true;
     }

   bool IsValid() const { return m_last_valid; }
   int  GetBuildCount() const { return m_build_count; }
  };

#endif // __AI_SEQUENCE_FEATURE_BUILDER_MQH__
