//+------------------------------------------------------------------+
//| QA/RiskManagerTest.mqh                                           |
//| Unit tests for CRiskManager (Phase 4)                            |
//|                                                                  |
//| TEST COVERAGE:                                                   |
//|   T01  GetDrawdownPct()    — returns 0.0 on init                 |
//|   T02  GetDailyLossPct()   — returns 0.0 on init                 |
//|   T03  GetConsecLoss()     — returns 0 on init                   |
//|   T04  GetOpenTrades()     — returns 0 on init                   |
//|   T05  IsCircuitBroken()   — false on init                       |
//|   T06  CalcLot()           — returns > 0 for valid SL            |
//|   T07  CalcLot()           — returns <= MaxLot                   |
//|   T08  Check(0)            — allowed=true on clean slate         |
//|                                                                  |
//| HOW TO RUN:                                                      |
//|   #define PASR_QA_BUILD                                          |
//|   #include <PASR/Core/PASR.mqh>                                  |
//|   void OnStart() {                                               |
//|     CRiskManagerTest t;                                          |
//|     t.RunAll();                                                   |
//|   }                                                              |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_RISK_MANAGER_TEST_MQH__
#define __QA_RISK_MANAGER_TEST_MQH__

#include "Assertions.mqh"
#include "../Trade/RiskManager.mqh"

//+------------------------------------------------------------------+
//| CRiskManagerTest                                                 |
//+------------------------------------------------------------------+
class CRiskManagerTest
  {
private:
   CAssertions m_assert;

   // Helper: create a RiskManager with a minimal StrategyConfig
   // (no IManager Init call needed for state-read-only tests)
   CRiskManager *MakeRM()
     {
      return new CRiskManager();
     }

   void T01_DrawdownPctZeroOnInit()
     {
      CRiskManager *rm = MakeRM();
      m_assert.IsNear("T01_dd_zero_on_init",
                      0.0, rm.GetDrawdownPct(), 0.001);
      delete rm;
     }

   void T02_DailyLossPctZeroOnInit()
     {
      CRiskManager *rm = MakeRM();
      m_assert.IsNear("T02_daily_loss_zero_on_init",
                      0.0, rm.GetDailyLossPct(), 0.001);
      delete rm;
     }

   void T03_ConsecLossZeroOnInit()
     {
      CRiskManager *rm = MakeRM();
      m_assert.AreEqual("T03_consec_loss_zero_on_init",
                        0, rm.GetConsecLoss());
      delete rm;
     }

   void T04_OpenTradesZeroOnInit()
     {
      CRiskManager *rm = MakeRM();
      m_assert.AreEqual("T04_open_trades_zero",
                        0, rm.GetOpenTrades());
      delete rm;
     }

   void T05_CircuitNotBrokenOnInit()
     {
      CRiskManager *rm = MakeRM();
      m_assert.IsFalse("T05_circuit_not_broken_on_init",
                       rm.IsCircuitBroken());
      delete rm;
     }

   void T06_CalcLotPositiveForValidSL()
     {
      CRiskManager *rm = MakeRM();
      // Assume account equity > 0 and symbol lot step valid:
      // CalcLot should return > 0 for a reasonable SL distance
      double slPts = 200.0;  // 20 pip SL on 5-digit broker
      double lot   = rm.CalcLot(slPts);
      // We can only assert > 0 since we don’t know broker equity in test
      // so guard: if equity > 0, lot must be > 0
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > 100.0)
         m_assert.IsTrue("T06_lot_positive_valid_sl", lot > 0.0);
      else
         m_assert.Skip("T06_lot_positive_valid_sl", "equity<=100 in test env");
      delete rm;
     }

   void T07_CalcLotNotExceedMaxLot()
     {
      CRiskManager *rm = MakeRM();
      double slPts = 10.0;   // tiny SL → might compute large lot
      double lot   = rm.CalcLot(slPts);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      if(maxLot > 0.0)
         m_assert.IsTrue("T07_lot_lte_maxlot", lot <= maxLot);
      else
         m_assert.Skip("T07_lot_lte_maxlot", "maxLot not available in test env");
      delete rm;
     }

   void T08_CheckAllowedOnCleanSlate()
     {
      CRiskManager *rm = MakeRM();
      RiskCheckResult rr = rm.Check(0);
      // On a clean slate (no trades, no DD), pre-check should be allowed
      // Exception: if account has existing DD > threshold, test may skip.
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double dd      = (balance > 0) ? (balance - equity) / balance * 100.0 : 0.0;
      if(dd < 5.0)  // reasonable threshold
         m_assert.IsTrue("T08_check_allowed_clean", rr.allowed);
      else
         m_assert.Skip("T08_check_allowed_clean",
                       "live account already in DD, skipping");
      delete rm;
     }

public:
   void RunAll()
     {
      m_assert.BeginSuite("CRiskManager Phase 4");
      T01_DrawdownPctZeroOnInit();
      T02_DailyLossPctZeroOnInit();
      T03_ConsecLossZeroOnInit();
      T04_OpenTradesZeroOnInit();
      T05_CircuitNotBrokenOnInit();
      T06_CalcLotPositiveForValidSL();
      T07_CalcLotNotExceedMaxLot();
      T08_CheckAllowedOnCleanSlate();
      m_assert.EndSuite();
     }
  };

#endif // __QA_RISK_MANAGER_TEST_MQH__
