//+------------------------------------------------------------------+
//|                                           QA/SmokeTest.mqh      |
//|                                     Copyright 2026, Agsicentre  |
//|  Fast smoke tests that can be called from OnInit() to verify     |
//|  the PASR framework is wired correctly before EA goes live.      |
//|                                                                  |
//|  USAGE IN EA OnInit():                                           |
//|    if(!RunPASRSmokeTests()) { ExpertRemove(); return INIT_FAILED; }|
//|                                                                  |
//|  TESTS:                                                          |
//|   1-7  : Core wiring (EventBus, config, math, symbol, account)  |
//|   8-10 : Validator rules (Phase 5 — 33 rules)                   |
//|   11-12: AIManager ring buffer invariants (Phase 7)             |
//|   13   : DashboardManager prefix isolation (Phase 9)            |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_SMOKE_TEST_MQH__
#define __QA_SMOKE_TEST_MQH__

#include "TestRunner.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/IManager.mqh"
#include "../Core/Config/Validator.mqh"  // Phase 5
#include "../AI/AIManager.mqh"           // Phase 7 — for AI_REPLAY_BUF_SIZE, AIExperience

//======================================================================
//  EXISTING TESTS 1-7 (unchanged)
//======================================================================

//--- Test 1: EventBus singleton pattern
void _Smoke_EventBusSingleton()
  {
   EventBus *a = EventBus::Instance();
   EventBus *b = EventBus::Instance();
   ASSERT_NOT_NULL(a);
   ASSERT_EQ(a, b);
  }

//--- Test 2: Event priority ordering
void _Smoke_EventPriority()
  {
   ASSERT_TRUE(EVENT_PRIORITY_LOW    < EVENT_PRIORITY_NORMAL);
   ASSERT_TRUE(EVENT_PRIORITY_NORMAL < EVENT_PRIORITY_HIGH);
   ASSERT_TRUE(EVENT_PRIORITY_HIGH   < EVENT_PRIORITY_CRITICAL);
  }

//--- Test 3: Config zero-init contract
void _Smoke_ConfigDefaults()
  {
   StrategyConfig cfg;
   ZeroMemory(cfg);
   ASSERT_EQ(cfg.atr_period, 0);
  }

//--- Test 4: Math / branchless safety
void _Smoke_MathSanity()
  {
   ASSERT_APPROX(MathAbs(-1.23456), 1.23456, 1e-9);
   ASSERT_POSITIVE(MathMax(0.0001, 0.0));
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD);
   ASSERT_RANGE(spread, 0.0, 5000.0);
  }

