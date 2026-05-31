//+------------------------------------------------------------------+
//| Signal/SRSignalSource.mqh — v1.10                                |
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
   datetime            m_lastEvaluated;
   ENUM_SIGNAL_DIR     m_lastDirection;
   double              m_lastConfidence;
   string              m_lastReason;
   double              m_lastZonePrice;
   double              m_lastZoneStrength;

   void StoreLast(SignalResult &out, const string reason, double zonePrice = 0.0, double zoneStrength = 0.0)
     {
      m_lastEvaluated = TimeCurrent();
      m_lastDirection = out.direction;
      m_lastConfidence = out.confidence;
      m_lastReason = reason;
      m_lastZonePrice = zonePrice;
      m_lastZoneStrength = zoneStrength;
     }

public:
   SRSignalSource(CAnalysisSRManager *sr, IDataManager *data, double proximityATR=0.5)
      : m_sr(sr), m_data(data), m_proximityATR(proximityATR),
        m_lastEvaluated(0), m_lastDirection(SIGNAL_NONE), m_lastConfidence(0.0),
        m_lastReason(""), m_lastZonePrice(0.0), m_lastZoneStrength(0.0) {}

   virtual string Name() override { return "SRSignalSource"; }

   virtual bool Evaluate(SignalResult &out) override
     {
      out.Clear();
      if(m_sr == NULL || m_data == NULL)
        {
         StoreLast(out, "SR/Data manager NULL");
         return false;
        }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0)
        {
         StoreLast(out, "Invalid bid");
         return false;
        }

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
            StoreLast(out, out.reason, zone.price, zone.strength);
            return true;
           }
         out.direction = SIGNAL_SELL;
         out.reason = StringFormat("SR_Resist p=%.5f str=%.0f", zone.price, zone.strength);
         StoreLast(out, out.reason, zone.price, zone.strength);
         return true;
        }

      out.direction = SIGNAL_NONE;
      out.confidence = 0.0;
      StoreLast(out, "No nearby SR zone");
      return false;
     }

   void SetProximity(double atrMult) { m_proximityATR = MathMax(0.1, atrMult); }
   datetime GetLastEvaluated() const { return m_lastEvaluated; }
   ENUM_SIGNAL_DIR GetLastDirection() const { return m_lastDirection; }
   double GetLastConfidence() const { return m_lastConfidence; }
   string GetLastReason() const { return m_lastReason; }
   double GetLastZonePrice() const { return m_lastZonePrice; }
   double GetLastZoneStrength() const { return m_lastZoneStrength; }
  };

#endif // __SIGNAL_SR_SOURCE_MQH__
