#!/usr/bin/env python3
"""
Quick PF Analysis: SL/TP Sweep + Regime Breakdown
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import json

# Load existing backtest results
with open('output/comprehensive_backtest_results.json', 'r') as f:
    data = json.load(f)

# We need to re-run with fresh data to get per-trade details
# Let's generate a focused test

from comprehensive_backtest import AdvancedMarketGenerator, OptimizedBacktest, OPTIMIZED_CONFIG

print("=" * 60)
print("PF ANALYSIS: SL/TP SWEEP + REGIME BREAKDOWN")
print("=" * 60)

# Generate data once
gen = AdvancedMarketGenerator(seed=42)
df = gen.generate_realistic_series(50000)

# Test different SL/TP combinations
results = []

sl_range = [1.5, 1.75, 2.0, 2.17, 2.25, 2.5]
tp_range = [1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]

print("\n[1/2] SL/TP SWEEP")
print("-" * 60)
print(f"{'SL':>5} {'TP':>5} {'Trades':>7} {'WR':>7} {'PF':>7} {'AvgR':>7} {'DD%':>6}")
print("-" * 60)

for sl in sl_range:
    for tp in tp_range:
        cfg = OPTIMIZED_CONFIG.copy()
        cfg['sl_multiplier'] = sl
        cfg['tp_multiplier'] = tp
        
        bt = OptimizedBacktest(df)
        bt.cfg = cfg
        # Recompute with new config
        bt.atr = bt.atr  # already computed
        bt.cfg = cfg
        
        # Run with modified config
        from comprehensive_backtest import TechnicalIndicators
        class TempBT(OptimizedBacktest):
            def __init__(self, df, cfg):
                self.df = df
                self.c = df['close'].to_numpy()
                self.h = df['high'].to_numpy()
                self.l = df['low'].to_numpy()
                self.v = df['volume'].to_numpy()
                self.trades = []
                self.equity = 10000.0
                self.peak = 10000.0
                self.max_dd = 0.0
                self.daily_pnl = 0.0
                self.positions = 0
                self.cfg = cfg
                
                self.atr = TechnicalIndicators.atr(self.h, self.l, self.c, cfg['atr_period'])
                self.rsi = TechnicalIndicators.rsi(self.c, 14)
                self.adx = TechnicalIndicators.adx(self.h, self.l, self.c, cfg['adx_period'])
                self.stoch = TechnicalIndicators.stoch(self.h, self.l, self.c)
                self.sr_res, self.sr_sup, self.sr_zone, self.sr_pat = TechnicalIndicators.detect_sr(self.h, self.l, self.c, cfg['pattern_lookback_bars'])
        
        tbt = TempBT(df, cfg)
        res = tbt.run()
        
        results.append({
            'sl': sl, 'tp': tp,
            'trades': res['trades'], 'wr': res['win_rate'],
            'pf': res['profit_factor'], 'avg_r': res['total_r'] / max(res['trades'], 1),
            'dd': res['max_dd_pct']
        })
        
        if res['trades'] > 50:
            print(f"{sl:>5.2f} {tp:>5.2f} {res['trades']:>7} {res['win_rate']:>6.1%} {res['profit_factor']:>7.2f} {res['total_r']/res['trades']:>7.2f} {res['max_dd_pct']:>6.2f}")

# Find best PF
best = max([r for r in results if r['trades'] > 100], key=lambda x: x['pf'])
print(f"\n>>> BEST PF: SL={best['sl']}, TP={best['tp']}, PF={best['pf']:.2f}, WR={best['wr']:.1%}, Trades={best['trades']}")

# Regime breakdown with current best config
print("\n" + "=" * 60)
print("[2/2] REGIME BREAKDOWN (Current Optimized Config)")
print("=" * 60)

# Run with regime tracking
class RegimeBT(OptimizedBacktest):
    def __init__(self, df):
        super().__init__(df)
        self.regime_stats = {}
        
    def execute(self, signal, i):
        trade = super().execute(signal, i)
        regime = self.df['regime'].iloc[i]
        if regime not in self.regime_stats:
            self.regime_stats[regime] = {'wins': 0, 'losses': 0, 'profit_r': 0, 'count': 0}
        self.regime_stats[regime]['count'] += 1
        self.regime_stats[regime]['profit_r'] += trade.profit_r
        if trade.profit_r > 0:
            self.regime_stats[regime]['wins'] += 1
        else:
            self.regime_stats[regime]['losses'] += 1
        return trade

bt = RegimeBT(df)
res = bt.run()

print(f"\n{'Regime':<15} {'Trades':>7} {'Wins':>6} {'Losses':>7} {'WR':>7} {'TotalR':>8} {'PF':>7}")
print("-" * 60)
for regime, stats in sorted(bt.regime_stats.items()):
    wr = stats['wins'] / stats['count'] if stats['count'] > 0 else 0
    wins_r = sum(t.profit_r for t in bt.trades if t.profit_r > 0 and bt.df['regime'].iloc[t.entry_idx] == regime)
    losses_r = sum(t.profit_r for t in bt.trades if t.profit_r <= 0 and bt.df['regime'].iloc[t.entry_idx] == regime)
    pf = wins_r / abs(losses_r) if losses_r != 0 else float('inf')
    print(f"{regime:<15} {stats['count']:>7} {stats['wins']:>6} {stats['losses']:>7} {wr:>6.1%} {stats['profit_r']:>8.1f} {pf:>7.2f}")

# Summary
print("\n" + "=" * 60)
print("ANALISIS")
print("=" * 60)

# Calculate current TP:SL ratio impact
current_sl = OPTIMIZED_CONFIG['sl_multiplier']
current_tp = OPTIMIZED_CONFIG['tp_multiplier']
print(f"\nCurrent: SL={current_sl}R, TP={current_tp}R, Ratio TP/SL={current_tp/current_sl:.2f}")
print(f"Expected PF at 64% WR with 1:1 = {0.64 * 1 / (0.36 * 1):.2f}")
print(f"Expected PF at 64% WR with current = {0.64 * current_tp / (0.36 * current_sl):.2f}")

# Check if PF can reach 1.5 with config only
theoretical_best = max(r['pf'] for r in results if r['trades'] > 200)
print(f"\nBest achievable PF (config only): {theoretical_best:.2f}")
if theoretical_best >= 1.5:
    print("✅ PF 1.5 BISA dicapai hanya dengan ubah preset (SL/TP/Confidence)")
else:
    print("⚠️ PF 1.5 TIDAK tercapai config only → perlu evaluasi model")

# Regime-specific issues
worst_regime = min(bt.regime_stats.items(), key=lambda x: x[1]['profit_r'] / max(x[1]['count'], 1))
print(f"\nRegime paling lemah: {worst_regime[0]} (TotalR={worst_regime[1]['profit_r']:.1f})")
print("→ Coba tighten filter untuk regime ini")
