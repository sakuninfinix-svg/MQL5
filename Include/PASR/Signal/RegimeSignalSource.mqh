//+------------------------------------------------------------------+
//| Signal/RegimeSignalSource.mqh — v1.04                            |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_REGIME_SOURCE_MQH__
#define __SIGNAL_REGIME_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "RegimeFilter.mqh"
#include "../Data/RegimeTypes.mqh"

enum ENUM_REGIME_SOURCE_MODE
  {
   REGIME_MODE_MODULATE = 0,
   REGIME_MODE_VETO     = 1
  };

class RegimeSignalSource : public ISignalSource
  {
private:
   CRegimeFilter           *m_regime;
   ENUM_REGIME_SOURCE_MODE  m_mode;

public:
   RegimeSignalSource(CRegimeFilter *regime, ENUM_REGIME_SOURCE_MODE mode=REGIME_MODE_VETO)
      : m_regime(regime), m_mode(mode) {}

   virtual string Name() override { return "RegimeSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_regime == NULL || !m_regime.IsReady())
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.5;
         out.reason     = "Regime:NotReady";
         return true;
        }

      EMarketRegime r = m_regime.GetRegime();

      if(m_mode == REGIME_MODE_VETO &&
         (r == REGIME_VOLATILE || r == REGIME_CRASH || r == REGIME_SQUEEZE))
        {
         out.direction  = SIGNAL_NONE;
         out.confidence = 0.0;
         out.reason     = StringFormat("RegimeGate:%s(ADX=%.1f,BW=%.4f)",
                                        MarketRegimeName(r), m_regime.GetADX(), m_regime.GetBW());
         return true;
        }

      double confMult = 1.0;
      switch(r)
        {
         case REGIME_RANGE:      confMult = 1.1; break;
         case REGIME_TREND_UP:
         case REGIME_TREND_DOWN: confMult = 0.7; break;
         case REGIME_TRANSITION: confMult = 0.6; break;
         case REGIME_SQUEEZE:    confMult = 0.0; break;
         case REGIME_VOLATILE:   confMult = 0.2; break;
         case REGIME_CRASH:      confMult = 0.0; break;
         default:                confMult = 1.0; break;
        }

      out.direction  = SIGNAL_NONE;
      out.confidence = confMult;
      out.reason     = StringFormat("Regime:%s(x%.1f)", MarketRegimeName(r), confMult);
      return true;
     }

   EMarketRegime GetCurrentRegime() const
     { return m_regime ? m_regime.GetRegime() : REGIME_UNKNOWN; }
  };

typedef RegimeSignalSource CRegimeSignalSource;

#endif // __SIGNAL_REGIME_SOURCE_MQH__