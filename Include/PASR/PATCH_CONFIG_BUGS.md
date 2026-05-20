# Config.mqh Patch Notes — Audit 2026-05-20

## BUG-04 🟠 CRITICAL FIX — ArrayResize OOB in ValidationResult::AddIssue

### Problem
`ArrayResize()` returns the **new array size**, not the index of the new element.
Original code used the return value as index → out-of-bounds write → crash/corruption.

### Location
`ValidationResult::AddIssue()` in `2.Config.mqh`

### Diff
```diff
- int idx = ArrayResize(issues, ArraySize(issues) + 1);
- issues[idx] = ValidationIssue(...);
+ ArrayResize(issues, ArraySize(issues) + 1);
+ int idx = ArraySize(issues) - 1;
+ issues[idx] = ValidationIssue(...);
```

---

## BUG-02 🔴 CRITICAL FIX — partialTP calculation wrong scale

### Problem
`iATR()` returns values in **price units** (e.g. 0.00120 for EURUSD).
Multiplying by `_Point` again makes `pcDist` ~10,000x too small.
Result: partialTP nearly equals entryPrice → partial close triggers immediately after open.

### Location
`RecoveryEngine::LoadState()` in `2.Config.mqh`

### Diff
```diff
- double pcDist = lastKnownATR * CFG.exit.partialATR * _Point;
+ double pcDist = lastKnownATR * CFG.exit.partialATR;
```

---

## BUG-03 🔴 FIX — Reload() operator precedence bug + m_firstLoad flag

### Problem
Condition `!m_lastKnownConfig.market.atrPeriod > 0` parses as
`!(atrPeriod > 0)` — after first init, atrPeriod is never 0, so
context-aware validation **never runs again** after first reload.

### Required Change in 2.Config.mqh
1. Add `bool m_firstLoad;` to `ConfigManager` private members
2. Init `m_firstLoad = true` in constructor
3. Replace condition:

```diff
- if(symbolChanged || !m_lastKnownConfig.market.atrPeriod > 0)
+ if(symbolChanged || m_firstLoad)
```

4. Replace snapshot logic at end of Reload():
```diff
- if(m_lastKnownConfig.market.atrPeriod == 0)
- {
-    m_lastKnownConfig = m_config;
- }
+ if(m_firstLoad || symbolChanged)
+ {
+    m_lastKnownConfig = m_config;
+    m_firstLoad = false;
+ }
```

---

## BUG-06 🟠 FIX — Missing input declarations (COMPILE ERROR)

### Problem
`LoadRecoveryParams()` references 4 inputs that are never declared in the `input` block.
This causes **compile error**.

### Fix — Add to `[GROUP] RECOVERY MODE` input block:
```cpp
input int    InpMaxRecoveryPositions;      // Max Recovery Positions per initial trade
input double InpMaxRecoveryExposureMult;   // Max Exposure Multiplier (Recovery)
input int    InpRecoveryTimeoutBars;       // Timeout bars untuk recovery mode  
input double InpRecoveryHardStopPct;       // Hard Stop Loss % saat recovery (0=disabled)
```

---

## BUG-08 🟡 FIX — Double validation in LoadXParams()

### Problem
Each `LoadXParams()` calls `m_config.x.Validate()`, then `ConfigManager::Reload()`
calls `m_config.Validate()` which calls **all** `x.Validate()` again.
Double normalization = duplicate Print() warnings, confusing logs.

### Fix
Remove the `m_config.x.Validate()` call from the end of each `LoadXParams()` function.
Leave validation only in the master `Validate()` chain.

---

## BUG-09 🟡 FIX — news.use implicit assignment hidden side effect

### Problem
`news.use` is silently derived inside `News::Validate()`. If someone reads
the code or sets `news.use` before Validate() runs, it gets overwritten silently.

### Fix in LoadNewsParams():
```diff
+ m_config.news.use = (InpNewsLevel != NEWS_OFF); // Explicit — don't rely on Validate() side effect
```

---

## BUG-07 🟡 NOTE — ArrayInt type

If `ArrayInt` is not defined in `0.EventBus.mqh` or `IManager.mqh`,
`StrategyConfig::Compare()` and `ConfigManager::GetChanges()` will cause compile error.

Alternative signature using plain MQL5 arrays:
```cpp
void Compare(const StrategyConfig &other, int &changed[]) const
{
   ArrayResize(changed, 0);
   // ... append with:
   // int sz = ArraySize(changed); ArrayResize(changed, sz+1); changed[sz] = FIELD_XXX;
}
```

---

## BUG-01 🔴 NOTE — iATR Handle Leak

`InstrumentContext::CalculateATR14()` and `StrategyConfig::GetATRValue()`
create a new `iATR()` handle on **every call**. If `CopyBuffer()` fails,
`IndicatorRelease()` is not called → handle leak.

Recommended fix: cache the handle as a member of `InstrumentContext`,
release in destructor, and expose a `ReadATR()` method instead.
`StrategyConfig::GetATRValue()` should be removed — pass `ctx.atr14` directly.
