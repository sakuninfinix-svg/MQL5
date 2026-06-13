#!/usr/bin/env python3
"""
Quick PF Analysis: SL/TP Sweep + Regime Breakdown (Optimized)
Uses smaller dataset and fewer combos for speed
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta

from comprehensive_backtest import (
    AdvancedMarketGenerator, OptimizedBacktest, TechnicalIndicators, OPTIMIZED_CONFIG
)

print("=" * 60)
print("PF ANALYSIS: SL/TP SWEEP + REGIME BREAKDOWN (FAST)")
print("=" * 60)

# Generate smaller dataset for speed
gen = AdvancedMarketGenerator(seed=42)
df = gen.generate_realistic_series(15000)  # Smaller = faster

# Precompute indicators once
c = df['close'].to_numpy()
h = df['high'].to_numpy()
l = df['low'].to_numpy()
v = df['volume'].to_numpy()

# Precompute all indicators
atr14 = TechnicalIndicators.atr(h, l, c, 14)
rsi14 = TechnicalIndicators.rsi(c, 14)
adx14 = TechnicalIndicators.adx(h, l, c, 14)
stoch = TechnicalIndicators.stoch(h, l, c)
sr_res, sr_sup, sr_zone, sr_pat = TechnicalIndicators.detect_sr(h, l, c, 39)

print("\n[1/2] SL/TP SWEEP (Key combos only)")
print("-" * 50)
print(f"{'SL':>4} {'TP':>4} {'Trd':>5} {'WR':>6} {'PF':>6} {'AvgR':>6} {'DD%':>5}")
print("-" * 50)

# Key combos to test
combos = [
    (1.5, 1.5), (1.5, 2.0), (1.5, 2.5),
    (1.75, 1.75), (1.75, 2.0), (1.75, 2.5), (1.75, 3.0),
    (2.0, 2.0), (2.0, 2.5), (2.0, 3.0),
    (2.17, 1.75), (2.17, 2.0), (2.17, 2.5),  # Current
    (2.5, 2.0), (2.5, 2.5), (2.5, 3.0),
]

best_pf = 0
best_combo = None

for sl, tp in combos:
    # Quick simulation with precomputed indicators
    trades = 0
    wins = 0
    total_r = 0.0
    wins_r = 0.0
    losses_r = 0.0
    equity = 10000.0
    peak = 10000.0
    max_dd = 0.0
    daily_pnl = 0.0
    positions = 0
    daily_pnl = 0.0
    
    last_date = None
    
    for i in range(39, len(c) - 50):
        # Daily reset
        cur_date = df['timestamp'].iloc[i].date()
        if last_date and cur_date != last_date:
            daily_pnl = 0
            positions = 0
        last_date = cur_date
        
        # Risk limits
        if daily_pnl < -300: continue  # 3% of 10k
        if max_dd > 0.10: continue
        if positions >= 3: continue
        
        # Entry signal (simplified from OptimizedBacktest)
        hour = df['timestamp'].iloc[i].hour
        if not (0 <= hour <= 23): continue
        if adx14[i] < 26.5: continue
        if sr_pat[i] < 42.5: continue
        if (h[i] - l[i]) * 0.1 > 0.0003: continue  # 3 pips spread
        
        pos = (c[i] - l[max(0,i-39):i].min()) / (h[max(0,i-39):i].max() - l[max(0,i-39):i].min() + 1e-10)
        regime = df['regime'].iloc[i]
        
        signal = 0
        if regime in ["TREND_UP", "RECOVERY"]:
            if sr_sup[i] < 0.25 and sr_zone[i] > 0.4 and pos < 0.4 and rsi14[i] < 70:
                signal = 1
        elif regime in ["TREND_DOWN"]:
            if sr_res[i] < 0.25 and sr_zone[i] > 0.4 and pos > 0.6 and rsi14[i] > 30:
                signal = -1
        elif regime in ["RANGE", "CHOPPY"]:
            if sr_zone[i] > 0.5:
                if sr_sup[i] < 0.2 and rsi14[i] < 65: signal = 1
                if sr_res[i] < 0.2 and rsi14[i] > 35: signal = -1
        elif regime in ["VOLATILE", "CRASH"]:
            if pos > 0.7 and sr_res[i] > 0.3 and rsi14[i] > 50: signal = 1
            if pos < 0.3 and sr_sup[i] > 0.3 and rsi14[i] < 50: signal = -1
        
        if signal != 0:
            entry = c[i]
            atr = max(atr14[i], 0.0001)
            if signal == 1:
                sl_p = entry - atr * sl
                tp_p = entry + atr * tp
            else:
                sl_p = entry + atr * sl
                tp_p = entry - atr * tp
            
            # Quick exit sim (max 50 bars)
            hit_sl = hit_tp = False
            exit_p = entry
            for k in range(1, 50):
                if i + k >= len(c): break
                hi, lo = h[i+k], l[i+k]
                if signal == 1:
                    if lo <= sl_p: hit_sl = True; exit_p = sl_p; break
                    if hi >= tp_p: hit_tp = True; exit_p = tp_p; break
                else:
                    if hi >= sl_p: hit_sl = True; exit_p = sl_p; break
                    if lo <= tp_p: hit_tp = True; exit_p = tp_p; break
            
            if not hit_tp and not hit_sl:
                exit_p = c[min(i+50, len(c)-1)]
            
            pips = (exit_p - entry) * 10000 if signal == 1 else (entry - exit_p) * 10000
            sl_pips = abs(entry - sl_p) * 10000
            r_mult = pips / sl_pips if sl_pips > 0 else 0
            
            trades += 1
            total_r += r_mult
            if r_mult > 0:
                wins += 1
                wins_r += r_mult
            else:
                losses_r += abs(r_mult)
            
            positions += 1
            daily_pnl += r_mult * 1.95 * 100  # approx dollars
            equity += r_mult * 1.95 * 100
            
            if equity > peak: peak = equity
            dd = (peak - equity) / peak
            if dd > max_dd: max_dd = dd
            
            positions -= 1
    
    wr = wins / trades if trades > 0 else 0
    pf = wins_r / losses_r if losses_r > 0 else float('inf')
    avg_r = total_r / trades if trades > 0 else 0
    
    marker = " ← CURRENT" if (sl == 2.17 and tp == 1.75) else ""
    if pf > best_pf and trades > 100:
        best_pf = pf
        best_combo = (sl, tp)
    
    print(f"{sl:>4.2f} {tp:>4.2f} {trades:>5} {wr:>5.1%} {pf:>6.2f} {avg_r:>6.2f} {max_dd*100:>5.1f}{marker}")

print(f"\n>>> BEST PF: SL={best_combo[0]}, TP={best_combo[1]}, PF={best_pf:.2f}")

# =============================================
# REGIME BREAKDOWN
# =============================================
print("\n" + "=" * 50)
print("[2/2] REGIME BREAKDOWN (Current Config)")
print("=" * 50)

# Run single backtest with regime tracking
class RegimeTracker:
    def __init__(self):
        self.stats = {}
        
    def track(self, regime, r_mult):
        if regime not in self.stats:
            self.stats[regime] = {'wins': 0, 'losses': 0, 'total_r': 0.0, 'count': 0}
        self.stats[regime]['count'] += 1
        self.stats[regime]['total_r'] += r_mult
        if r_mult > 0:
            self.stats[regime]['wins'] += 1
        else:
            self.stats[regime]['losses'] += 1

tracker = RegimeTracker()

# Simulate with current config
sl, tp = 2.17, 1.75
for i in range(39, len(c) - 50):
    cur_date = df['timestamp'].iloc[i].date()
    # ... (same entry logic as above, simplified)
    # Just track completed trades
    pass

# Run actual optimized backtest but with regime tracking
class RegimeBT(OptimizedBacktest):
    def __init__(self, df):
        super().__init__(df)
        self.regime_data = {}
        
    def execute(self, signal, i):
        trade = super().execute(signal, i)
        regime = self.df['regime'].iloc[i]
        if regime not in self.regime_data:
            self.regime_data[regime] = {'wins': 0, 'losses': 0, 'total_r': 0.0, 'count': 0, 'wins_r': 0.0, 'losses_r': 0.0}
        rd = self.regime_data[regime]
        rd['count'] += 1
        rd['total_r'] += trade.profit_r
        if trade.profit_r > 0:
            rd['wins'] += 1
            rd['wins_r'] += trade.profit_r
        else:
            rd['losses'] += 1
            rd['losses_r'] += abs(trade.profit_r)
        return trade

bt = RegimeBT(df)
res = bt.run()

print(f"\n{'Regime':<12} {'Count':>6} {'Wins':>5} {'Loss':>5} {'WR':>6} {'TotalR':>8} {'PF':>6}")
print("-" * 50)
for regime in sorted(bt.regime_data.keys()):
    d = bt.regime_data[regime]
    wr = d['wins'] / d['count'] if d['count'] > 0 else 0
    pf = d['wins_r'] / d['losses_r'] if d['losses_r'] > 0 else float('inf')
    print(f"{regime:<12} {d['count']:>6} {d['wins']:>5} {d['losses']:>5} {wr:>5.1%} {d['total_r']:>8.1f} {pf:>6.2f}")

# Summary
print("\n" + "=" * 50)
print("KESIMPULAN")
print("=" * 50)

# Theoretical PF calculation
current_sl, current_tp = 2.17, 1.75
theoretical = 0.64 * current_tp / (0.36 * current_sl)
print(f"\nCurrent setup: SL={current_sl}R, TP={current_tp}R, TP/SL={current_tp/current_sl:.2f}")
print(f"Theoretical PF (at 64% WR): {theoretical:.2f}")
print(f"Best achievable PF (sweep): {best_pf:.2f}")

if best_pf >= 1.5:
    print(f"\n✅ PF 1.5 DAPAT dicapai HANYA dengan ubah preset")
    print(f"   Recommended: SL={best_combo[0]}R, TP={best_combo[1]}R")
else:
    print(f"\n⚠️ PF 1.5 TIDAK tercapai config-only")
    print(f"   → Perlu evaluasi model / regime filter")

# Show losing regimes
worst = min(bt.regime_data.items(), key=lambda x: x[1]['total_r']/max(x[1]['count'],1))
print(f"\nRegime lemah: {worst[0]} (AvgR={worst[1]['total_r']/worst[1]['count']:.2f})")
print("→ Tighten entry filter untuk regime ini")

# AI Confidence impact
print(f"\nAI Confidence threshold sensitivity:")
for thr in [0.55, 0.60, 0.65, 0.70, 0.75]:
    # Approximate: higher threshold = fewer trades, higher WR
    # Rough estimate: each 0.05 threshold ↑ → WR +2%, Trades -20%
    est_wr = 0.64 + (thr - 0.60) * 0.4  # rough linear approx
    est_pf = est_wr * 1.75 / ((1-est_wr) * 2.17)
    print(f"  InpAIMinConfidence={thr:.2f} → est WR={est_wr:.1%}, est PF={est_pf:.2f}")
