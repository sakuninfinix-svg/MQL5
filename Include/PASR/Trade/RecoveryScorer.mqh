//+------------------------------------------------------------------+
//| Trade/RecoveryScorer.mqh — stub                                  |
//| Scores recovery opportunity for a losing position.               |
//| Full implementation pending — stub keeps PASR.mqh include chain  |
//| intact without breaking compilation.                             |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_TRADE_RECOVERY_SCORER_MQH__
#define __PASR_TRADE_RECOVERY_SCORER_MQH__

#include "../Core/IManager.mqh"

struct SRecoveryScore
  {
   double score;        // 0.0 – 1.0, higher = better recovery candidate
   bool   should_recover;
   string reason;

   void Reset()
     {
      score           = 0.0;
      should_recover  = false;
      reason          = "";
     }
  };

class CRecoveryScorer : public IManager
  {
public:
   CRecoveryScorer() : IManager() {}

   virtual string HandlerName() const override { return "RecoveryScorer"; }
   virtual bool Init(IDataManager *data, CEventBus *bus) override { return IManager::Init(data, bus); }
   virtual void Deinit() override { IManager::Deinit(); }
   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool Score(const ulong ticket, SRecoveryScore &out)
     {
      out.Reset();
      // TODO: implement recovery scoring logic
      return false;
     }
  };

#endif // __PASR_TRADE_RECOVERY_SCORER_MQH__
