# Sprint 9 — PatternManager Fixes

## Status: ✅ COMMITTED

## Bugs Fixed

### BUG-017: StorePatternHistory() was a no-op
- **Root cause:** `CArrayObj` requires `CObject`-derived items. `SPatternResult` is a plain struct — cannot be `Add()`-ed directly. Body was empty because previous dev left a comment "requires CObject wrapper".
- **Fix:** Added `CPatternRecord : public CObject` wrapper class with `SPatternResult data` field. `StorePatternHistory()` now allocates `new CPatternRecord(result)` and calls `m_patternHistory.Add(rec)`. FIFO cap: 200 entries.

### BUG-018: Adapter overload REGIME_SIDEWAYS cast clarity
- **Root cause:** `EMarketRegime` cast from enum constant was implicit and could cause compiler warning in strict mode.
- **Fix:** Explicit cast `(EMarketRegime)REGIME_SIDEWAYS` with comment. Safe — MQL5 enums are int-backed.

### BUG-019: No external accessor for history
- **Root cause:** PipelineEngine Stage scoring has no way to read recent confirmed patterns.
- **Fix:** Added `GetHistoryCount()` and `GetHistoryAt(idx, out)` public accessors. PipelineEngine can now check last N patterns for regime confirmation.

## Version Bump
PatternManager.mqh: v2.02 → **v2.03**
