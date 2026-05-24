//+------------------------------------------------------------------+
//| Analysis/MarketRegimeDetector.mqh — v2.02                        |
//| Canonical EMarketRegime detector                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_MARKET_REGIME_DETECTOR_MQH__
#define __ANALYSIS_MARKET_REGIME_DETECTOR_MQH__

#include "../Infra/DataManager.mqh"
#include "../Data/RegimeTypes.mqh"

struct SDynamicParams
  {
   double sl_multiplier;
   double tp_multiplier;
   double risk_percent;
   double entry_threshold;
   int    max_positions;
   string regime_name;
   double volatility_ratio;
   double trend_strength;
   double momentum_score;
  };

class CMarketRegimeDetector
  {
private:
   EMarketRegime    m_current_regime;
   SDynamicParams   m_params;
   int              m_atr_period;
   int              m_adx_period;
   int              m_vol_lookback;
   double           m_vol_low_thresh;
   double           m_vol_high_thresh;
   double           m_trend_strength_thresh;
   double           m_crash_thresh;
   double           m_last_atr;
   double           m_last_adx;
   double           m_last_di_plus;
   double           m_last_di_minus;
   double           m_avg_atr;
   datetime         m_last_update;
   ulong            m_update_count;
   EMarketRegime    m_prev_regime;
   int              m_regime_stable_bars;
   const int        MIN_STABLE_BARS;

   bool ReadADX(const string symbol, ENUM_TIMEFRAMES tf,
                double &adx, double &diPlus, double &diMinus) const
     {
      adx = 0; diPlus = 0; diMinus = 0;
      int h = iADX(symbol, tf, m_adx_period);
      if(h == INVALID_HANDLE) return false;
      double b0[1], b1[1], b2[1];
      bool ok = (CopyBuffer(h, 0, 1, 1, b0) == 1 &&
                 CopyBuffer(h, 1, 1, 1, b1) == 1 &&
                 CopyBuffer(h, 2, 1, 1, b2) == 1);
      IndicatorRelease(h);
      if(!ok) return false;
      adx = b0[0]; diPlus = b1[0]; diMinus = b2[0];
      return true;
     }

   bool ReadATR(const string symbol, ENUM_TIMEFRAMES tf, double &atr, double &avgAtr) const
     {
      atr = 0; avgAtr = 0;
      int h = iATR(symbol, tf, m_atr_period);
      if(h == INVALID_HANDLE) return false;
      double cur[1];
      bool ok = (CopyBuffer(h, 0, 1, 1, cur) == 1);
      if(ok) atr = cur[0];
      int count = MathMax(1, m_vol_lookback);
      double buf[];
      ArrayResize(buf, count);
      if(CopyBuffer(h, 0, 1, count, buf) > 0)
        {
         double sum = 0.0;
         int n = ArraySize(buf);
         for(int i = 0; i < n; i++) sum += buf[i];
         avgAtr = (n > 0) ? sum / n : atr;
        }
      IndicatorRelease(h);
      return ok;
     }

public:
   CMarketRegimeDetector() : m_current_regime(REGIME_UNKNOWN),
                             m_prev_regime(REGIME_UNKNOWN),
                             m_last_update(0), m_update_count(0),
                             m_regime_stable_bars(0), MIN_STABLE_BARS(2)
     {
      m_atr_period = 14;
      m_adx_period = 14;
      m_vol_lookback = 50;
      m_vol_low_thresh = 0.5;
      m_vol_high_thresh = 2.0;
      m_trend_strength_thresh = 25.0;
      m_crash_thresh = 3.0;
      m_last_atr = 0;
      m_last_adx = 0;
      m_last_di_plus = 0;
      m_last_di_minus = 0;
      m_avg_atr = 0;
      ResetToDefault();
     }

   void SetParameters(int atrPeriod, int adxPeriod, int volLookback,
                      double volLowThresh, double volHighThresh,
                      double trendThresh, double crashThresh)
     {
      m_atr_period = MathMax(1, atrPeriod);
      m_adx_period = MathMax(1, adxPeriod);
      m_vol_lookback = MathMax(2, volLookback);
      m_vol_low_thresh = volLowThresh;
      m_vol_high_thresh = volHighThresh;
      m_trend_strength_thresh = trendThresh;
      m_crash_thresh = crashThresh;
      m_last_update = 0;
     }

   void ResetToDefault()
     {
      m_params.sl_multiplier = 1.0;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 1.0;
      m_params.entry_threshold = 0.5;
      m_params.max_positions = 3;
      m_params.regime_name = "UNKNOWN";
      m_params.volatility_ratio = 1.0;
      m_params.trend_strength = 0.0;
      m_params.momentum_score = 0.0;
     }

   EMarketRegime Detect(const string symbol, ENUM_TIMEFRAMES tf, DataManager *dataMgr)
     {
      datetime currentBarTime = iTime(symbol, tf, 0);
      if(currentBarTime == m_last_update && m_update_count > 0)
         return m_current_regime;

      double atr = 0, avgAtr = 0;
      if(dataMgr != NULL)
         atr = dataMgr.GetATRPoints() * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(atr <= 0 || !ReadATR(symbol, tf, atr, avgAtr))
         return m_current_regime;
      if(avgAtr <= 0) avgAtr = atr;

      double adx, diPlus, diMinus;
      if(!ReadADX(symbol, tf, adx, diPlus, diMinus))
         return m_current_regime;

      m_last_atr = atr;
      m_last_adx = adx;
      m_last_di_plus = diPlus;
      m_last_di_minus = diMinus;
      m_avg_atr = avgAtr;
      m_last_update = currentBarTime;
      m_update_count++;

      m_params.volatility_ratio = (m_avg_atr > 0) ? (atr / m_avg_atr) : 1.0;
      m_params.trend_strength = adx;
      m_params.momentum_score = diPlus - diMinus;

      EMarketRegime detected = AnalyzeRegime();
      if(detected != m_current_regime)
        {
         m_regime_stable_bars++;
         if(m_regime_stable_bars >= MIN_STABLE_BARS)
           {
            m_prev_regime = m_current_regime;
            m_current_regime = detected;
            m_regime_stable_bars = 0;
            ApplyRegimeAdjustments();
            PrintFormat("[Regime] Changed from %s to %s",
                        GetRegimeName(m_prev_regime), GetRegimeName(m_current_regime));
           }
        }
      else
         m_regime_stable_bars = 0;

      return m_current_regime;
     }

   const SDynamicParams& GetParams() const { return m_params; }
   EMarketRegime GetCurrentRegime() const { return m_current_regime; }
   EMarketRegime GetRegime() const { return m_current_regime; }

   string GetRegimeName(EMarketRegime regime) const
     {
      return MarketRegimeName(regime);
     }

   string ExportRegimeInfo() const
     {
      return StringFormat("Regime=%s|VolRatio=%.2f|ADX=%.1f|Momentum=%.2f|Risk=%.1f%%",
                          GetRegimeName(m_current_regime), m_params.volatility_ratio,
                          m_params.trend_strength, m_params.momentum_score,
                          m_params.risk_percent * 100.0);
     }

   ulong GetUpdateCount() const { return m_update_count; }
   datetime GetLastUpdate() const { return m_last_update; }

private:
   EMarketRegime AnalyzeRegime()
     {
      double volRatio = m_params.volatility_ratio;
      double adx = m_params.trend_strength;
      double momScore = m_params.momentum_score;
      if(volRatio > m_crash_thresh) return REGIME_CRASH;
      if(volRatio > m_vol_high_thresh) return REGIME_VOLATILE;
      if(adx > m_trend_strength_thresh)
        {
         if(momScore > 5.0) return REGIME_TREND_UP;
         if(momScore < -5.0) return REGIME_TREND_DOWN;
         return REGIME_VOLATILE;
        }
      return REGIME_RANGE;
     }

   void ApplyRegimeAdjustments()
     {
      switch(m_current_regime)
        {
         case REGIME_TREND_UP:   AdjustParamsForTrend(true);  break;
         case REGIME_TREND_DOWN: AdjustParamsForTrend(false); break;
         case REGIME_VOLATILE:   AdjustParamsForHighVol();    break;
         case REGIME_RANGE:      AdjustParamsForRange();      break;
         case REGIME_SQUEEZE:    AdjustParamsForSqueeze();    break;
         case REGIME_CRASH:      AdjustParamsForCrash();      break;
         default:                ResetToDefault();            break;
        }
     }

   void AdjustParamsForTrend(bool bullish)
     {
      m_params.regime_name = bullish ? "TREND_UP" : "TREND_DOWN";
      m_params.sl_multiplier = 1.5;
      m_params.tp_multiplier = 2.0;
      m_params.risk_percent = 1.2;
      m_params.entry_threshold = 0.4;
      m_params.max_positions = 2;
     }

   void AdjustParamsForRange()
     {
      m_params.regime_name = "RANGE";
      m_params.sl_multiplier = 0.8;
      m_params.tp_multiplier = 1.2;
      m_params.risk_percent = 0.8;
      m_params.entry_threshold = 0.7;
      m_params.max_positions = 4;
     }

   void AdjustParamsForHighVol()
     {
      m_params.regime_name = "VOLATILE";
      m_params.sl_multiplier = 2.0;
      m_params.tp_multiplier = 1.5;
      m_params.risk_percent = 0.5;
      m_params.entry_threshold = 0.8;
      m_params.max_positions = 1;
     }

   void AdjustParamsForSqueeze()
     {
      m_params.regime_name = "SQUEEZE";
      m_params.sl_multiplier = 0.7;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 0.6;
      m_params.entry_threshold = 0.6;
      m_params.max_positions = 2;
     }

   void AdjustParamsForCrash()
     {
      m_params.regime_name = "CRASH";
      m_params.sl_multiplier = 3.0;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 0.1;
      m_params.entry_threshold = 0.95;
      m_params.max_positions = 0;
     }
  };

#endif // __ANALYSIS_MARKET_REGIME_DETECTOR_MQH__
