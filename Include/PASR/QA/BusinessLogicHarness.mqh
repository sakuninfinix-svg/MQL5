//+------------------------------------------------------------------+
//| QA/BusinessLogicHarness.mqh - deterministic lifecycle checks     |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__
#define __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__

#include "Assertions.mqh"
#include "../Trade/ExecutionLedger.mqh"
#include "../Trade/ExitConfirmationQueue.mqh"
#include "../AI/AIFeatureValidator.mqh"

class CBusinessLogicHarness
  {
private:
   CAssertions m_assert;

   void TestExecutionLedger()
     {
      m_assert.BeginSection("ExecutionLedger");

      TradePlan plan;
      plan.Clear();
      plan.valid = true;
      plan.direction = SIGNAL_BUY;
      plan.lot = 0.10;
      plan.entryPrice = 1.25000;
      plan.sl = 1.24000;
      plan.tp = 1.27000;

      CExecutionLedger ledger;
      ulong requestId = ledger.StartRequest(plan);
      ExecutionLedgerSnapshot snap = ledger.GetSnapshot();
      m_assert.IsTrue("request id allocated", requestId > 0);
      m_assert.AreEqual("requested state", (int)EXEC_LEDGER_REQUESTED, (int)snap.state);
      m_assert.IsTrue("pending after request", ledger.HasPending());

      ledger.MarkSent(12345, 10009, "Done");
      snap = ledger.GetSnapshot();
      m_assert.AreEqual("sent state", (int)EXEC_LEDGER_SENT, (int)snap.state);
      m_assert.AreEqual("order ticket stored", 12345, (int)snap.orderTicket);

      ledger.MarkFilled(777, 888, "BrokerDealIn");
      snap = ledger.GetSnapshot();
      m_assert.AreEqual("filled state", (int)EXEC_LEDGER_FILLED, (int)snap.state);
      m_assert.AreEqual("position ticket stored", 777, (int)snap.positionTicket);
      m_assert.AreEqual("deal ticket stored", 888, (int)snap.dealTicket);
      m_assert.IsFalse("not pending after fill", ledger.HasPending());

      requestId = ledger.StartRequest(plan);
      ledger.MarkRetrying(10004, 1, "Requote");
      snap = ledger.GetSnapshot();
      m_assert.AreEqual("retrying state", (int)EXEC_LEDGER_RETRYING, (int)snap.state);
      m_assert.AreEqual("retry count stored", 1, snap.retryCount);

      ledger.MarkRejected(10027, "Rejected");
      snap = ledger.GetSnapshot();
      m_assert.AreEqual("rejected state", (int)EXEC_LEDGER_REJECTED, (int)snap.state);
      m_assert.IsFalse("not pending after reject", ledger.HasPending());

      m_assert.EndSection();
     }

   void TestExitConfirmationQueue()
     {
      m_assert.BeginSection("ExitConfirmationQueue");

      CExitConfirmationQueue queue;
      ulong closeReq = queue.RequestClose(1001, 2, "TimeExit");
      ExitConfirmationSnapshot snap = queue.GetSnapshot();
      m_assert.IsTrue("close request id allocated", closeReq > 0);
      m_assert.AreEqual("one pending close", 1, snap.pendingCount);
      m_assert.AreEqual("close action stored", (int)EXIT_ACTION_CLOSE, snap.lastAction);
      m_assert.IsTrue("pending close visible", queue.HasPendingClose(1001));

      queue.MarkSent(1001, 10009, "CloseSent");
      snap = queue.GetSnapshot();
      m_assert.AreEqual("sent close state", (int)EXIT_CONFIRM_SENT, snap.lastState);

      queue.MarkConfirmed(1001, 5001, "BrokerDealOut");
      snap = queue.GetSnapshot();
      m_assert.AreEqual("close confirmed count", 1, snap.confirmedCount);
      m_assert.IsFalse("pending close cleared", queue.HasPendingClose(1001));

      ulong partialReq = queue.RequestPartial(2002, 4, 0.05, "HalfTarget");
      snap = queue.GetSnapshot();
      m_assert.IsTrue("partial request id allocated", partialReq > 0);
      m_assert.AreEqual("partial action stored", (int)EXIT_ACTION_PARTIAL, snap.lastAction);
      m_assert.IsNear("partial volume stored", 0.05, snap.lastRequestedVolume, 0.000001);

      queue.MarkRejected(2002, 10030, "InvalidVolume");
      ENUM_EXIT_REQUEST_ACTION action = EXIT_ACTION_NONE;
      double retryVolume = 0.0;
      int exitReason = 0;
      string retryReason = "";
      bool retry = queue.PrepareRetry(2002, action, retryVolume, exitReason, retryReason);
      snap = queue.GetSnapshot();
      m_assert.IsTrue("partial reject retryable", retry);
      m_assert.AreEqual("retry keeps partial action", (int)EXIT_ACTION_PARTIAL, (int)action);
      m_assert.IsNear("retry keeps volume", 0.05, retryVolume, 0.000001);
      m_assert.AreEqual("retry count incremented", 1, snap.lastRetryCount);
      m_assert.AreEqual("retry returns requested state", (int)EXIT_CONFIRM_REQUESTED, snap.lastState);

      queue.MarkConfirmed(2002, 6002, "BrokerDealOutPartial");
      m_assert.IsTrue("confirmed partial remembered", queue.HasConfirmedAction(2002, EXIT_ACTION_PARTIAL));

     m_assert.EndSection();
     }

   void TestAIFeatureValidator()
     {
      m_assert.BeginSection("AIFeatureValidator");

      CAIFeatureValidator validator;
      SAIFeatureVector fv;
      fv.Reset();
      fv.valid = true;
      fv.timestamp = TimeCurrent();
      fv.bar_time = TimeCurrent() - PeriodSeconds(PERIOD_CURRENT);
      fv.symbol = _Symbol;
      fv.timeframe = _Period;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         fv.features[i] = 0.5;

      AIFeatureValidationResult result;
      bool ok = validator.ValidateFeatures(fv, result);
      m_assert.IsTrue("valid features accepted", ok);
      m_assert.IsTrue("feature result valid", result.valid);

      fv.features[3] = 99.0;
      ok = validator.ValidateFeatures(fv, result);
      m_assert.IsFalse("out-of-range feature rejected", ok);
      m_assert.AreEqual("invalid index captured", 3, result.invalidIndex);

      fv.features[3] = 0.5;
      fv.bar_time = 0;
      ok = validator.ValidateFeatures(fv, result);
      m_assert.IsFalse("missing bar time rejected", ok);

      fv.bar_time = TimeCurrent() - PeriodSeconds(PERIOD_CURRENT);
      fv.timestamp = TimeCurrent() - 1000;
      validator.SetMaxStaleSec(10);
      ok = validator.ValidateFeatures(fv, result);
      m_assert.IsFalse("stale feature vector rejected", ok);

      ok = validator.ValidateModel(NULL, result);
      m_assert.IsFalse("missing model rejected", ok);

      m_assert.EndSection();
     }

public:
   void RunAll()
     {
      QA::Reset();
      Print("[BusinessLogicHarness] Start");
      TestExecutionLedger();
      TestExitConfirmationQueue();
      TestAIFeatureValidator();
      m_assert.PrintReport();
      if(QA::FailCount() == 0)
         Print("[BusinessLogicHarness] PASS");
      else
         Print("[BusinessLogicHarness] FAIL");
     }
  };

#endif // __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__
