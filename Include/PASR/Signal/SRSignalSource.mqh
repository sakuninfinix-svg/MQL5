//+------------------------------------------------------------------+
//| Signal/SRSignalSource.mqh — v1.00                                |
//| ISignalSource plugin: SR zone proximity → directional vote.     |
//| Price near support → BUY; near resistance → SELL.               |
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
   double              m_proximityATR; // proximity threshold in ATR units

public:
   SRSignalSource(CAnalysisSRManager *sr, IDataManager *data, double proximityATR=0.5)
      : m_sr(sr), m_data(data), m_proximityATR(proximityATR) {}

   virtual string Name() override { return "SRSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      if(m_sr == NULL || m_data == NULL) return false;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      SRZone zone;

      if(m_sr.IsNearZone(bid, m_proximityATR, zone))
        {
         double atr = m_data.GetATRPoints() * _Point;
         double dist = MathAbs(bid - zone.price);
         double rawConf = (atr > 0) ? MathMax(0.0, 1.0 - dist / (atr * m_proximityATR)) : 0.5;
         // Boost confidence by zone strength (0-100 mapped to 0-0.3 bonus)
         double strengthBonus = zone.strength / 100.0 * 0.3;
         out.confidence = MathMin(1.0, rawConf * 0.7 + strengthBonus);

         if(zone.isSupport)
           { out.direction=SIGNAL_BUY;
             out.reason=StringFormat("SR_Support p=%.5f str=%.0f", zone.price, zone.strength);
             return true; }
         else
           { out.direction=SIGNAL_SELL;
             out.reason=StringFormat("SR_Resist p=%.5f str=%.0f", zone.price, zone.strength);
             return true; }
        }

      out.direction=SIGNAL_NONE; out.confidence=0;
      return false;
     }

   void SetProximity(double atrMult) { m_proximityATR = MathMax(0.1, atrMult); }
  };

#endif
