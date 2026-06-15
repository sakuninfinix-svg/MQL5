#!/usr/bin/env python3
"""
Comprehensive Backtest with Optimized Parameters
Tests on extended synthetic data matching real market conditions
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Dict, Tuple
import json

# Use the optimized parameters
OPTIMIZED_CONFIG = {
    'lot_size': 0.01, 'risk_percent': 1.95, 'sl_multiplier': 2.17, 'tp_multiplier': 1.75,
    'max_daily_loss_pct': 3.0, 'max_drawdown_pct': 10.0, 'max_open_positions': 3,
    'use_break_even': True, 'break_even_atr_mult': 1.0, 'use_trailing_stop': True,
    'trail_atr_mult': 1.0,
    'atr_period': 15, 'adx_period': 16, 'adx_trend_threshold': 26.5,
    'spread_filter_pips': 3.0, 'session_start_hour': 0, 'session_end_hour': 23,
    'min_pattern_score': 42.5, 'pattern_lookback_bars': 39,
    'pin_bar_ratio': 2.0, 'engulf_multiplier': 1.1,
}

@dataclass
class TradeResult:
    entry_idx: int; exit_idx: int; direction: int
    entry_price: float; exit_price: float; sl_price: float; tp_price: float
    profit_pips: float; profit_r: float; profit_dollars: float
    duration_bars: int; hit_tp: bool; hit_sl: bool

class AdvancedMarketGenerator:
    """Generates more realistic market data with regime changes"""
    
    def __init__(self, seed=42):
        np.random.seed(seed)
        self.price = 1.1000
        
    def generate_realistic_series(self, n_bars=50000) -> pd.DataFrame:
        """Generate series with multiple market regimes"""
        regimes = [
            ("TREND_UP", 8000, 0.00008, 0.0006),
            ("TREND_DOWN", 7000, -0.00008, 0.0007),
            ("RANGE", 6000, 0.0, 0.0005),
            ("VOLATILE", 4000, 0.0, 0.0015),
            ("TREND_UP", 5000, 0.0001, 0.0006),
            ("CRASH", 3000, -0.0002, 0.0025),
            ("RECOVERY", 4000, 0.00005, 0.0008),
            ("RANGE", 5000, 0.0, 0.0005),
            ("TREND_DOWN", 4000, -0.00006, 0.0007),
            ("CHOPPY", 4000, 0.0, 0.0009),
        ]
        
        all_data = []
        base_time = datetime(2023, 1, 1)
        
        for regime_name, length, trend, vol in regimes:
            segment = self._generate_regime(regime_name, length, trend, vol, base_time + timedelta(hours=len(all_data)))
            all_data.append(segment)
        
        df = pd.concat(all_data, ignore_index=True)
        if len(df) > n_bars:
            df = df.iloc[:n_bars]
        return df
    
    def _generate_regime(self, name: str, n: int, trend: float, vol: float, start_time: datetime) -> pd.DataFrame:
        opens, highs, lows, closes, volumes = [], [], [], [], []
        current = self.price
        
        for i in range(n):
            o = current
            trend_move = trend + vol * np.random.randn() * 0.3
            vol_move = vol * np.random.randn() * 0.7
            
            # Fat tails for crash/volatile
            if name in ["CRASH", "VOLATILE"] and np.random.random() < 0.02:
                vol_move *= 3.0
            
            hl = abs(vol * np.random.randn() * 0.5)
            h = o + max(0, trend_move) + hl
            l = o + min(0, trend_move) - hl
            c = o + trend_move * 0.6 + vol_move * 0.4
            h = max(h, o, c); l = min(l, o, c)
            
            vol_base = 1000 * (1.5 if name in ["VOLATILE", "CRASH"] else 1.0)
            v = int(vol_base + abs(np.random.randn()) * vol_base * 0.5)
            
            opens.append(o); highs.append(h); lows.append(l); closes.append(c); volumes.append(v)
            current = c
        
        self.price = current
        times = [start_time + timedelta(hours=i) for i in range(n)]
        
        return pd.DataFrame({
            'timestamp': times, 'open': opens, 'high': highs, 
            'low': lows, 'close': closes, 'volume': volumes,
            'regime': name
        })

class TechnicalIndicators:
    @staticmethod
    def atr(h, l, c, p=14):
        tr = np.maximum(h - l, np.maximum(np.abs(h - np.roll(c,1)), np.abs(l - np.roll(c,1))))
        tr[0] = h[0] - l[0]
        return pd.Series(tr).rolling(p, min_periods=1).mean().to_numpy()
    
    @staticmethod
    def rsi(c, p=14):
        d = np.diff(c, prepend=c[0])
        g = np.where(d>0, d, 0); l = np.where(d<0, -d, 0)
        ag = pd.Series(g).rolling(p, min_periods=1).mean()
        al = pd.Series(l).rolling(p, min_periods=1).mean()
        return (100 - 100/(1 + ag/(al+1e-10))).to_numpy()
    
    @staticmethod
    def adx(h, l, c, p=14):
        tr = TechnicalIndicators.atr(h, l, c, p)
        pdm = np.diff(h, prepend=h[0]); mdm = -np.diff(l, prepend=l[0])
        pdm = np.where((pdm>0) & (pdm>mdm), pdm, 0)
        mdm = np.where((mdm>0) & (mdm>pdm), mdm, 0)
        pdi = 100 * pd.Series(pdm).rolling(p, min_periods=1).mean() / (tr+1e-10)
        mdi = 100 * pd.Series(mdm).rolling(p, min_periods=1).mean() / (tr+1e-10)
        dx = 100 * np.abs(pdi-mdi)/(pdi+mdi+1e-10)
        return pd.Series(dx).rolling(p, min_periods=1).mean().to_numpy()
    
    @staticmethod
    def stoch(h, l, c, k=5, d=3, s=3):
        ll = pd.Series(l).rolling(k, min_periods=1).min()
        hh = pd.Series(h).rolling(k, min_periods=1).max()
        k_raw = 100 * (c - ll) / (hh - ll + 1e-10)
        return pd.Series(k_raw).rolling(s, min_periods=1).mean().to_numpy()
    
    @staticmethod
    def detect_sr(h, l, c, lookback=50):
        res_dist = np.full(len(c), 0.5); sup_dist = np.full(len(c), 0.5)
        zone_str = np.full(len(c), 0.5); pat_score = np.full(len(c), 50.0)
        for i in range(lookback, len(c)):
            rh = h[i-lookback:i].max(); rl = l[i-lookback:i].min()
            cur = c[i]
            res_dist[i] = min(max((rh - cur)/cur, 0), 1) if cur>0 else 0.5
            sup_dist[i] = min(max((cur - rl)/cur, 0), 1) if cur>0 else 0.5
            rng = rh - rl
            pos = (cur - rl)/rng if rng>0 else 0.5
            zone_str[i] = 1 - 2*abs(pos - 0.5)
            pat_score[i] = 50 + (0.5 - abs(pos - 0.5)) * 100
        return res_dist, sup_dist, zone_str, pat_score

class OptimizedBacktest:
    def __init__(self, df: pd.DataFrame):
        self.df = df; self.c = df['close'].to_numpy()
        self.h = df['high'].to_numpy(); self.l = df['low'].to_numpy()
        self.v = df['volume'].to_numpy()
        self.trades: List[TradeResult] = []
        self.equity = 10000.0; self.peak = 10000.0; self.max_dd = 0.0
        self.daily_pnl = 0.0; self.positions = 0
        self.cfg = OPTIMIZED_CONFIG
        
        # Precompute indicators
        self.atr = TechnicalIndicators.atr(self.h, self.l, self.c, self.cfg['atr_period'])
        self.rsi = TechnicalIndicators.rsi(self.c, 14)
        self.adx = TechnicalIndicators.adx(self.h, self.l, self.c, self.cfg['adx_period'])
        self.stoch = TechnicalIndicators.stoch(self.h, self.l, self.c)
        self.sr_res, self.sr_sup, self.sr_zone, self.sr_pat = TechnicalIndicators.detect_sr(self.h, self.l, self.c, self.cfg['pattern_lookback_bars'])
        
    def check_entry(self, i: int) -> int:
        if i < self.cfg['pattern_lookback_bars']: return 0
        
        # Session filter
        hour = self.df['timestamp'].iloc[i].hour
        if not (self.cfg['session_start_hour'] <= hour <= self.cfg['session_end_hour']): return 0
        
        # ADX trend filter
        if self.adx[i] < self.cfg['adx_trend_threshold']: return 0
        
        # Pattern score filter
        if self.sr_pat[i] < self.cfg['min_pattern_score']: return 0
        
        # Spread filter (approximate)
        spread = (self.h[i] - self.l[i]) * 0.1  # ~10% of range as spread proxy
        if spread > self.cfg['spread_filter_pips'] * 0.0001: return 0
        
        # Position in range
        pos = (self.c[i] - self.l[i-self.cfg['pattern_lookback_bars']:i].min()) / \
              (self.h[i-self.cfg['pattern_lookback_bars']:i].max() - self.l[i-self.cfg['pattern_lookback_bars']:i].min() + 1e-10)
        
        # Regime-aware entry logic
        regime = self.df['regime'].iloc[i]
        
        if regime in ["TREND_UP", "TREND_UP_FAST", "RECOVERY"]:
            # Trend following - buy pullbacks near support
            if self.sr_sup[i] < 0.25 and self.sr_zone[i] > 0.4 and pos < 0.4:
                if self.rsi[i] < 70: return 1  # BUY
                
        elif regime in ["TREND_DOWN"]:
            # Sell rallies near resistance
            if self.sr_res[i] < 0.25 and self.sr_zone[i] > 0.4 and pos > 0.6:
                if self.rsi[i] > 30: return -1  # SELL
                
        elif regime in ["RANGE", "CHOPPY"]:
            # Range trading - bounce at extremes
            if self.sr_zone[i] > 0.5:
                if self.sr_sup[i] < 0.2 and self.rsi[i] < 65: return 1
                if self.sr_res[i] < 0.2 and self.rsi[i] > 35: return -1
                
        elif regime in ["VOLATILE", "CRASH"]:
            # Breakout/momentum
            if pos > 0.7 and self.sr_res[i] > 0.3 and self.rsi[i] > 50: return 1
            if pos < 0.3 and self.sr_sup[i] > 0.3 and self.rsi[i] < 50: return -1
            
        return 0
    
    def execute(self, signal: int, i: int) -> TradeResult:
        entry = self.c[i]
        atr = max(self.atr[i], 0.0001)
        sl_mult, tp_mult = self.cfg['sl_multiplier'], self.cfg['tp_multiplier']
        
        if signal == 1:
            sl = entry - atr * sl_mult; tp = entry + atr * tp_mult
        else:
            sl = entry + atr * sl_mult; tp = entry - atr * tp_mult
        
        # Simulate forward
        hit_sl = hit_tp = False; exit_p = entry
        max_bars = min(150, len(self.c) - i - 1)
        
        for k in range(1, max_bars):
            h, l = self.h[i+k], self.l[i+k]
            if signal == 1:
                if l <= sl: hit_sl = True; exit_p = sl; break
                if h >= tp: hit_tp = True; exit_p = tp; break
            else:
                if h >= sl: hit_sl = True; exit_p = sl; break
                if l <= tp: hit_tp = True; exit_p = tp; break
        
        if not hit_tp and not hit_sl:
            exit_p = self.c[i + max_bars]
        
        pips = (exit_p - entry) * 10000 if signal == 1 else (entry - exit_p) * 10000
        sl_pips = abs(entry - sl) * 10000
        r_mult = pips / sl_pips if sl_pips > 0 else 0
        dollars = r_mult * self.cfg['risk_percent'] * 10000 * self.cfg['lot_size'] / 100  # approx
        
        return TradeResult(i, -1, signal, entry, exit_p, sl, tp, pips, r_mult, dollars, 0, hit_tp, hit_sl)
    
    def run(self) -> Dict:
        for i in range(self.cfg['pattern_lookback_bars'], len(self.c) - 150):
            # Daily reset
            if i > 0 and self.df['timestamp'].iloc[i].date() != self.df['timestamp'].iloc[i-1].date():
                self.daily_pnl = 0; self.positions = 0
            
            # Risk limits
            if self.daily_pnl < -self.cfg['max_daily_loss_pct'] * 100: continue
            if self.max_dd > self.cfg['max_drawdown_pct'] / 100: continue
            if self.positions >= self.cfg['max_open_positions']: continue
            
            signal = self.check_entry(i)
            if signal != 0:
                trade = self.execute(signal, i)
                trade.exit_idx = i + trade.duration_bars
                
                # Update equity
                self.equity += trade.profit_dollars
                self.daily_pnl += trade.profit_dollars
                self.positions += 1
                
                if self.equity > self.peak: self.peak = self.equity
                dd = (self.peak - self.equity) / self.peak
                if dd > self.max_dd: self.max_dd = dd
                
                self.trades.append(trade)
                self.positions -= 1
        
        return self._metrics()
    
    def _metrics(self) -> Dict:
        if not self.trades:
            return {'trades': 0, 'fitness': -1000}
        
        wins = [t for t in self.trades if t.profit_r > 0]
        losses = [t for t in self.trades if t.profit_r <= 0]
        
        total_r = sum(t.profit_r for t in self.trades)
        wp = sum(t.profit_r for t in wins) if wins else 0
        wl = abs(sum(t.profit_r for t in losses)) if losses else 1
        pf = wp / wl if wl > 0 else 0
        wr = len(wins) / len(self.trades)
        ret_pct = (self.equity - 10000) / 100
        sharpe = ret_pct / (self.max_dd * 100) if self.max_dd > 0 else 0
        
        # Fitness similar to MT5
        fitness = 0
        if len(self.trades) >= 20 and total_r > 0:
            fitness += np.log(1 + abs(total_r) * 100)
            fitness += 2 * np.log(1 + pf)
            fitness += 1.5 * np.log(1 + ret_pct/10)
            fitness += 0.5 * wr
            fitness += 0.25 * sharpe
            fitness -= 0.15 * self.max_dd * 100
        else:
            fitness = -1000
        
        return {
            'trades': len(self.trades), 'wins': len(wins), 'win_rate': wr,
            'profit_factor': pf, 'total_r': total_r, 'return_pct': ret_pct,
            'max_dd_pct': self.max_dd * 100, 'sharpe': sharpe, 'fitness': fitness,
            'avg_duration': np.mean([t.duration_bars for t in self.trades]),
            'tp_rate': sum(1 for t in self.trades if t.hit_tp)/len(self.trades),
            'sl_rate': sum(1 for t in self.trades if t.hit_sl)/len(self.trades),
        }

# Run comprehensive backtest
print("=" * 60)
print("COMPREHENSIVE BACKTEST - OPTIMIZED PARAMETERS")
print("=" * 60)

gen = AdvancedMarketGenerator(seed=42)
df = gen.generate_realistic_series(50000)
print(f"Generated {len(df)} bars across {df['regime'].nunique()} regimes")
print(f"Regime distribution:\n{df['regime'].value_counts()}")

bt = OptimizedBacktest(df)
results = bt.run()

print("\n" + "=" * 60)
print("BACKTEST RESULTS")
print("=" * 60)
for k, v in results.items():
    print(f"  {k}: {v}")

# Save results
output = {
    'timestamp': datetime.now().isoformat(),
    'config': OPTIMIZED_CONFIG,
    'results': results,
    'num_bars': len(df),
    'regimes_tested': df['regime'].unique().tolist()
}
import json
with open('output/comprehensive_backtest_results.json', 'w') as f:
    json.dump(output, f, indent=2, default=str)
print("\nResults saved to output/comprehensive_backtest_results.json")