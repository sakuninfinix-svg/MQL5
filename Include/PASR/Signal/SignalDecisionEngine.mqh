//+------------------------------------------------------------------+
//| Signal/SignalDecisionEngine.mqh - v1.00                          |
//| Formal final signal/no-trade contract for the PASR signal layer. |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_DECISION_ENGINE_MQH__
#define __SIGNAL_DECISION_ENGINE_MQH__

#include "SignalAggregator.mqh"

enum ENUM_SIGNAL_DECISION_REASON
  {
   SIGNAL_DECISION_NONE        = 0,
   SIGNAL_DECISION_ACCEPTED    = 1,
   SIGNAL_DECISION_NO_SOURCES  = 2,
   SIGNAL_DECISION_VETOED      = 3,
   SIGNAL_DECISION_CONFLICT    = 4,
   SIGNAL_DECISION_NO_CONSENSUS= 5,
   SIGNAL_DECISION_STALE       = 6
  };

struct SignalDecisionResult
  {
   bool                         tradeAllowed;
   ENUM_SIGNAL_DIR              direction;
   double                       confidence;
   string                       primarySource;
   int                          sourceCount;
   int                          confluence;
   double                       conflictScore;
   double                       dominanceGap;
   bool                         vetoed;
   string                       vetoReason;
   ENUM_SIGNAL_DECISION_REASON  reasonCode;
   string                       reason;
   datetime                     decidedAt;

   void Clear()
     {
      tradeAllowed = false;
      direction = SIGNAL_NONE;
      confidence = 0.0;
      primarySource = "";
      sourceCount = 0;
      confluence = 0;
      conflictScore = 0.0;
      dominanceGap = 0.0;
      vetoed = false;
      vetoReason = "";
      reasonCode = SIGNAL_DECISION_NONE;
      reason = "";
      decidedAt = 0;
     }
  };

class CSignalDecisionEngine
  {
private:
   datetime m_lastDecisionTime;
   SignalDecisionResult m_lastDecision;
   AggregatedSignal m_lastAggregated;

   ENUM_SIGNAL_DECISION_REASON ClassifyReason(const AggregatedSignal &agg,
                                              const SignalAggregatorSnapshot &snap) const
     {
      if(snap.sourceCount <= 0)
         return SIGNAL_DECISION_NO_SOURCES;
      if(agg.vetoed || snap.vetoActive)
         return SIGNAL_DECISION_VETOED;
      if(agg.direction != SIGNAL_NONE)
         return SIGNAL_DECISION_ACCEPTED;
      if(snap.staleSourceCount > 0)
         return SIGNAL_DECISION_STALE;
      if(snap.bullConfluence > 0 && snap.bearConfluence > 0 && snap.dominanceGap > 0.0)
         return SIGNAL_DECISION_CONFLICT;
      return SIGNAL_DECISION_NO_CONSENSUS;
     }

public:
   CSignalDecisionEngine()
     {
      m_lastDecisionTime = 0;
      m_lastDecision.Clear();
      m_lastAggregated.Clear();
     }

   SignalDecisionResult Decide(CSignalAggregator &aggregator)
     {
      SignalDecisionResult out;
      out.Clear();

      AggregatedSignal agg = aggregator.Aggregate();
      SignalAggregatorSnapshot snap = aggregator.GetSnapshot();
      m_lastAggregated = agg;

      out.decidedAt = TimeCurrent();
      out.sourceCount = snap.sourceCount;
      out.confluence = agg.confluence;
      out.conflictScore = snap.conflictScore;
      out.dominanceGap = snap.dominanceGap;
      out.vetoed = agg.vetoed || snap.vetoActive;
      out.vetoReason = snap.vetoReason;
      out.reasonCode = ClassifyReason(agg, snap);
      out.reason = snap.lastDecisionReason;

      if(out.reason == "")
        {
         if(out.reasonCode == SIGNAL_DECISION_ACCEPTED) out.reason = "Accepted";
         else if(out.reasonCode == SIGNAL_DECISION_VETOED) out.reason = "Vetoed";
         else if(out.reasonCode == SIGNAL_DECISION_CONFLICT) out.reason = "Conflict no-trade";
         else if(out.reasonCode == SIGNAL_DECISION_STALE) out.reason = "Stale source no-trade";
         else if(out.reasonCode == SIGNAL_DECISION_NO_SOURCES) out.reason = "No signal sources";
         else out.reason = "No consensus";
        }

      if(out.reasonCode == SIGNAL_DECISION_ACCEPTED)
        {
         out.tradeAllowed = true;
         out.direction = agg.direction;
         out.confidence = agg.normalizedScore;
         out.primarySource = agg.contributingSources;
        }

      m_lastDecision = out;
      m_lastDecisionTime = out.decidedAt;
      return out;
     }

   SignalDecisionResult GetLastDecision() const { return m_lastDecision; }
   AggregatedSignal GetLastAggregated() const { return m_lastAggregated; }
   datetime GetLastDecisionTime() const { return m_lastDecisionTime; }
  };

#endif // __SIGNAL_DECISION_ENGINE_MQH__
