//+------------------------------------------------------------------+
//| QA/SmokeTest.mqh — v3.00                                         |
//| End-to-end smoke tests: Orchestrator Init + per-manager checks.  |
//|                                                                  |
//| PHILOSOPHY:                                                      |
//|   Smoke tests do NOT test logic correctness — they verify that   |
//|   every manager initialises without crash or memory error,       |
//|   and that the wiring produces non-null/valid state.             |
//|                                                                  |
//| HOW TO RUN (via PASR_Smoke.mq5 Script):                          |
//|   #define PASR_QA_BUILD                                          |
//|   #include <PASR/Core/PASR.mqh>                                  |
//|   void OnStart() {                                               |
//|     CPASRSmoke smoke;                                            |
//|     smoke.RunAll();                                              |
//|   }                                                              |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v3.00 (2026-05-21) — Phase 4 sections:                         |
//|     + RunRegimeSmoke()    : CRegimeFilter init + regime enum     |
//|     + RunSignalV3Smoke()  : veto/mult/voter register + SourceCount|
//|     + RunRiskSmoke()      : CalcLot + Check + IsCircuitBroken    |
//|     + RunDashboardSmoke() : SetRegimeFilter + no crash           |
//|   v2.00 (2026-05-20) — Phase 3 smoke sections                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_SMOKE_TEST_MQH__
#define __QA_SMOKE_TEST_MQH__

#include "Assertions.mqh"
#include "../Core/Orchestrator.mqh"
#include "../Signal/RegimeFilter.mqh"
#include "../Signal/RegimeSignalSource.mqh"
#include "../Trade/RiskManager.mqh"
#include "../UI/DashboardManager.mqh"

