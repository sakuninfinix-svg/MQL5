//+------------------------------------------------------------------+
//|                                  AdaptiveParameterManager.mqh    |
//|                        Copyright 2024, PASR Modular System       |
//|                                     Adaptive Dynamic Parameters  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Modular System"
#property link      "https://pasr.system"
#property version   "1.00"
#property description "Dynamic parameter adjustment based on market regime"

#include "../Infra/DataManager.mqh"
#include "../Core/EventBus.mqh"

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                        |
//+------------------------------------------------------------------+
enum EMarketRegime
  {
   REGIME_UNKNOWN       = 0,  // Data insufficient
   REGIME_LOW_VOL       = 1,  // Quiet market, tight ranges
   REGIME_HIGH_VOL      = 2,  // Volatile, wide swings
   REGIME_TRENDING_UP   = 3,  // Strong bullish momentum
   REGIME_TRENDING_DOWN = 4,  // Strong bearish momentum
   REGIME_CHOPPY        = 5   // Noisy, whipsaw behavior
  };

//+------------------------------------------------------------------+
//| Adaptive Configuration Structure                                 |
//+------------------------------------------------------------------+
struct SAdaptiveConfig
  {
   double StopLossPoints;         // Dynamic SL
   double TakeProfitPoints;       // Dynamic TP
   double TrailingStopPoints;     // Dynamic Trail
   double PositionSizePercent;    // Dynamic Risk %
   double EntryThreshold;         // Signal strength required
   int    MaxOpenPositions;       // Concurrent position limit
   
   // Internal state
   EMarketRegime CurrentRegime;
   double        ATR_Value;
   double        ADX_Value;
   ulong         LastUpdateBar;
  };

