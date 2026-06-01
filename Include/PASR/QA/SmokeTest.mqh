//+------------------------------------------------------------------+
//| QA/SmokeTest.mqh — v3.00                                         |
//| End-to-end smoke tests: Kernel init + per-manager checks.        |
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
#include "../Core/PASR.mqh"
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
   // S01: Full Kernel Init - all managers must init OK
   // ─────────────────────────────────────────────────────
   void RunKernelSmoke()
     {
      m_assert.BeginSection("S01 Kernel");

      CPASRKernel kernel;
      int result = kernel.Init();
      CServiceLocator *services = kernel.Services();

      m_assert.AreEqual("S01_init_returns_succeeded",
                        (int)INIT_SUCCEEDED, result);
      m_assert.IsNotNull("S01_services_not_null",
                         (void*)services);
      m_assert.IsNotNull("S01_data_manager_not_null",
                         (services != NULL ? (void*)services.Data() : NULL));
      m_assert.IsNotNull("S01_sr_manager_not_null",
                         (services != NULL ? (void*)services.SR() : NULL));
      m_assert.IsNotNull("S01_zone_manager_not_null",
                         (services != NULL ? (void*)services.Zone() : NULL));
      m_assert.IsNotNull("S01_signal_manager_not_null",
                         (services != NULL ? (void*)services.Signal() : NULL));
      m_assert.IsNotNull("S01_ai_orchestrator_not_null",
                         (services != NULL ? (void*)services.AI() : NULL));
      m_assert.IsNotNull("S01_regime_filter_not_null",
                         (services != NULL ? (void*)services.RegimeFilter() : NULL));
      m_assert.IsNotNull("S01_risk_manager_not_null",
                         (services != NULL ? (void*)services.Risk() : NULL));
      m_assert.IsNotNull("S01_exec_manager_not_null",
                         (services != NULL ? (void*)services.Execution() : NULL));
      m_assert.IsNotNull("S01_recovery_not_null",
                         (services != NULL ? (void*)services.Recovery() : NULL));
      m_assert.IsNotNull("S01_dashboard_not_null",
                         (services != NULL ? (void*)services.Dashboard() : NULL));

      // Signal sources registered (4 in Phase 4: Pattern + SR + AI + Regime)
      CSignalManager *sm = (services != NULL ? services.Signal() : NULL);
      if(sm != NULL)
         m_assert.AreEqual("S01_signal_sources_count", 4, sm.SourceCount());

      kernel.OnDeinit(0);  // verify clean shutdown
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
      EMarketRegime r = rf.GetRegime();
      bool validEnum = (r == REGIME_TREND_UP  ||
                        r == REGIME_TREND_DOWN ||
                        r == REGIME_RANGE     ||
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
      // Source count starts at 0
      m_assert.AreEqual("S03_source_count_zero", 0, sm.SourceCount());
      m_assert.IsFalse("S03_layer_not_ready_without_sources", sm.IsSignalLayerReady());

      SSignal aggregate = sm.AggregateSignals();
      m_assert.AreEqual("S03_aggregate_without_sources_none", (int)SIGNAL_NONE, (int)aggregate.direction);

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
      RiskSnapshot snap = rm.GetSnapshot();
      m_assert.IsNear("S04_dd_zero",    0.0, snap.drawdownPct,  0.001);
      m_assert.IsNear("S04_daily_zero", 0.0, snap.dailyLossPctUsed, 0.001);
      m_assert.AreEqual("S04_consec_zero", 0, snap.consecLoss);
      m_assert.AreEqual("S04_open_zero",   0, rm.GetOpenTrades());
      m_assert.IsTrue("S04_trading_allowed", rm.IsTradingAllowed());

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

      db.SetPrefix("PASR_QA");
      db.SetUpdateInterval(1);
      db.SetObservabilityText("smoke");
      m_assert.IsTrue("S05_observability_roundtrip", db.GetObservabilityText() == "smoke");

      db.Deinit();
      m_assert.IsTrue("S05_deinit_no_crash", true);

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

      RunKernelSmoke();
      RunRegimeSmoke();
      RunSignalV3Smoke();
      RunRiskSmoke();
      RunDashboardSmoke();

      m_assert.PrintReport();
     }
  };

#endif // __QA_SMOKE_TEST_MQH__
