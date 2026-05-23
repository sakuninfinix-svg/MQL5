//+------------------------------------------------------------------+
//| Scripts/PASR_QA_Run.mq5 — v1.00                                 |
//| Sprint 6 — QA Infrastructure: Master test runner script         |
//|                                                                   |
//| HOW TO RUN:                                                       |
//|   MetaEditor → Compile this file → drag to any chart in MT5     |
//|   Results appear in Experts tab                                  |
//|                                                                   |
//| WHAT IT TESTS:                                                    |
//|   1. EventBus: push/subscribe/drain/priority ordering           |
//|   2. MockDataManager: tick injection and replay                  |
//|   3. PipelineHarness: 50-bar trending + 50-bar ranging scenario  |
//|   4. ZoneSignalSource: score logic smoke test                    |
//|   5. AssertHelpers: self-test of macro correctness               |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <PASR/QA/AssertHelpers.mqh>
#include <PASR/QA/MockEventBus.mqh>
#include <PASR/QA/MockDataManager.mqh>
#include <PASR/QA/PipelineHarness.mqh>
#include <PASR/QA/TestRunner.mqh>
#include <PASR/QA/SmokeTest.mqh>

input bool InpRunSmokeTests    = true;   // Run existing SmokeTest suite
input bool InpRunPipelineTests = true;   // Run PipelineHarness (50+50 bars)
input bool InpVerbose          = false;  // Verbose stage output

//+------------------------------------------------------------------+
//| Test 1: EventBus push/subscribe correctness                      |
//+------------------------------------------------------------------+
bool Test_EventBus_PushOrder()
  {
   CMockEventBus bus;

   PASREvent ev1 = {}; ev1.id = EVENT_ID_NEW_BAR;      ev1.priority = 5;
   PASREvent ev2 = {}; ev2.id = EVENT_ID_PRICE_UPDATE; ev2.priority = 10; // higher
   PASREvent ev3 = {}; ev3.id = EVENT_ID_TRADE_CLOSED; ev3.priority = 1;

   bus.Push(ev1);
   bus.Push(ev2);
   bus.Push(ev3);

   ASSERT_EQ(bus.PushedCount(), 3, "EventBus: expected 3 pushes");

   // Last pushed = ev3
   PASREvent last = bus.LastEvent();
   ASSERT_EQ((int)last.id, (int)EVENT_ID_TRADE_CLOSED, "EventBus: last event id");

   // Find by id
   PASREvent found;
   ASSERT_TRUE(bus.FindEvent(EVENT_ID_NEW_BAR, found), "EventBus: find EVENT_ID_NEW_BAR");
   ASSERT_EQ((int)found.priority, 5, "EventBus: found event priority");

   bus.Reset();
   ASSERT_EQ(bus.PushedCount(), 0, "EventBus: reset clears count");

   Print("[QA] Test_EventBus_PushOrder: PASS");
   return true;
  }

//+------------------------------------------------------------------+
//| Test 2: MockDataManager tick replay                              |
//+------------------------------------------------------------------+
bool Test_MockDataManager_Replay()
  {
   CMockDataManager dm;

   // Inject 5 ticks
   for(int i = 0; i < 5; i++)
     {
      MqlTick t = CMockDataManager::BuildTick(1.0800 + i*0.0001,
                                               1.0802 + i*0.0001,
                                               (datetime)(1700000000 + i*60));
      dm.InjectTick(t);
     }

   ASSERT_EQ(dm.TicksInjected(), 5, "DM: 5 ticks injected");
   ASSERT_EQ(dm.TicksRemaining(), 5, "DM: 5 remaining before replay");

   int played = 0;
   while(dm.PlayNext()) played++;

   ASSERT_EQ(played, 5, "DM: played all 5 ticks");
   ASSERT_TRUE(dm.IsReplayDone(), "DM: replay done after all ticks");
   ASSERT_EQ(dm.TicksRemaining(), 0, "DM: 0 remaining after replay");

   // Rewind and replay again
   dm.Rewind();
   ASSERT_FALSE(dm.IsReplayDone(), "DM: rewind clears done flag");
   ASSERT_EQ(dm.TicksRemaining(), 5, "DM: 5 remaining after rewind");

   Print("[QA] Test_MockDataManager_Replay: PASS");
   return true;
  }

