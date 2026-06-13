//+------------------------------------------------------------------+
//| QA/BusinessLogicHarness.mqh - deterministic lifecycle checks     |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__
#define __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__

#include "Assertions.mqh"
#include "../Trade/ExecutionLedger.mqh"
#include "../Trade/ExitConfirmationQueue.mqh"
#include "../Trade/PositionRegistry.mqh"
#include "../Infra/AccountSnapshot.mqh"
#include "../AI/AIFeatureValidator.mqh"
#include "../AI/ONNXBridge.mqh"
#include "../Signal/SignalDecisionEngine.mqh"

class CMockSignalSource : public ISignalSource
  {
private:
   string          m_name;
   ENUM_SIGNAL_DIR m_direction;
   double          m_confidence;
   string          m_reason;
   datetime        m_evaluatedAt;
   bool            m_enabled;

public:
   CMockSignalSource()
     {
      Configure("Mock", SIGNAL_NONE, 0.0, "unset", 0, true);
     }

   void Configure(const string name,
                  const ENUM_SIGNAL_DIR direction,
                  const double confidence,
                  const string reason,
                  const datetime evaluatedAt = 0,
                  const bool enabled = true)
     {
      m_name = name;
      m_direction = direction;
      m_confidence = confidence;
      m_reason = reason;
      m_evaluatedAt = evaluatedAt;
      m_enabled = enabled;
     }

   virtual string Name() override
     {
      return m_name;
     }

   virtual bool Evaluate(SignalResult &out) override
     {
      if(!m_enabled) return false;
      out.Clear();
      out.direction = m_direction;
      out.confidence = m_confidence;
      out.reason = m_reason;
      out.evaluatedAt = m_evaluatedAt;
      return true;
     }
  };

