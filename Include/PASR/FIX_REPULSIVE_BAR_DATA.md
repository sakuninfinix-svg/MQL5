# FIX: Repulsive Bar Data Issue - Using Closed Bars Only

## Problem Statement

**Issue**: In `OnTick()`, when `NewBarEvent` is dispatched, the code uses `rates[0]` (the bar that just opened, not yet closed). Every signal/pattern/SR calculated from `rates[0]` will change as the bar forms, leading to:
- **Repainting signals**: Signals appear/disappear as the bar develops
- **False patterns**: Pattern detection on incomplete data
- **Unreliable S&R levels**: Support/Resistance calculated from unconfirmed price action
- **Whipsaw entries**: Entries based on formations that reverse before bar close

## Root Cause Analysis

### Current Implementation (WRONG)
```mql5
// In PASR_MODULAR.mq5 OnTick()
if(CopyRates(eaCfg.symbolName, eaCfg.timeframe, 0, 1, rates) > 0)
{
   DispatchEvent(new NewBarEvent(
       currentBar,
       rates[0].open,    // ← UNCLOSED BAR! Changes every tick
       rates[0].high,    // ← Can still expand
       rates[0].low,     // ← Can still expand
       rates[0].close,   // ← Current price, not final close
       eaCfg.timeframe));
}
```

### Why This Is Wrong
1. **`rates[0]` = Currently forming bar**: Opened at `currentBar` time but not closed yet
2. **Price keeps changing**: High/Low/Close update with every tick
3. **Pattern detection fails**: A hammer pattern at shift 0 might become a marubozu in 5 seconds
4. **Signal repainting**: Signal appears at 90% of bar life, disappears at close

## Solution: Use Only Closed Bars

### Principle
**Only use `rates[1]` and beyond for signal generation, SR detection, and price action patterns.**

- `rates[0]` = Currently forming bar (UNCLOSED) ❌
- `rates[1]` = Last completed bar (CLOSED) ✅
- `rates[2]` = Previous bar (CLOSED) ✅

### Implementation Changes Required

#### 1. Modify NewBarEvent Dispatch (PASR_MODULAR.mq5)

**Change**: Dispatch `NewBarEvent` AFTER bar closes, using `rates[1]` (the bar that just closed).

```mql5
// NEW: Check if bar just closed by comparing previous bar time
static datetime g_lastClosedBarTime = 0;

datetime times[];
if(CopyTime(eaCfg.symbolName, eaCfg.timeframe, 0, 2, times) <= 0)
   return;

datetime currentFormingBar = times[0];      // Still forming
datetime lastClosedBar = times[1];          // Just closed

// Fire event only when a NEW bar has closed
if(lastClosedBar != g_lastClosedBarTime)
{
   g_lastClosedBarTime = lastClosedBar;
   market.SetLastBarTime(lastClosedBar);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Copy 2 bars: [0]=forming, [1]=closed
   if(CopyRates(eaCfg.symbolName, eaCfg.timeframe, 0, 2, rates) > 1)
   {
      // Use rates[1] - the CLOSED bar
      DispatchEvent(new NewBarEvent(
          lastClosedBar,           // Time of closed bar
          rates[1].open,           // Final OHLC of closed bar
          rates[1].high,
          rates[1].low,
          rates[1].close,
          eaCfg.timeframe));
   }
}
```

#### 2. Update All Signal/Pattern Detection to Use Shift >= 1

In `5.SignalManager.mqh`, `DetectSignalCore()`:

```mql5
// OLD: Loop starts from shift 0 (unclosed bar)
for (int shift = 0; shift < cfg.pattern_lookback; shift++)

// NEW: Start from shift 1 (first closed bar)
for (int shift = 1; shift < cfg.pattern_lookback + 1; shift++)
```

#### 3. Add Data Validation (Outlier & Stale Data Detection)

```mql5
// Add to DataManager or SignalManager
bool ValidateCandleData(const MqlRates &rates[], int shift)
{
   if(shift >= ArraySize(rates)) return false;
   
   double currentRange = rates[shift].high - rates[shift].low;
   double prevRange = rates[shift + 1].high - rates[shift + 1].low;
   
   // Outlier detection: Range > 5x previous candle
   if(currentRange > (prevRange * 5.0))
   {
      DebugLog("Outlier candle detected at shift " + IntegerToString(shift));
      return false;
   }
   
   // Stale data: Zero range or invalid OHLC
   if(currentRange <= 0 || 
      rates[shift].high < rates[shift].low ||
      rates[shift].open <= 0 || rates[shift].close <= 0)
   {
      DebugLog("Stale/invalid data at shift " + IntegerToString(shift));
      return false;
   }
   
   // Gap detection: Large gap from previous close
   double gap = MathAbs(rates[shift].open - rates[shift + 1].close);
   if(gap > (prevRange * 2.0))
   {
      DebugLog("Large gap detected at shift " + IntegerToString(shift));
      // Don't reject, just log (gaps are valid but risky)
   }
   
   return true;
}
```

#### 4. Update Replay Function (1.Events.mqh)

```mql5
// In ReplayRecordedEvents()
case EVENT_ID_NEW_BAR:
   {
      MqlRates rates[];
      // Copy 2 bars to get closed bar at index 1
      if(CopyRates(_Symbol, _Period, 0, 2, rates) > 1)
      {
         e = new NewBarEvent(rates[1].time, rates[1].open, rates[1].high,
                             rates[1].low, rates[1].close, _Period);
      }
   }
   break;
```

## Files to Modify

1. **Experts/PASR_MODULAR.mq5**
   - Modify `OnTick()` to dispatch `NewBarEvent` with closed bar data
   
2. **Include/PASR/5.SignalManager.mqh**
   - Update `DetectSignalCore()` to start loop from shift 1
   - Add `ValidateCandleData()` call before pattern detection
   
3. **Include/PASR/1.Events.mqh**
   - Fix `ReplayRecordedEvents()` to use `rates[1]`
   
4. **Include/PASR/4.SRManager.mqh**
   - Ensure S&R calculation uses only closed bars (shift >= 1)
   
5. **Include/PASR/9.PatternManager.mqh**
   - Add validation for outlier/stale data

6. **Include/PASR/10.DataManager.mqh**
   - Add global `ValidateCandleData()` utility function

## Benefits

✅ **No more repainting**: Signals are generated from confirmed, closed bars
✅ **Reliable patterns**: Pattern recognition works on complete candle formations
✅ **Accurate S&R**: Support/Resistance based on actual price reactions
✅ **Better backtesting**: Historical performance matches live results
✅ **Reduced false signals**: Eliminates whipsaws from incomplete bar formations

## Testing Checklist

- [ ] Verify `NewBarEvent` fires only after bar closes
- [ ] Confirm all pattern detection uses shift >= 1
- [ ] Test outlier detection with spike candles
- [ ] Validate backtest results match forward test
- [ ] Check no signals appear on forming bars
- [ ] Verify S&R levels don't repaint

## Migration Notes

**Backward Compatibility**: This change affects signal timing slightly:
- Signals will fire at the **open of the next bar** instead of during formation
- This is CORRECT behavior for production trading
- Backtests should be re-run with the new logic

**Performance Impact**: Minimal - same number of API calls, just different index

---

**Version**: 1.31
**Date**: 2026
**Status**: Ready for Implementation