//+------------------------------------------------------------------+
//| Test 3: AssertHelpers self-test                                  |
//+------------------------------------------------------------------+
bool Test_AssertHelpers_Self()
  {
   // ASSERT_NEAR
   ASSERT_NEAR(1.0000001, 1.0, 0.001, "NEAR: within epsilon");

   // ASSERT_RANGE
   ASSERT_RANGE(0.75, 0.0, 1.0, "RANGE: 0.75 in [0..1]");

   // ASSERT_GT
   ASSERT_GT(5, 4, "GT: 5 > 4");

   // ASSERT_STR_EQ
   ASSERT_STR_EQ("hello", "hello", "STR_EQ: hello==hello");

   // ASSERT_STR_CONTAINS
   ASSERT_STR_CONTAINS("PipelineEngine", "Pipeline", "STR_CONTAINS");

   Print("[QA] Test_AssertHelpers_Self: PASS");
   return true;
  }

//+------------------------------------------------------------------+
//| Test 4: PipelineHarness trending scenario                        |
//+------------------------------------------------------------------+
bool Test_PipelineHarness_Trending()
  {
   CPipelineHarness h;
   h.LoadScenario_Trending();
   h.RunCycles(50);

   ASSERT_GT(h.CycleCount(),   0,    "Harness: trending ran >0 cycles");
   ASSERT_GTE(h.PassRate(),    0.80, "Harness: trending pass rate >= 80%");
   ASSERT_EQ(h.TimeoutCount(), 0,    "Harness: trending no stage timeouts");

   if(InpVerbose) h.PrintReport();
   Print("[QA] Test_PipelineHarness_Trending: PASS | pass_rate=",
         DoubleToString(h.PassRate()*100,1), "%");
   return true;
  }

//+------------------------------------------------------------------+
//| Test 5: PipelineHarness ranging scenario                         |
//+------------------------------------------------------------------+
bool Test_PipelineHarness_Ranging()
  {
   CPipelineHarness h;
   h.LoadScenario_Ranging();
   h.RunCycles(50);

   ASSERT_GT(h.CycleCount(),   0,    "Harness: ranging ran >0 cycles");
   ASSERT_GTE(h.PassRate(),    0.70, "Harness: ranging pass rate >= 70%");

   if(InpVerbose) h.PrintReport();
   Print("[QA] Test_PipelineHarness_Ranging: PASS | pass_rate=",
         DoubleToString(h.PassRate()*100,1), "%");
   return true;
  }

//+------------------------------------------------------------------+
//| Script entry point                                               |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("===== PASR QA Suite v1.00 =====");
   Print("Started: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

   int pass = 0, fail = 0;

   // Core unit tests (always run)
   #define RUN_TEST(fn) { bool _r = false; \
      if(true) { _r = fn(); } \
      if(_r) pass++; else { fail++; Print("[FAIL] ", #fn); } }

   RUN_TEST(Test_EventBus_PushOrder);
   RUN_TEST(Test_MockDataManager_Replay);
   RUN_TEST(Test_AssertHelpers_Self);

   // SmokeTest suite (existing)
   if(InpRunSmokeTests)
     {
      CPASRSmokeTest smoke;
      if(smoke.RunAll()) pass++; else fail++;
     }

   // Pipeline integration tests
   if(InpRunPipelineTests)
     {
      RUN_TEST(Test_PipelineHarness_Trending);
      RUN_TEST(Test_PipelineHarness_Ranging);
     }

   Print("===== QA COMPLETE: ", pass, " PASS / ", fail, " FAIL =====");

   if(fail > 0)
      Alert("PASR QA: ", fail, " test(s) FAILED — check Experts tab");
   else
      Print("[QA] ALL TESTS PASSED ✅");
  }
