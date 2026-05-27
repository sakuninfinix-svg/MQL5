//+------------------------------------------------------------------+
//| Signal/SRSignalSource.mqh — v1.01                                |
//| ISignalSource plugin: SR zone proximity → directional vote.      |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_SR_SOURCE_MQH__
#define __SIGNAL_SR_SOURCE_MQH__

#include "ISignalSource.mqh"
#include "../Analysis/SRManager.mqh"

class SRSignalSource : public ISignalSource
  {
private:
   CAnalysisSRManager *m_sr;
   IDataManager       *m_data;
   double              m_proximityATR;

public:
   SRSignalSource(CAnalysisSRManager *sr, IDataManager *data, double proximityATR=0.5)
      : m_sr(sr), m_data(data), m_proximityATR(proximityATR) {}

   virtual string Name() override { return "SRSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_sr == NULL || m_data == NULL) return false;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0) return false;

      SRZoneExtended zone;
      if(m_sr.IsNearValidZone(bid, m_proximityATR, zone))
        {
         double atr = m_data.GetATRPoints() * _Point;
         double dist = MathAbs(bid - zone.price);
         double rawConf = (atr > 0.0) ? MathMax(0.0, 1.0 - dist / (atr * m_proximityATR)) : 0.5;
         double strengthBonus = zone.strength / 100.0 * 0.3;
         out.confidence = MathMin(1.0, rawConf * 0.7 + strengthBonus);

         if(zone.isSupport)
           {
            out.direction = SIGNAL_BUY;
            out.reason = StringFormat("SR_Support p=%.5f str=%.0f", zone.price, zone.strength);
            return true;
           }
         out.direction = SIGNAL_SELL;
         out.reason = StringFormat("SR_Resist p=%.5f str=%.0f", zone.price, zone.strength);
         return true;
        }

      out.direction = SIGNAL_NONE;
      out.confidence = 0.0;
      return false;
     }

   void SetProximity(double atrMult) { m_proximityATR = MathMax(0.1, atrMult); }
  };

#endif // __SIGNAL_SR_SOURCE_MQH__