class CBusinessLogicHarness
  {
private:
   CAssertions m_assert;

   void TestStatePrimitives()
     {
      m_assert.BeginSection("StatePrimitives");

      SAccountSnapshot account;
      account.Clear();
      m_assert.IsFalse("cleared account invalid", account.valid);
      m_assert.IsFalse("cleared account not fresh", account.IsFresh());

      SPositionSnapshot pos;
      pos.Clear();
      m_assert.IsFalse("cleared position invalid", pos.IsValid());
      pos.ticket = 123;
      pos.symbol = _Symbol;
      pos.volume = 0.10;
      m_assert.IsTrue("minimal position snapshot valid", pos.IsValid());

      CPositionRegistry registry;
      m_assert.AreEqual("empty registry count", 0, registry.Count());
      m_assert.IsFalse("empty registry no position", registry.HasPosition());
      m_assert.IsFalse("empty registry no overflow", registry.Overflow());

      m_assert.EndSection();
     }

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

   void TestSignalDecisionEngine()
     {
      m_assert.BeginSection("SignalDecisionEngine");

      CSignalConfig config;
      config.Init();

      CMockSignalSource buyA;
      CMockSignalSource buyB;
      buyA.Configure("BuyA", SIGNAL_BUY, 0.80, "buy evidence A");
      buyB.Configure("BuyB", SIGNAL_BUY, 0.75, "buy evidence B");

      CSignalAggregator acceptedAgg;
      acceptedAgg.Init(config);
      acceptedAgg.RegisterSource(&buyA, 1.0);
      acceptedAgg.RegisterSource(&buyB, 1.0);

      CSignalDecisionEngine engine;
      SignalDecisionResult decision = engine.Decide(acceptedAgg);
      m_assert.IsTrue("aligned sources allow trade", decision.tradeAllowed);
      m_assert.AreEqual("accepted direction buy", (int)SIGNAL_BUY, (int)decision.direction);
      m_assert.AreEqual("accepted reason code", (int)SIGNAL_DECISION_ACCEPTED, (int)decision.reasonCode);
      m_assert.IsNear("accepted confidence average", 0.775, decision.confidence, 0.000001);

      CMockSignalSource sellA;
      sellA.Configure("SellA", SIGNAL_SELL, 0.80, "sell evidence A");

      CSignalAggregator conflictAgg;
      conflictAgg.Init(config);
      conflictAgg.RegisterSource(&buyA, 1.0);
      conflictAgg.RegisterSource(&sellA, 1.0);
      decision = engine.Decide(conflictAgg);
      m_assert.IsFalse("opposed sources block trade", decision.tradeAllowed);
      m_assert.IsTrue("conflict score captured", decision.conflictScore > 0.0);

      CMockSignalSource staleBuy;
      staleBuy.Configure("StaleBuy", SIGNAL_BUY, 0.95, "stale buy", TimeCurrent() - 1000);
      CSignalAggregator staleAgg;
      staleAgg.Init(config);
      staleAgg.RegisterSource(&staleBuy, 1.0);
      staleAgg.RegisterSource(&buyA, 1.0);
      decision = engine.Decide(staleAgg);
      m_assert.IsFalse("stale source blocks insufficient confluence", decision.tradeAllowed);
      m_assert.AreEqual("stale reason code", (int)SIGNAL_DECISION_STALE, (int)decision.reasonCode);

      m_assert.EndSection();
     }

   void TestSignalConfigBridge()
     {
      m_assert.BeginSection("SignalConfigBridge");

      StrategyConfig cfg;
      cfg.Pattern.MinPatternScore = 73.0;
      cfg.Pattern.LookbackBars = 64;
      cfg.Risk.RecoveryCooldownBars = 7;
      cfg.Market.SpreadFilterPips = 2.5;
      cfg.Market.SessionStartHour = 2;
      cfg.Market.SessionEndHour = 18;

      CSignalConfig config;
      config.ApplyStrategyConfig(cfg, true);

      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double pipFactor = (digits == 3 || digits == 5) ? 10.0 : 1.0;
      double expectedSpreadPoints = 2.5 * pipFactor;

      m_assert.AreEqual("lookback follows pattern config", 64, config.GetSignalLookback());
      m_assert.IsNear("aggregator min score follows pattern config", 0.73, config.GetMinScore(), 0.000001);
      m_assert.AreEqual("signal cooldown follows recovery cooldown", 7, config.GetSignalCooldownBars());
      m_assert.AreEqual("pattern failure cooldown follows recovery cooldown", 7, config.GetPatternFailureCooldownBars());
      m_assert.IsNear("spread filter converted to points", expectedSpreadPoints, config.GetMaxSpreadPoints(), 0.000001);
      m_assert.IsTrue("session filter enabled for restricted window", config.GetUseSessionFilter());
      m_assert.IsTrue("debug mode forwarded", config.GetDebugMode());

      cfg.Market.SessionStartHour = 0;
      cfg.Market.SessionEndHour = 23;
      config.ApplyStrategyConfig(cfg, false);
      m_assert.IsFalse("session filter disabled for full-day session", config.GetUseSessionFilter());
      m_assert.IsFalse("debug mode can be disabled", config.GetDebugMode());

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
      fv.features[0] = -0.25;
      fv.features[1] = 0.25;
      fv.features[2] = 0.0;
      fv.features[3] = 0.5;
      fv.features[19] = 0.0;
      fv.features[20] = 1.0;
      fv.features[21] = 0.0;

      AIFeatureValidationResult result;
      bool ok = validator.ValidateFeatures(fv, result);
      m_assert.IsTrue("valid features accepted", ok);
      m_assert.IsTrue("feature result valid", result.valid);

      fv.features[8] = 1.5;
      ok = validator.ValidateFeatures(fv, result);
      m_assert.IsFalse("out-of-range feature rejected", ok);
      m_assert.AreEqual("invalid index captured", 8, result.invalidIndex);
      m_assert.AreEqual("momentum group captured", 0, StringCompare(result.featureGroup, "momentum"));

      fv.features[8] = 0.5;
      fv.features[19] = 0.0;
      fv.features[20] = 0.0;
      fv.features[21] = 0.0;
      ok = validator.ValidateFeatures(fv, result);
      m_assert.IsFalse("invalid regime one-hot rejected", ok);
      m_assert.AreEqual("one-hot group captured", 0, StringCompare(result.featureGroup, "regime_onehot"));

      fv.features[20] = 1.0;
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

   void FillValidSequenceTensor(SAISequenceTensor &tensor)
     {
      tensor.Reset();
      tensor.valid = true;
      tensor.seq_len = AI_SEQ_LEN;
      tensor.feat_dim = AI_SEQ_FEATURE_DIM;
      tensor.timestamp = TimeCurrent();
      tensor.newest_bar_time = TimeCurrent() - PeriodSeconds(PERIOD_CURRENT);
      tensor.symbol = _Symbol;
      tensor.timeframe = _Period;
      for(int b = 0; b < AI_SEQ_LEN; b++)
        {
         for(int f = 0; f < AI_SEQ_FEATURE_DIM; f++)
            tensor.Set(b, f, 0.5);
         tensor.Set(b, SEQ_FEAT_BAR_AGE, (double)b / (double)MathMax(1, AI_SEQ_LEN - 1));
        }
     }

   void TestSequenceTensorValidator()
     {
      m_assert.BeginSection("SequenceTensorValidator");

      CAIFeatureValidator validator;
      SAISequenceTensor tensor;
      FillValidSequenceTensor(tensor);

      AIFeatureValidationResult result;
      bool ok = validator.ValidateSequence(tensor, result);
      m_assert.IsTrue("valid sequence tensor accepted", ok);
      m_assert.AreEqual("sequence feature dim", AI_SEQ_FEATURE_DIM, result.featureDim);
      m_assert.AreEqual("sequence flat size", AI_SEQ_TENSOR_SIZE, result.featureCount);

      tensor.Set(10, SEQ_FEAT_BODY_RATIO, 1.5);
      ok = validator.ValidateSequence(tensor, result);
      m_assert.IsFalse("out-of-range sequence value rejected", ok);
      m_assert.AreEqual("sequence candle group captured", 0, StringCompare(result.featureGroup, "seq_candle"));

      FillValidSequenceTensor(tensor);
      tensor.newest_bar_time = 0;
      ok = validator.ValidateSequence(tensor, result);
      m_assert.IsFalse("missing newest bar time rejected", ok);

      FillValidSequenceTensor(tensor);
      tensor.seq_len = AI_SEQ_LEN - 1;
      ok = validator.ValidateSequence(tensor, result);
      m_assert.IsFalse("shape mismatch rejected", ok);

      m_assert.EndSection();
     }

   void TestONNXBridgeStub()
     {
      m_assert.BeginSection("ONNXBridgeStub");

      CONNXBridge bridge;
      m_assert.IsFalse("sequence load disabled without compile flag",
                       bridge.LoadSequence("PASR_transformer.onnx", AI_SEQ_LEN, AI_SEQ_FEATURE_DIM, 2));
      m_assert.IsFalse("bridge not loaded by default", bridge.IsLoaded());

      double outputs[];
      int out_count = 0;
      float input[];
      ArrayResize(input, AI_SEQ_TENSOR_SIZE);
      ArrayInitialize(input, 0.5f);
      m_assert.IsFalse("sequence run fails when not loaded",
                       bridge.RunSequence(input, AI_SEQ_LEN, AI_SEQ_FEATURE_DIM, outputs, out_count));

      SAISequenceTensor tensor;
      FillValidSequenceTensor(tensor);
      m_assert.IsFalse("tensor run fails when bridge not loaded",
                       bridge.RunSequenceTensor(tensor, outputs, out_count));

      m_assert.EndSection();
     }

public:
   void RunAll()
     {
      QA::Reset();
      Print("[BusinessLogicHarness] Start");
      TestStatePrimitives();
      TestExecutionLedger();
      TestExitConfirmationQueue();
      TestSignalDecisionEngine();
      TestSignalConfigBridge();
      TestAIFeatureValidator();
      TestSequenceTensorValidator();
      TestONNXBridgeStub();
      m_assert.PrintReport();
      if(QA::FailCount() == 0)
         Print("[BusinessLogicHarness] PASS");
      else
         Print("[BusinessLogicHarness] FAIL");
     }
  };

#endif // __PASR_QA_BUSINESS_LOGIC_HARNESS_MQH__
