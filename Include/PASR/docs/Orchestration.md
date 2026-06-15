# Orchestration Module (`PASR/Orchestration/`)

19 files — Pipeline engine, stage registry, and 14 concrete pipeline stages.

## Arsitektur

```
Orchestration/
  ├── PipelineStage.mqh           — IPipelineStage interface
  ├── PipelineStageRegistry.mqh   — Stage registry (32 slots)
  ├── PipelineEngine.mqh          — Main pipeline orchestrator
  ├── AdaptivePipelineEngine.mqh  — Regime-adaptive wrapper
  └── Stages/
        ├── PipelineStageBase.mqh     — Base class
        ├── DataSyncStage.mqh         — Stage 1: Data validation
        ├── AnalysisSRStage.mqh       — Stage 2: S/R analysis
        ├── AnalysisZoneStage.mqh     — Stage 3: Zone analysis
        ├── PatternStage.mqh          — Stage 4: Pattern recognition
        ├── RegimeStage.mqh           — Stage 5: Regime detection
        ├── SignalStage.mqh           — Stage 6: Signal generation
        ├── AIInferStage.mqh          — Stage 7: AI inference
        ├── RiskStage.mqh             — Stage 8: Risk check
        ├── AdaptiveParamsStage.mqh   — Stage 9: Adaptive params
        ├── ExecutionStage.mqh        — Stage 10: Trade execution
        ├── PositionStage.mqh         — Stage 11: Position mgmt
        ├── RecoveryStage.mqh         — Stage 12: Recovery
        ├── DashboardStage.mqh        — Stage 13: Dashboard UI
        └── JournalStage.mqh          — Stage 14: Journal logging
```

## Pipeline Flow (14 Stages)

```
 1. DataSyncStage     — Validasi DataManager siap
 2. AnalysisSRStage   — Support/Resistance scan
 3. AnalysisZoneStage — Supply/Demand zone update
 4. PatternStage      — Candlestick pattern detection
 5. RegimeStage       — Market regime detection
 6. SignalStage       — Aggregasi signal dari semua sumber
 7. AIInferStage      — AI inference + confidence gate
 8. RiskStage         — Risk check + position sizing
 9. AdaptiveParamsStage — Dynamic SL/TP/lot adjustment
10. ExecutionStage    — Order execution
11. PositionStage     — Position management + exit check
12. RecoveryStage     — Loss recovery management
13. DashboardStage    — UI dashboard update
14. JournalStage      — Trade journal logging
```

## File Reference

| # | File | Class | Fungsi |
|---|------|-------|--------|
| 1 | `PipelineStage.mqh` | `IPipelineStage` | Abstract: `Name()`, `Execute(PipelineContext&)`, `IsEnabled()`, `SetEnabled()`, `IsReady()`, `LastElapsedUs()` |
| 2 | `PipelineStageRegistry.mqh` | `CPipelineStageRegistry` | Register 14 stages, enable/disable, record results, print summary |
| 3 | `PipelineEngine.mqh` | `CPipelineEngine` | `InjectDependencies()`, `ExecutePipeline()`, `RunStage()`, `PublishObservability()` |
| 4 | `AdaptivePipelineEngine.mqh` | `CAdaptivePipelineEngine` | Regime-adaptive: adjust thresholds/weights/stages per regime |
| 5 | `Stages/PipelineStageBase.mqh` | `CPipelineStageBase` | Reusable base with `Skip()`, `Abort()` helpers |
| 6-19 | `Stages/*Stage.mqh` | Per-stage classes | See table above |

## Stage Implementation Pattern

```cpp
class CDataSyncStage : public CPipelineStageBase {
public:
    void Bind(IDataManager* dm) { m_data = dm; }
    string Name() { return "DataSync"; }
    bool Execute(PipelineContext &ctx) {
        if (!m_data.IsInitialized())
            return Abort(ctx, "DataManager not ready");
        return true;
    }
};
```

## PipelineEngine.ExecutePipeline()

```cpp
bool ExecutePipeline(PipelineContext &ctx) {
    // Health gate
    if (!m_health.IsHealthy()) { ... return false; }
    // Drawdown gate
    if (m_risk.GetDrawdown() > max_dd) { ... return false; }

    for (int i = 0; i < m_registry.Count(); i++) {
        if (m_profiling) m_profiler.Start();
        bool ok = RunStage(i, ctx);
        if (m_profiling) { m_profiler.Stop(); }

        if (!ok && m_stop_on_fail) break;
    }
    return true;
}
```
