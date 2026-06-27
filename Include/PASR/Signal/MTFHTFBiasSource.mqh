//+------------------------------------------------------------------+
//| Signal/MTFHTFBiasSource.mqh — v1.00                              |
//| Wraps CMTFBiasEngine as a VETO-style ISignalSource for use with   |
//| existing CSignalAggregator.                                       |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_MTF_HTF_BIAS_SOURCE_MQH__
#define __SIGNAL_MTF_HTF_BIAS_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "../Analysis/MTFBiasEngine.mqh"

class CMTFHTFBiasSource : public ISignalSource
  {
private:
   CMTFBiasEngine *m_engine;
   string          m_name;

public:
   CMTFBiasEngine *Engine() const { return m_engine; }

   CMTFHTFBiasSource()
      : m_engine(NULL), m_name("MTFHTFBias") { }

   void Bind(CMTFBiasEngine *engine)
     {
      m_engine = engine;
     }

   virtual string Name() override { return m_name; }

   virtual bool Evaluate(SignalResult &o) override
     {
      o.Clear();
      o.evaluatedAt = TimeCurrent();
      if(m_engine == NULL || !m_engine.IsReady()) return true;
      m_engine.Refresh();

      SMTFBiasSnapshot s = m_engine.GetSnapshot();
      bool blockBuys  = s.blockBuys;
      bool blockSells = s.blockSells;

      if(blockBuys && blockSells)
        {
         o.direction  = SIGNAL_NONE;
         o.confidence = m_engine.GetConfig().vetoConfidence;
         o.reason     = StringFormat("MTF flat-chop composite=%.2f atr=%.2f",
                                     s.compositeBias, s.htfAtrStrength);
         return true;
        }
      if(blockBuys)
        {
         o.direction  = SIGNAL_BUY;
         o.confidence = m_engine.GetConfig().vetoConfidence;
         o.reason     = StringFormat("MTF veto BUY composite=%.2f", s.compositeBias);
         return true;
        }
      if(blockSells)
        {
         o.direction  = SIGNAL_SELL;
         o.confidence = m_engine.GetConfig().vetoConfidence;
         o.reason     = StringFormat("MTF veto SELL composite=%.2f", s.compositeBias);
         return true;
        }
      o.direction  = SIGNAL_NONE;
      o.confidence = 0.0;
      o.reason     = "MTF aligned";
      return true;
     }
  };

#endif // __SIGNAL_MTF_HTF_BIAS_SOURCE_MQH__