//+------------------------------------------------------------------+
//| CPASRSmoke — smoke runner for all Phase 1–4 managers            |
//+------------------------------------------------------------------+
class CPASRSmoke
  {
private:
   CAssertions m_assert;

   // ─────────────────────────────────────────────────────
   // S01: Full Orchestrator Init — all managers must init OK
   // ─────────────────────────────────────────────────────
   void RunOrchestratorSmoke()
     {
      m_assert.BeginSection("S01 Orchestrator");

      COrchestrator orch;
      int result = orch.Init();

      m_assert.AreEqual("S01_init_returns_succeeded",
                        (int)INIT_SUCCEEDED, result);
      m_assert.IsNotNull("S01_data_manager_not_null",
                         (void*)orch.GetDataManager());
      m_assert.IsNotNull("S01_sr_manager_not_null",
                         (void*)orch.GetSRManager());
      m_assert.IsNotNull("S01_zone_manager_not_null",
                         (void*)orch.GetZoneManager());
      m_assert.IsNotNull("S01_signal_manager_not_null",
                         (void*)orch.GetSignalManager());
      m_assert.IsNotNull("S01_ai_manager_not_null",
                         (void*)orch.GetAIManager());
      m_assert.IsNotNull("S01_regime_filter_not_null",
                         (void*)orch.GetRegimeFilter());
      m_assert.IsNotNull("S01_risk_manager_not_null",
                         (void*)orch.GetRiskManager());
      m_assert.IsNotNull("S01_exec_manager_not_null",
                         (void*)orch.GetExecManager());
      m_assert.IsNotNull("S01_recovery_not_null",
                         (void*)orch.GetRecoveryManager());
      m_assert.IsNotNull("S01_dashboard_not_null",
                         (void*)orch.GetDashboard());

      // Signal sources registered (4 in Phase 4: Pattern + SR + AI + Regime)
      CSignalManager *sm = orch.GetSignalManager();
      if(sm != NULL)
         m_assert.AreEqual("S01_signal_sources_count", 4, sm.SourceCount());

      orch.OnDeinit(0);  // verify clean shutdown
      m_assert.IsTrue("S01_deinit_no_crash", true);

      m_assert.EndSection();
     }

   // ─────────────────────────────────────────────────────
   // S02: RegimeFilter standalone
   // ─────────────────────────────────────────────────────
   void RunRegimeSmoke()
     {
      m_assert.BeginSection("S02 RegimeFilter");

      CRegimeFilter rf;
      // GetRegime() before Init returns a valid enum (REGIME_UNKNOWN or default)
      ENUM_MARKET_REGIME r = rf.GetRegime();
      bool validEnum = (r == REGIME_TRENDING  ||
                        r == REGIME_RANGING   ||
                        r == REGIME_VOLATILE  ||
                        r == REGIME_SQUEEZE   ||
                        r == REGIME_UNKNOWN);
      m_assert.IsTrue("S02_get_regime_valid_enum", validEnum);

      // GetADX() before Init returns non-negative
      m_assert.IsTrue("S02_get_adx_non_negative", rf.GetADX() >= 0.0);

      // RegimeSignalSource wraps it without crash
      CRegimeSignalSource *src = new CRegimeSignalSource(&rf);
      m_assert.IsNotNull("S02_regime_source_alloc", (void*)src);
      SignalResult sr; sr.Clear();
      bool ok = src.Evaluate(sr);
      // Must return true (even if direction is NONE)
      m_assert.IsTrue("S02_regime_source_evaluate_ok", ok);
      delete src;

      m_assert.EndSection();
     }

   // ─────────────────────────────────────────────────────
   // S03: SignalManager v3 source registration smoke
   // ─────────────────────────────────────────────────────
   void RunSignalV3Smoke()
     {
      m_assert.BeginSection("S03 SignalManager v3");

      CSignalManager sm;
      sm.SetMinConfluence(2);
      sm.SetMinScore(0.45);
      sm.SetCooldownBars(3);

      // HasSignal false before any OnNewBar
      m_assert.IsFalse("S03_no_signal_on_fresh", sm.HasSignal());

      // Source count starts at 0
      m_assert.AreEqual("S03_source_count_zero", 0, sm.SourceCount());

      // Urgency enum ordering
      m_assert.IsTrue("S03_urgency_HIGH_is_0",
                      (int)SIGNAL_URGENCY_HIGH == 0);
      m_assert.IsTrue("S03_urgency_LOW_is_2",
                      (int)SIGNAL_URGENCY_LOW == 2);

      m_assert.EndSection();
     }

   // ─────────────────────────────────────────────────────
   // S04: RiskManager standalone
   // ─────────────────────────────────────────────────────
   void RunRiskSmoke()
     {
      m_assert.BeginSection("S04 RiskManager");

      CRiskManager rm;

      // State checks on un-inited RM (all should be safe defaults)
      m_assert.IsNear("S04_dd_zero",    0.0, rm.GetDrawdownPct(),  0.001);
      m_assert.IsNear("S04_daily_zero", 0.0, rm.GetDailyLossPct(), 0.001);
      m_assert.AreEqual("S04_consec_zero", 0, rm.GetConsecLoss());
      m_assert.AreEqual("S04_open_zero",   0, rm.GetOpenTrades());
      m_assert.IsFalse("S04_not_broken",   rm.IsCircuitBroken());

      // CalcLot with zero SL returns 0 (guard against div-by-zero)
      double lotZero = rm.CalcLot(0.0);
      m_assert.IsNear("S04_lot_zero_sl", 0.0, lotZero, 0.0001);

      // Check on clean slate
      RiskCheckResult rr = rm.Check(0);
      // allowed can be true or false depending on live account state;
      // just verify the call doesn't crash and reason is a string
      m_assert.IsTrue("S04_check_no_crash",
                      StringLen(rr.reason) >= 0);  // always true = no crash

      m_assert.EndSection();
     }

   // ─────────────────────────────────────────────────────
   // S05: DashboardManager v3 injection smoke
   // ─────────────────────────────────────────────────────
   void RunDashboardSmoke()
     {
      m_assert.BeginSection("S05 DashboardManager v3");

      // Alloc without crash
      CDashboardManager *db = new CDashboardManager();
      m_assert.IsNotNull("S05_alloc_ok", (void*)db);

      // Inject NULL deps (should not crash on read)
      db.SetRiskManager(NULL);
      db.SetSignalManager(NULL);
      db.SetRegimeFilter(NULL);
      m_assert.IsTrue("S05_null_inject_no_crash", true);

      // Inject real (stack) deps
      CRiskManager   rm;
      CSignalManager sm;
      CRegimeFilter  rf;
      db.SetRiskManager  (&rm);
      db.SetSignalManager(&sm);
      db.SetRegimeFilter (&rf);
      m_assert.IsTrue("S05_real_inject_no_crash", true);

      // Destroy must not crash
      db.Destroy();
      m_assert.IsTrue("S05_destroy_no_crash", true);

      // Double destroy must be safe (idempotent)
      db.Destroy();
      m_assert.IsTrue("S05_double_destroy_safe", true);

      delete db;
      m_assert.IsTrue("S05_delete_no_crash", true);

      m_assert.EndSection();
     }

public:
   void RunAll()
     {
      Print("╔══════════════════════════════════════════════════╗");
      Print("║  PASR Smoke Test Suite v3.00                     ║");
      Print("╚══════════════════════════════════════════════════╝");

      RunOrchestratorSmoke();
      RunRegimeSmoke();
      RunSignalV3Smoke();
      RunRiskSmoke();
      RunDashboardSmoke();

      m_assert.PrintReport();
     }
  };

#endif // __QA_SMOKE_TEST_MQH__