//+------------------------------------------------------------------+
//| CAdaptiveParameterManager Class                                  |
//+------------------------------------------------------------------+
class CAdaptiveParameterManager
  {
private:
   DataManager     *m_dataMgr;
   EventBus        *m_eventBus;
   SAdaptiveConfig m_config;
   
   // Indicator Handles
   int             m_handleATR;
   int             m_handleADX;
   int             m_handleMA;
   
   // Constants
   const int       ATR_PERIOD = 14;
   const int       ADX_PERIOD = 14;
   const int       MA_PERIOD  = 50;
   
   // Base Parameters (from input)
   double          m_baseSL;
   double          m_baseTP;
   double          m_baseRisk;
   
public:
   CAdaptiveParameterManager()
     {
      m_dataMgr       = NULL;
      m_eventBus      = NULL;
      m_handleATR     = INVALID_HANDLE;
      m_handleADX     = INVALID_HANDLE;
      m_handleMA      = INVALID_HANDLE;
      ZeroMemory(m_config);
      m_config.CurrentRegime = REGIME_UNKNOWN;
     }
     
   ~CAdaptiveParameterManager()
     {
      ReleaseIndicators();
     }
     
   //--- Initialization
   bool Initialize(DataManager *dataMgr, EventBus *eventBus, 
                   double baseSL, double baseTP, double baseRisk)
     {
      if(dataMgr == NULL || eventBus == NULL) return false;
      
      m_dataMgr  = dataMgr;
      m_eventBus = eventBus;
      m_baseSL   = baseSL;
      m_baseTP   = baseTP;
      m_baseRisk = baseRisk;
      
      // Create indicators
      m_handleATR = iATR(_Symbol, PERIOD_CURRENT, ATR_PERIOD);
      m_handleADX = iADX(_Symbol, PERIOD_CURRENT, ADX_PERIOD);
      m_handleMA  = iMA(_Symbol, PERIOD_CURRENT, MA_PERIOD, 0, MODE_SMA, PRICE_CLOSE);
      
      if(m_handleATR == INVALID_HANDLE || m_handleADX == INVALID_HANDLE || m_handleMA == INVALID_HANDLE)
        {
         Print("[AdaptiveParams] Failed to create indicators");
         return false;
        }
      
      return true;
     }
     
   //--- Main Update Logic (Call every tick/bar)
   bool UpdateParameters()
     {
      if(m_dataMgr == NULL) return false;
      
      // Check if new bar formed to avoid recalculation every tick
      ulong currentBar = (ulong)iBarShift(_Symbol, PERIOD_CURRENT, 0);
      if(currentBar == m_config.LastUpdateBar) return true; // Already updated for this bar
      
      // Get indicator values
      double atrBuffer[], adxBuffer[], maBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      ArraySetAsSeries(adxBuffer, true);
      ArraySetAsSeries(maBuffer, true);
      
      if(CopyBuffer(m_handleATR, 0, 0, 3, atrBuffer) <= 0) return false;
      if(CopyBuffer(m_handleADX, 0, 0, 3, adxBuffer) <= 0) return false;
      if(CopyBuffer(m_handleMA,  0, 0, 3, maBuffer) <= 0) return false;
      
      m_config.ATR_Value = atrBuffer[0];
      m_config.ADX_Value = adxBuffer[0]; // Main line
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double maValue      = maBuffer[0];
      
      // Detect Market Regime
      DetectRegime(currentPrice, maValue);
      
      // Adjust parameters based on regime
      AdjustParameters();
      
      m_config.LastUpdateBar = currentBar;
      
      // Publish update event
      SendAdaptiveUpdateEvent();
      
      return true;
     }
     
   //--- Getters
   double GetStopLoss() const { return m_config.StopLossPoints; }
   double GetTakeProfit() const { return m_config.TakeProfitPoints; }
   double GetPositionSize() const { return m_config.PositionSizePercent; }
   EMarketRegime GetRegime() const { return m_config.CurrentRegime; }
   
private:
   void DetectRegime(double price, double ma)
     {
      double atr = m_config.ATR_Value;
      double adx = m_config.ADX_Value;
      
      // Normalize ATR relative to price (percentage)
      double atrPct = (atr / price) * 100.0;
      
      // Simple regime detection logic
      if(adx > 25.0)
        {
         // Trending market
         if(price > ma) m_config.CurrentRegime = REGIME_TRENDING_UP;
         else           m_config.CurrentRegime = REGIME_TRENDING_DOWN;
        }
      else if(atrPct > 0.5) // High volatility threshold
        {
         m_config.CurrentRegime = REGIME_HIGH_VOL;
        }
      else if(atrPct < 0.2)
        {
         m_config.CurrentRegime = REGIME_LOW_VOL;
        }
      else
        {
         m_config.CurrentRegime = REGIME_CHOPPY;
        }
     }
     
   void AdjustParameters()
     {
      // Multipliers based on regime
      double slMult = 1.0, tpMult = 1.0, riskMult = 1.0, entryMult = 1.0;
      
      switch(m_config.CurrentRegime)
        {
         case REGIME_LOW_VOL:
            // Tighter stops, standard targets, normal risk
            slMult = 0.8; tpMult = 1.2; riskMult = 1.0; entryMult = 0.9;
            break;
            
         case REGIME_HIGH_VOL:
            // Wider stops, wider targets, reduced risk
            slMult = 1.5; tpMult = 1.5; riskMult = 0.7; entryMult = 1.1;
            break;
            
         case REGIME_TRENDING_UP:
         case REGIME_TRENDING_DOWN:
            // Wide stops to let trend run, bigger targets, normal/high risk
            slMult = 1.3; tpMult = 2.0; riskMult = 1.2; entryMult = 0.8;
            break;
            
         case REGIME_CHOPPY:
            // Very tight stops, quick targets, low risk (scalp mode)
            slMult = 0.6; tpMult = 0.8; riskMult = 0.5; entryMult = 1.2;
            break;
            
         default:
            // Fallback to base
            slMult = 1.0; tpMult = 1.0; riskMult = 1.0; entryMult = 1.0;
        }
      
      m_config.StopLossPoints       = m_baseSL * slMult;
      m_config.TakeProfitPoints     = m_baseTP * tpMult;
      m_config.TrailingStopPoints   = m_config.StopLossPoints * 0.5;
      m_config.PositionSizePercent  = m_baseRisk * riskMult;
      m_config.EntryThreshold       = 0.5 * entryMult; // Example threshold
      m_config.MaxOpenPositions     = (m_config.CurrentRegime == REGIME_HIGH_VOL || m_config.CurrentRegime == REGIME_CHOPPY) ? 1 : 3;
     }
     
   void SendAdaptiveUpdateEvent()
     {
      if(m_eventBus == NULL) return;
      
      // Pack data into event (simplified)
      // In real impl, use a struct payload
      m_eventBus->Publish(EVENT_ID_ADAPTIVE_UPDATE, 
                          (long)m_config.CurrentRegime, 
                          m_config.StopLossPoints, 
                          m_config.TakeProfitPoints);
     }
     
   void ReleaseIndicators()
     {
      if(m_handleATR != INVALID_HANDLE) IndicatorRelease(m_handleATR);
      if(m_handleADX != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleMA  != INVALID_HANDLE) IndicatorRelease(m_handleMA);
     }
  };
