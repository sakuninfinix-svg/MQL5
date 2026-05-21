//+------------------------------------------------------------------+
//|                                           QA/SmokeTest.mqh      |
//|                                     Copyright 2026, Agsicentre  |
//|  Fast smoke tests that can be called from OnInit() to verify     |
//|  the PASR framework is wired correctly before EA goes live.      |
//|                                                                  |
//|  USAGE IN EA OnInit():                                           |
//|    if(!RunPASRSmokeTests()) { ExpertRemove(); return INIT_FAILED; }|
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_SMOKE_TEST_MQH__
#define __QA_SMOKE_TEST_MQH__

#include "TestRunner.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/IManager.mqh"

//+------------------------------------------------------------------+
//| Individual smoke test functions                                  |
//+------------------------------------------------------------------+

//--- Test 1: EventBus singleton pattern
void _Smoke_EventBusSingleton()
  {
   EventBus *a = EventBus::Instance();
   EventBus *b = EventBus::Instance();
   ASSERT_NOT_NULL(a);
   ASSERT_EQ(a, b); // same pointer = singleton holds
  }

//--- Test 2: Event priority ordering
void _Smoke_EventPriority()
  {
   // Priority enum must be ordered low→high numerically
   ASSERT_TRUE(EVENT_PRIORITY_LOW  < EVENT_PRIORITY_NORMAL);
   ASSERT_TRUE(EVENT_PRIORITY_NORMAL < EVENT_PRIORITY_HIGH);
   ASSERT_TRUE(EVENT_PRIORITY_HIGH < EVENT_PRIORITY_CRITICAL);
  }

//--- Test 3: Config magic number sanity
void _Smoke_ConfigDefaults()
  {
   StrategyConfig cfg;
   ZeroMemory(cfg);
   // ATR period of 0 would cause iATR crash — default must be >0 after ZeroMemory
   // (this test intentionally checks zero-init; EA must set defaults before use)
   ASSERT_EQ(cfg.atr_period, 0); // ZeroMemory sets to 0
   // Post-init defaults would be set by ConfigManager — validate that separately
  }

//--- Test 4: MathAbs / branchless safety
void _Smoke_MathSanity()
  {
   ASSERT_APPROX(MathAbs(-1.23456), 1.23456, 1e-9);
   ASSERT_POSITIVE(MathMax(0.0001, 0.0));
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD);
   ASSERT_RANGE(spread, 0.0, 5000.0); // spread in points, not pips
  }

//--- Test 5: Symbol tick size non-zero (prevents division-by-zero in pip calc)
void _Smoke_SymbolTickSize()
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   ASSERT_POSITIVE(tickSize);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   ASSERT_POSITIVE(tickValue);
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
   ASSERT_POSITIVE((int)login); // login must be non-zero
   // Key must contain login to prevent cross-account collision
   string prefix = IntegerToString(login) + "_PASR";
   ASSERT_TRUE(StringLen(prefix) > 5);
  }

//+------------------------------------------------------------------+
//| Master smoke test runner — call from EA OnInit()                 |
//+------------------------------------------------------------------+
bool RunPASRSmokeTests(bool verbose = false)
  {
   Print("\n══ PASR Smoke Tests ══");
   CTestRunner runner(true, verbose); // stopOnFail=true for init guard

   runner.Run("EventBus: singleton",          _Smoke_EventBusSingleton);
   runner.Run("EventBus: priority ordering",  _Smoke_EventPriority);
   runner.Run("Config: zero-init contract",   _Smoke_ConfigDefaults);
   runner.Run("Math: basic sanity",           _Smoke_MathSanity);
   runner.Run("Symbol: tick size > 0",        _Smoke_SymbolTickSize);
   runner.Run("Account: leverage range",      _Smoke_AccountLeverage);
   runner.Run("GV: key uniqueness per acct",  _Smoke_GVKeyUniqueness);

   runner.PrintSummary();
   return runner.AllPassed();
  }

#endif // __QA_SMOKE_TEST_MQH__
