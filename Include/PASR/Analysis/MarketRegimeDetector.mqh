//+------------------------------------------------------------------+
//| Analysis/MarketRegimeDetector.mqh — v2.05                        |
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
   int              m_bb_period;
   double           m_bb_deviation;
   double           m_squeeze_thresh;
   double           m_vol_low_thresh;
   double           m_vol_high_thresh;
   double           m_trend_strength_thresh;
   double           m_crash_thresh;
   double           m_last_atr;
   double           m_last_adx;
   double           m_last_di_plus;
   double           m_last_di_minus;
   double           m_avg_atr;
   double           m_last_bb_bandwidth;
   double           m_avg_bb_bandwidth;
   datetime         m_last_update;
   ulong            m_update_count;
   EMarketRegime    m_prev_regime;
   int              m_regime_stable_bars;
   int              m_min_stable_bars;
   double           m_adx_hysteresis_band;

   int GetMinStableBarsForPeriod(ENUM_TIMEFRAMES tf) const
     {
      switch(tf)
        {
         case PERIOD_M1:
         case PERIOD_M5:
         case PERIOD_M15: return 5;
         case PERIOD_M30: return 4;
         case PERIOD_H1:
         case PERIOD_H4:  return 3;
         default:         return 3;
        }
     }

   double GetADXThresholdForPeriod(ENUM_TIMEFRAMES tf) const
     {
      switch(tf)
        {
         case PERIOD_M1:
         case PERIOD_M5:
         case PERIOD_M15: return 18.0;
         case PERIOD_M30: return 19.0;
         case PERIOD_H1:  return 21.0;
         case PERIOD_H4:  return 23.0;
         case PERIOD_D1:  return 25.0;
         default:         return 22.0;
        }
     }

   bool ReadADX(const string symbol, ENUM_TIMEFRAMES tf,
                double &adx, double &diPlus, double &diMinus) const
     {
      adx = 0.0; diPlus = 0.0; diMinus = 0.0;
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
      atr = 0.0; avgAtr = 0.0;
      int h = iATR(symbol, tf, m_atr_period);
      if(h == INVALID_HANDLE) return false;
      double cur[1];
      bool ok = (CopyBuffer(h, 0, 1, 1, cur) == 1);
      if(ok) atr = cur[0];
      int count = MathMax(1, m_vol_lookback);
      double buf[];
      ArrayResize(buf, count);
      int copied = CopyBuffer(h, 0, 1, count, buf);
      if(copied > 0)
        {
         double sum = 0.0;
         for(int i = 0; i < copied; i++) sum += buf[i];
         avgAtr = sum / copied;
        }
      IndicatorRelease(h);
      return ok;
     }

   bool ReadBBBandwidth(const string symbol, ENUM_TIMEFRAMES tf, double &currentBW, double &avgBW) const
     {
      currentBW = 0.0; avgBW = 0.0;
      int h = iBands(symbol, tf, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
      if(h == INVALID_HANDLE) return false;
      int count = MathMax(2, m_vol_lookback);
      double upper[], lower[], base[];
      ArrayResize(upper, count);
      ArrayResize(lower, count);
      ArrayResize(base, count);
      int cb = CopyBuffer(h, 0, 1, count, base);
      int cu = CopyBuffer(h, 1, 1, count, upper);
      int cl = CopyBuffer(h, 2, 1, count, lower);
      IndicatorRelease(h);
      int n = MathMin(cu, MathMin(cl, cb));
      if(n <= 0) return false;
      double sum = 0.0;
      int valid = 0;
      for(int i = 0; i < n; i++)
        {
         if(base[i] <= 0.0) continue;
         double bw = (upper[i] - lower[i]) / base[i];
         if(i == 0) currentBW = bw;
         sum += bw;
         valid++;
        }
      if(valid <= 0) return false;
      avgBW = sum / valid;
      return currentBW > 0.0 && avgBW > 0.0;
     }

   EMarketRegime AnalyzeRegime()
     {
      double volRatio = m_params.volatility_ratio;
      double adx = m_params.trend_strength;
      double momScore = m_params.momentum_score;
      double trendEnter = m_trend_strength_thresh + m_adx_hysteresis_band;
      double trendStay  = m_trend_strength_thresh - m_adx_hysteresis_band;
      if(volRatio > m_crash_thresh) return REGIME_CRASH;
      if(volRatio > m_vol_high_thresh) return REGIME_VOLATILE;
      if(adx <= m_trend_strength_thresh &&
         m_last_bb_bandwidth > 0.0 && m_avg_bb_bandwidth > 0.0 &&
         m_last_bb_bandwidth < m_squeeze_thresh * m_avg_bb_bandwidth)
         return REGIME_SQUEEZE;
      bool currentlyTrending = (m_current_regime == REGIME_TREND_UP || m_current_regime == REGIME_TREND_DOWN);
      bool isTrend = currentlyTrending ? (adx >= trendStay) : (adx >= trendEnter);
      if(isTrend)
        {
         if(momScore > 5.0) return REGIME_TREND_UP;
         if(momScore < -5.0) return REGIME_TREND_DOWN;
         return REGIME_TRANSITION;
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
         case REGIME_TRANSITION: AdjustParamsForTransition(); break;
         default:                ResetToDefault();            break;
        }
     }

   void AdjustParamsForTrend(bool bullish)
     {
      m_params.regime_name = bullish ? "TREND_UP" : "TREND_DOWN";
      m_params.sl_multiplier = 1.5;
      m_params.tp_multiplier = 2.0;
      m_params.risk_percent = 0.8;
      m_params.entry_threshold = 0.60;
      m_params.max_positions = 2;
     }

   void AdjustParamsForRange()
     {
      m_params.regime_name = "RANGE";
      m_params.sl_multiplier = 0.8;
      m_params.tp_multiplier = 1.2;
      m_params.risk_percent = 0.8;
      m_params.entry_threshold = 0.65;
      m_params.max_positions = 4;
     }

   void AdjustParamsForHighVol()
     {
      m_params.regime_name = "VOLATILE";
      m_params.sl_multiplier = 2.0;
      m_params.tp_multiplier = 1.5;
      m_params.risk_percent = 0.5;
      m_params.entry_threshold = 0.80;
      m_params.max_positions = 1;
     }

   void AdjustParamsForSqueeze()
     {
      m_params.regime_name = "SQUEEZE";
      m_params.sl_multiplier = 1.2;
      m_params.tp_multiplier = 1.5;
      m_params.risk_percent = 0.3;
      m_params.entry_threshold = 0.90;
      m_params.max_positions = 0;
     }

   void AdjustParamsForTransition()
     {
      m_params.regime_name = "TRANSITION";
      m_params.sl_multiplier = 1.4;
      m_params.tp_multiplier = 1.8;
      m_params.risk_percent = 0.5;
      m_params.entry_threshold = 0.75;
      m_params.max_positions = 1;
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

public:
   CMarketRegimeDetector() : m_current_regime(REGIME_UNKNOWN),
                             m_prev_regime(REGIME_UNKNOWN),
                             m_last_update(0), m_update_count(0),
                             m_regime_stable_bars(0), m_min_stable_bars(3),
                             m_adx_hysteresis_band(3.0)
     {
      m_atr_period = 14;
      m_adx_period = 14;
      m_vol_lookback = 50;
      m_bb_period = 20;
      m_bb_deviation = 2.0;
      m_squeeze_thresh = 0.5;
      m_vol_low_thresh = 0.5;
      m_vol_high_thresh = 2.0;
      m_trend_strength_thresh = 22.0;
      m_crash_thresh = 3.0;
      m_last_atr = 0.0;
      m_last_adx = 0.0;
      m_last_di_plus = 0.0;
      m_last_di_minus = 0.0;
      m_avg_atr = 0.0;
      m_last_bb_bandwidth = 0.0;
      m_avg_bb_bandwidth = 0.0;
      ResetToDefault();
     }

   void Deinit() {}
   void Shutdown() { Deinit(); }

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

   void SetSqueezeParameters(int bbPeriod, double bbDeviation, double squeezeThreshold)
     {
      m_bb_period = MathMax(2, bbPeriod);
      m_bb_deviation = (bbDeviation > 0.0) ? bbDeviation : 2.0;
      m_squeeze_thresh = (squeezeThreshold > 0.0) ? squeezeThreshold : 0.5;
      m_last_update = 0;
     }

   void SetHysteresis(int minStableBars, double adxBand)
     {
      m_min_stable_bars = MathMax(1, minStableBars);
      m_adx_hysteresis_band = MathMax(0.0, adxBand);
     }

   void ResetToDefault()
     {
      m_params.sl_multiplier = 1.0;
      m_params.tp_multiplier = 1.0;
      m_params.risk_percent = 1.0;
      m_params.entry_threshold = 0.55;
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

      m_min_stable_bars = GetMinStableBarsForPeriod(tf);
      if(m_trend_strength_thresh <= 0.0 || m_trend_strength_thresh == 22.0)
         m_trend_strength_thresh = GetADXThresholdForPeriod(tf);

      double atr = 0.0, avgAtr = 0.0;
      if(dataMgr != NULL)
         atr = dataMgr.GetATRPoints() * SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(atr <= 0.0 || !ReadATR(symbol, tf, atr, avgAtr))
         return m_current_regime;
      if(avgAtr <= 0.0) avgAtr = atr;

      double adx = 0.0, diPlus = 0.0, diMinus = 0.0;
      if(!ReadADX(symbol, tf, adx, diPlus, diMinus))
         return m_current_regime;

      double bbNow = 0.0, bbAvg = 0.0;
      ReadBBBandwidth(symbol, tf, bbNow, bbAvg);

      m_last_atr = atr;
      m_last_adx = adx;
      m_last_di_plus = diPlus;
      m_last_di_minus = diMinus;
      m_avg_atr = avgAtr;
      m_last_bb_bandwidth = bbNow;
      m_avg_bb_bandwidth = bbAvg;
      m_last_update = currentBarTime;
      m_update_count++;

      m_params.volatility_ratio = (m_avg_atr > 0.0) ? (atr / m_avg_atr) : 1.0;
      m_params.trend_strength = adx;
      m_params.momentum_score = diPlus - diMinus;

      EMarketRegime detected = AnalyzeRegime();
      if(detected != m_current_regime)
        {
         m_regime_stable_bars++;
         if(m_regime_stable_bars >= m_min_stable_bars)
           {
            int stableBars = m_regime_stable_bars;
            m_prev_regime = m_current_regime;
            m_current_regime = detected;
            m_regime_stable_bars = 0;
            ApplyRegimeAdjustments();
            PrintFormat("[Regime] Changed from %s to %s (stable after %d bars, ADX=%.1f th=%.1f)",
                        GetRegimeName(m_prev_regime), GetRegimeName(m_current_regime),
                        stableBars, m_last_adx, m_trend_strength_thresh);
           }
        }
      else
         m_regime_stable_bars = 0;

      return m_current_regime;
     }

   const SDynamicParams& GetParams() const { return m_params; }
   EMarketRegime GetCurrentRegime() const { return m_current_regime; }
   EMarketRegime GetRegime() const { return m_current_regime; }
   string GetRegimeName(EMarketRegime regime) const { return MarketRegimeName(regime); }
   ulong GetUpdateCount() const { return m_update_count; }
   datetime GetLastUpdate() const { return m_last_update; }

   string ExportRegimeInfo() const
     {
      return StringFormat("Regime=%s|VolRatio=%.2f|ADX=%.1f|Momentum=%.2f|BB=%.4f/%.4f|Risk=%.1f%%|StableBars=%d/%d",
                          GetRegimeName(m_current_regime), m_params.volatility_ratio,
                          m_params.trend_strength, m_params.momentum_score,
                          m_last_bb_bandwidth, m_avg_bb_bandwidth,
                          m_params.risk_percent * 100.0,
                          m_regime_stable_bars, m_min_stable_bars);
     }
  };

#endif // __ANALYSIS_MARKET_REGIME_DETECTOR_MQH__