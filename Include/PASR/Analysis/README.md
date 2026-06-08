# Analysis Module — PASR Pipeline Architecture

> **Last updated:** Sprint 9 (2026-05-23)  
> **Status:** ✅ Active — IManager compliant  
> **Pending:** SRManager.mqh decomposition (Sprint 10+)

---

## Folder Structure

```
Include/PASR/Analysis/
├── SRManager.mqh                ← Support/Resistance detection (CAnalysisSRManager)
├── ZoneManager.mqh              ← Supply/Demand zone engine (CAnalysisZoneManager)
├── MarketRegimeDetector.mqh     ← Market regime classification (CMarketRegimeDetector)
├── AdaptiveParameterManager.mqh ← Dynamic SL/TP adaptation (CAdaptiveParameterManager)
└── Pattern/                     ← Candlestick pattern recognition sub-module
```

### Removed in Sprint 9
| Path | Reason |
|------|--------|
| `Optimized/` (entire folder) | Dead experiment branch — 6 files (SRUnifiedManager, SRBatchScanner, SRMemoryPool, SRZoneCache, AnalysisOptimized, PerformanceUtils) never wired to pipeline or PASR.mqh |
| `OPTIMIZATION_SUMMARY.md` | Dev artifact, not official documentation |

---

## Manager Contracts

All managers in this folder extend `IManager` (Core/IManager.mqh v2.15):

```cpp
class CXxxManager : public IManager
{
   bool Init(IDataManager *data, CEventBus *bus) override;
   void DeclareEvents() override;   // AddEvent() calls here
   void OnEvent(const PASREvent &ev) override;
   void OnNewBar() override;
};
```

---

## Pipeline Integration

| Manager | Pipeline Stage | Called By |
|---------|---------------|-----------|
| `CAnalysisSRManager` | Stage 2 — AnalysisSR | `PipelineEngine::Stage_AnalysisSR()` |
| `CAnalysisZoneManager` | Stage 3 — AnalysisZone | `PipelineEngine::Stage_AnalysisZone()` |
| `CMarketRegimeDetector` | Stage 9 — AdaptiveParams | `Orchestrator::Init()` Phase 5 |
| `CAdaptiveParameterManager` | Stage 9 — AdaptiveParams | `PipelineEngine::Stage_AdaptiveParams()` |

---

## Known Issues & Backlog

### 🔴 OPEN — Sprint 10 Target
| ID | Issue | File | Impact |
|----|-------|------|--------|
| A1 | `SRManager.mqh` is 54KB (~1500 lines) — needs decomposition into `SRDetector.mqh` + `SRZoneStore.mqh` + `SRScorer.mqh` | `SRManager.mqh` | Maintainability, compile time |
| A5 | `Pattern/` folder contents not yet audited for IManager compliance | `Pattern/*.mqh` | Unknown, may have monolith remnants |

### ✅ RESOLVED
| ID | Fix | Sprint |
|----|-----|--------|
| A2 | Deleted `Optimized/` — orphan parallel development branch | Sprint 9 |
| A3 | Deleted `OPTIMIZATION_SUMMARY.md` — dev artifact | Sprint 9 |
| A4 | `AdaptiveParameterManager.mqh` placement noted (logically belongs in Strategy/, stays here to avoid path churn) | Sprint 9 |
