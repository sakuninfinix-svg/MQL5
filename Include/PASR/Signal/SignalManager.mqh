//+------------------------------------------------------------------+
//| Signal/SignalManager.mqh  — CANONICAL v2.12                      |
//| Event-driven: evaluates signals only on NewBar, not every tick   |
//+------------------------------------------------------------------+
#pragma once
#ifndef SIGNAL_SIGNAL_MANAGER_MQH
#define SIGNAL_SIGNAL_MANAGER_MQH

#include "../Core/IManager.mqh"
#include "../Core/Events.mqh"

//--- signal direction constants
enum ENUM_SIGNAL_DIR
  {
   SIGNAL_NONE  = 0,
   SIGNAL_BUY   = 1,
   SIGNAL_SELL  = -1
  };

//--- composite signal output
struct SignalResult
  {
   ENUM_SIGNAL_DIR  direction;
   double           confidence;   // 0.0 - 1.0
   double           entry;
   double           sl;
   double           tp;
   string           reason;
  };

//--- base interface for pluggable signal sources
class ISignalSource
  {
public:
   virtual bool      Evaluate(SignalResult &out) = 0;
   virtual string    Name()                      = 0;
  };

//+------------------------------------------------------------------+
//| CSignalManager — aggregates multiple ISignalSource plugins       |
//| Evaluation is deferred to OnNewBar only (not per-tick)           |
//+------------------------------------------------------------------+
class CSignalManager : public IManager
  {
private:
   ISignalSource    *m_sources[16];
   int               m_sourceCount;
   SignalResult      m_lastSignal;
   bool              m_hasSignal;
   datetime          m_lastBarTime;

   //--- weighted vote across sources
   void              AggregateSignals()
     {
      double buyScore  = 0.0;
      double sellScore = 0.0;
      int    valid     = 0;

      for(int i = 0; i < m_sourceCount; i++)
        {
         SignalResult res;
         ZeroMemory(res);
         if(!m_sources[i].Evaluate(res)) continue;
         valid++;
         if(res.direction == SIGNAL_BUY)  buyScore  += res.confidence;
         if(res.direction == SIGNAL_SELL) sellScore += res.confidence;
        }

      if(valid == 0) { m_hasSignal = false; return; }

      double threshold = m_cfg.SignalMinConfidence > 0.0
                         ? m_cfg.SignalMinConfidence : 0.6;

      if(buyScore > sellScore && (buyScore / valid) >= threshold)
        {
         m_lastSignal.direction  = SIGNAL_BUY;
         m_lastSignal.confidence = buyScore / valid;
         m_hasSignal = true;
        }
      else if(sellScore > buyScore && (sellScore / valid) >= threshold)
        {
         m_lastSignal.direction  = SIGNAL_SELL;
         m_lastSignal.confidence = sellScore / valid;
         m_hasSignal = true;
        }
      else
        {
         m_hasSignal = false;
        }
     }

public:
   CSignalManager() : m_sourceCount(0), m_hasSignal(false), m_lastBarTime(0) {}

   bool              RegisterSource(ISignalSource *src)
     {
      if(m_sourceCount >= 16 || src == NULL) return false;
      m_sources[m_sourceCount++] = src;
      return true;
     }

   //--- Only evaluate on new bar — O(sources), not O(ticks)
   void              OnNewBar() override
     {
      datetime barTime = iTime(_Symbol, (ENUM_TIMEFRAMES)m_cfg.Timeframe, 0);
      if(barTime == m_lastBarTime) return;
      m_lastBarTime = barTime;
      AggregateSignals();
      if(m_hasSignal && m_bus != NULL)
         m_bus.Publish(EVENT_SIGNAL_GENERATED);
     }

   void              OnPriceUpdate() override {} // intentionally empty

   bool              HasSignal()  const { return m_hasSignal; }
   SignalResult      GetSignal()  const { return m_lastSignal; }
   bool              IsHealthy()  const override { return m_sourceCount > 0; }
  };

#endif // SIGNAL_SIGNAL_MANAGER_MQH
