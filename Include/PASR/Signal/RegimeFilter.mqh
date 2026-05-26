//+------------------------------------------------------------------+
//| Signal/RegimeFilter.mqh — v1.03                                  |
//| Canonical regime filter using EMarketRegime from Data layer       |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_REGIME_FILTER_MQH__
#define __SIGNAL_REGIME_FILTER_MQH__

#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

#define RF_ATR_PERIOD    14
#define RF_ADX_PERIOD    14
#define RF_BB_PERIOD     20
#define RF_BB_DEVIATION  2.0
#define RF_HISTORY       50

class CRegimeFilter : public IManager
  {
private:
   int    m_hADX;
   int    m_hATR;
   int    m_hBB;

   double m_adxTrendThreshold;
   double m_atrVolatileRatio;
   double m_bwSqueezeRatio;

   EMarketRegime m_regime;
   double  m_currentADX;
   double  m_currentATR;
   double  m_atrMedian;
   double  m_currentBW;
   double  m_bwMedian;
   bool    m_ready;

   double  m_atrHistory[RF_HISTORY];
   double  m_bwHistory[RF_HISTORY];
   int     m_histIdx;
   int     m_histFilled;

   double GetADXThresholdForPeriod() const
     {
      switch(_Period)
        {
         case PERIOD_M1:
         case PERIOD_M5:  return 18.0;
         case PERIOD_M15: return 18.0;
         case PERIOD_M30: return 19.0;
         case PERIOD_H1:  return 21.0;
         case PERIOD_H4:  return 23.0;
         case PERIOD_D1:  return 25.0;
         default:         return 22.0;
        }
     }

   double CalcMedian(double &arr[], int n) const
     {
      if(n <= 0) return 0;
      double tmp[];
      ArrayResize(tmp, n);
      ArrayCopy(tmp, arr, 0, 0, n);
      for(int i = 1; i < n; i++)
        {
         double key = tmp[i];
         int j = i - 1;
         while(j >= 0 && tmp[j] > key)
           {
            tmp[j+1] = tmp[j];
            j--;
           }
         tmp[j+1] = key;
        }
      return (n % 2 == 1) ? tmp[n/2] : (tmp[n/2-1] + tmp[n/2]) * 0.5;
     }

   EMarketRegime DetermineRegime() const
     {
      if(!m_ready) return REGIME_UNKNOWN;
      if(m_atrMedian > 0 && m_currentATR > m_atrVolatileRatio * m_atrMedian)
         return REGIME_VOLATILE;
      if(m_bwMedian > 0 && m_currentBW < m_bwSqueezeRatio * m_bwMedian)
         return REGIME_SQUEEZE;
      if(m_currentADX >= m_adxTrendThreshold)
         return REGIME_TREND_UP;
      return REGIME_RANGE;
     }

   void UpdateOnNewBar()
     {
      double adxBuf[1], atrBuf[1], bbU[1], bbL[1], bbM[1];
      if(CopyBuffer(m_hADX, 0,          1, 1, adxBuf) < 1) return;
      if(CopyBuffer(m_hATR, 0,          1, 1, atrBuf) < 1) return;
      if(CopyBuffer(m_hBB,  UPPER_BAND, 1, 1, bbU)    < 1) return;
      if(CopyBuffer(m_hBB,  LOWER_BAND, 1, 1, bbL)    < 1) return;
      if(CopyBuffer(m_hBB,  BASE_LINE,  1, 1, bbM)    < 1) return;

      m_currentADX = adxBuf[0];
      m_currentATR = atrBuf[0];
      m_currentBW  = (bbM[0] > 0) ? (bbU[0] - bbL[0]) / bbM[0] : 0;

      m_atrHistory[m_histIdx] = m_currentATR;
      m_bwHistory[m_histIdx]  = m_currentBW;
      m_histIdx = (m_histIdx + 1) % RF_HISTORY;
      if(m_histFilled < RF_HISTORY) m_histFilled++;

      if(m_histFilled >= 10)
        {
         m_atrMedian = CalcMedian(m_atrHistory, m_histFilled);
         m_bwMedian  = CalcMedian(m_bwHistory,  m_histFilled);
         m_ready     = true;
        }

      EMarketRegime prev = m_regime;
      m_regime = DetermineRegime();

      if(m_debugMode && m_regime != prev)
         PrintFormat("[RegimeFilter] %s -> %s ADX=%.1f(th=%.1f) ATR=%.5f BW=%.3f",
                     MarketRegimeName(prev), MarketRegimeName(m_regime),
                     m_currentADX, m_adxTrendThreshold, m_currentATR, m_currentBW);
     }

public:
   CRegimeFilter() : IManager(),
      m_hADX(INVALID_HANDLE), m_hATR(INVALID_HANDLE), m_hBB(INVALID_HANDLE),
      m_adxTrendThreshold(22.0), m_atrVolatileRatio(1.8), m_bwSqueezeRatio(0.5),
      m_regime(REGIME_UNKNOWN), m_currentADX(0), m_currentATR(0),
      m_atrMedian(0), m_currentBW(0), m_bwMedian(0),
      m_ready(false), m_histIdx(0), m_histFilled(0)
     {
      ArrayInitialize(m_atrHistory, 0);
      ArrayInitialize(m_bwHistory,  0);
     }

   ~CRegimeFilter()
     {
      if(m_hADX != INVALID_HANDLE) { IndicatorRelease(m_hADX); m_hADX = INVALID_HANDLE; }
      if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
      if(m_hBB  != INVALID_HANDLE) { IndicatorRelease(m_hBB);  m_hBB  = INVALID_HANDLE; }
     }

   virtual string HandlerName() const override { return "RegimeFilter"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;

      m_adxTrendThreshold = GetADXThresholdForPeriod();
      m_hADX = iADX(_Symbol, _Period, RF_ADX_PERIOD);
      m_hATR = iATR(_Symbol, _Period, RF_ATR_PERIOD);
      m_hBB  = iBands(_Symbol, _Period, RF_BB_PERIOD, 0, RF_BB_DEVIATION, PRICE_CLOSE);

      if(m_hADX == INVALID_HANDLE || m_hATR == INVALID_HANDLE || m_hBB == INVALID_HANDLE)
        {
         Print("[RegimeFilter] Indicator init FAILED");
         return false;
        }
      return true;
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_NEW_BAR)
         UpdateOnNewBar();
     }

   virtual void OnNewBar() override
     {
      UpdateOnNewBar();
     }

   EMarketRegime GetRegime() const { return m_regime; }
   bool IsReady() const { return m_ready; }
   bool IsTrending() const { return (m_regime == REGIME_TREND_UP || m_regime == REGIME_TREND_DOWN); }
   bool IsRanging() const { return m_regime == REGIME_RANGE; }
   bool IsVolatile() const { return m_regime == REGIME_VOLATILE; }
   bool IsSqueeze() const { return m_regime == REGIME_SQUEEZE; }
   double GetADX() const { return m_currentADX; }
   double GetATR() const { return m_currentATR; }
   double GetBW() const { return m_currentBW; }
   double GetATRMedian() const { return m_atrMedian; }
   double GetADXThreshold() const { return m_adxTrendThreshold; }

   void SetThresholds(double adxTrend, double atrVolatile, double bwSqueeze)
     {
      m_adxTrendThreshold = (adxTrend > 0.0) ? adxTrend : GetADXThresholdForPeriod();
      m_atrVolatileRatio  = atrVolatile;
      m_bwSqueezeRatio    = bwSqueeze;
     }
  };

#endif // __SIGNAL_REGIME_FILTER_MQH__