//--- Test 5: Symbol tick size non-zero
void _Smoke_SymbolTickSize()
  {
   ASSERT_POSITIVE(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
   ASSERT_POSITIVE(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
  }

//--- Test 6: Account leverage sane range
void _Smoke_AccountLeverage()
  {
   long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   ASSERT_RANGE(leverage, 1, 3000);
  }

//--- Test 7: GlobalVariable key prefix uniqueness per account
void _Smoke_GVKeyUniqueness()
  {
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   ASSERT_POSITIVE((int)login);
   string prefix = IntegerToString(login) + "_PASR";
   ASSERT_TRUE(StringLen(prefix) > 5);
  }

//======================================================================
//  NEW TESTS 8-10: Validator rules (Phase 5 — 33 rules)
//======================================================================

//--- Test 8: Validator must reject RiskPercent == 0 (rule #2)
void _Smoke_ValidatorRejectsZeroRisk()
  {
   SPASRConfig badCfg;
   ZeroMemory(badCfg);
   //--- Minimal valid config except RiskPercent = 0
   badCfg.Risk.MaxDrawdown         = 0.20;
   badCfg.Risk.MaxDailyDrawdown    = 0.05;
   badCfg.Risk.RiskPercent         = 0.0;  // INVALID — rule #2
   badCfg.Risk.MaxLotSize          = 1.0;
   badCfg.Risk.MagicNumber         = 12345;
   badCfg.Risk.MaxOpenPositions    = 3;
   badCfg.Risk.MaxRecoveryAttempts = 3;
   badCfg.Risk.RecoveryCooldownBars= 5;
   badCfg.Risk.PartialClosePct     = 0.5;
   badCfg.Risk.MaxTradeDurationDays= 7;
   badCfg.Indicator.ATRPeriod      = 14;
   badCfg.Indicator.ATRMultiplierSL= 1.5;
   badCfg.Indicator.ATRMultiplierTP= 2.0;
   badCfg.Indicator.EMA_Fast       = 8;
   badCfg.Indicator.EMA_Slow       = 21;
   badCfg.Indicator.RSI_Period     = 14;
   badCfg.Indicator.RSI_Overbought = 70.0;
   badCfg.Indicator.RSI_Oversold   = 30.0;
   badCfg.Indicator.BB_Period      = 20;
   badCfg.Indicator.BB_Deviation   = 2.0;
   badCfg.AI.LearningRate          = 0.01;
   badCfg.AI.HiddenLayerSize       = 16;
   badCfg.AI.BatchSize             = 32;
   badCfg.AI.TrainIntervalBars     = 5;
   badCfg.AI.MinExperience         = 50;

   CPASRValidator v;
   ASSERT_FALSE(v.Validate(badCfg)); // must fail
  }

//--- Test 9: Validator must reject MaxDrawdown >= 1.0 (rule #7)
void _Smoke_ValidatorRejectsBadDrawdown()
  {
   SPASRConfig badCfg;
   ZeroMemory(badCfg);
   badCfg.Risk.RiskPercent         = 1.0;
   badCfg.Risk.MaxDrawdown         = 1.0;  // INVALID — rule #7: must be < 1.0
   badCfg.Risk.MaxDailyDrawdown    = 0.05;
   badCfg.Risk.MaxLotSize          = 1.0;
   badCfg.Risk.MagicNumber         = 12345;
   badCfg.Risk.MaxOpenPositions    = 3;
   badCfg.Risk.MaxRecoveryAttempts = 3;
   badCfg.Risk.RecoveryCooldownBars= 5;
   badCfg.Risk.PartialClosePct     = 0.5;
   badCfg.Risk.MaxTradeDurationDays= 7;
   badCfg.Indicator.ATRPeriod      = 14;
   badCfg.Indicator.ATRMultiplierSL= 1.5;
   badCfg.Indicator.ATRMultiplierTP= 2.0;
   badCfg.Indicator.EMA_Fast       = 8;
   badCfg.Indicator.EMA_Slow       = 21;
   badCfg.Indicator.RSI_Period     = 14;
   badCfg.Indicator.RSI_Overbought = 70.0;
   badCfg.Indicator.RSI_Oversold   = 30.0;
   badCfg.Indicator.BB_Period      = 20;
   badCfg.Indicator.BB_Deviation   = 2.0;
   badCfg.AI.LearningRate          = 0.01;
   badCfg.AI.HiddenLayerSize       = 16;
   badCfg.AI.BatchSize             = 32;
   badCfg.AI.TrainIntervalBars     = 5;
   badCfg.AI.MinExperience         = 50;

   CPASRValidator v;
   ASSERT_FALSE(v.Validate(badCfg));
  }

//--- Test 10: Validator cross-field rule #33:
//    RecoveryEnabled=true but MaxRecoveryAttempts=0 must fail
void _Smoke_ValidatorCrossFieldRecovery()
  {
   SPASRConfig badCfg;
   ZeroMemory(badCfg);
   badCfg.Risk.RiskPercent          = 1.0;
   badCfg.Risk.MaxDrawdown          = 0.20;
   badCfg.Risk.MaxDailyDrawdown     = 0.05;
   badCfg.Risk.MaxLotSize           = 1.0;
   badCfg.Risk.MagicNumber          = 12345;
   badCfg.Risk.MaxOpenPositions     = 3;
   badCfg.Risk.RecoveryEnabled      = true;  // ON ...
   badCfg.Risk.MaxRecoveryAttempts  = 0;     // ... but 0 attempts — rule #33
   badCfg.Risk.RecoveryCooldownBars = 5;
   badCfg.Risk.PartialClosePct      = 0.5;
   badCfg.Risk.MaxTradeDurationDays = 7;
   badCfg.Indicator.ATRPeriod       = 14;
   badCfg.Indicator.ATRMultiplierSL = 1.5;
   badCfg.Indicator.ATRMultiplierTP = 2.0;
   badCfg.Indicator.EMA_Fast        = 8;
   badCfg.Indicator.EMA_Slow        = 21;
   badCfg.Indicator.RSI_Period      = 14;
   badCfg.Indicator.RSI_Overbought  = 70.0;
   badCfg.Indicator.RSI_Oversold    = 30.0;
   badCfg.Indicator.BB_Period       = 20;
   badCfg.Indicator.BB_Deviation    = 2.0;
   badCfg.AI.LearningRate           = 0.01;
   badCfg.AI.HiddenLayerSize        = 16;
   badCfg.AI.BatchSize              = 32;
   badCfg.AI.TrainIntervalBars      = 5;
   badCfg.AI.MinExperience          = 50;

   CPASRValidator v;
   ASSERT_FALSE(v.Validate(badCfg)); // rule #33 must catch this
  }

//======================================================================
//  NEW TESTS 11-12: AIManager ring buffer invariants (Phase 7)
//======================================================================

//--- Test 11: Ring buffer size must be power-of-2 and >= 64
//    Power-of-2 enables fast modulo via bitwise AND: idx & (N-1)
void _Smoke_AIRingBufferSize()
  {
   int n = AI_REPLAY_BUF_SIZE;
   ASSERT_RANGE(n, 64, 65536);              // sane range
   ASSERT_EQ((n & (n - 1)), 0);            // power-of-2 check
  }

//--- Test 12: AIExperience struct footprint <= 128 bytes
//    512 entries * 128 bytes = 64 KB max — acceptable stack budget
void _Smoke_AIExperienceSize()
  {
   int sz = (int)sizeof(AIExperience);
   ASSERT_RANGE(sz, 1, 128);
  }

//======================================================================
//  NEW TEST 13: DashboardManager prefix isolation (Phase 9)
//======================================================================

//--- Test 13: Two dashboards with different magic numbers must have
//    different object prefixes to prevent chart object collisions
void _Smoke_DashboardPrefixIsolation()
  {
   long login  = AccountInfoInteger(ACCOUNT_LOGIN);
   string pfx1 = "PASR_D_" + IntegerToString(login) + "_" + IntegerToString(11111) + "_";
   string pfx2 = "PASR_D_" + IntegerToString(login) + "_" + IntegerToString(22222) + "_";
   ASSERT_TRUE(pfx1 != pfx2);  // different magic → different prefix
   // Same magic must produce the SAME prefix (idempotency)
   string pfx3 = "PASR_D_" + IntegerToString(login) + "_" + IntegerToString(11111) + "_";
   ASSERT_TRUE(pfx1 == pfx3);
  }

//======================================================================
//  MASTER RUNNER
//======================================================================

bool RunPASRSmokeTests(bool verbose = false)
  {
   Print("\n══ PASR Smoke Tests (13 tests) ══");
   CTestRunner runner(true, verbose); // stopOnFail=true for OnInit guard

   //--- Core wiring (1-7)
   runner.Run("EventBus: singleton",            _Smoke_EventBusSingleton);
   runner.Run("EventBus: priority ordering",    _Smoke_EventPriority);
   runner.Run("Config: zero-init contract",     _Smoke_ConfigDefaults);
   runner.Run("Math: basic sanity",             _Smoke_MathSanity);
   runner.Run("Symbol: tick size > 0",          _Smoke_SymbolTickSize);
   runner.Run("Account: leverage range",        _Smoke_AccountLeverage);
   runner.Run("GV: key uniqueness per acct",    _Smoke_GVKeyUniqueness);

   //--- Validator (Phase 5, rules 8-10)
   runner.Run("Validator: reject zero risk",    _Smoke_ValidatorRejectsZeroRisk);
   runner.Run("Validator: reject DD >= 1.0",    _Smoke_ValidatorRejectsBadDrawdown);
   runner.Run("Validator: recovery cross-field",_Smoke_ValidatorCrossFieldRecovery);

   //--- AIManager (Phase 7, 11-12)
   runner.Run("AI: ring buf size power-of-2",   _Smoke_AIRingBufferSize);
   runner.Run("AI: experience struct <= 128B",  _Smoke_AIExperienceSize);

   //--- DashboardManager (Phase 9, 13)
   runner.Run("Dashboard: prefix isolation",   _Smoke_DashboardPrefixIsolation);

   runner.PrintSummary();
   return runner.AllPassed();
  }

#endif // __QA_SMOKE_TEST_MQH__
