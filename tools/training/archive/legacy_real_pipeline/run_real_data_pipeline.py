#!/usr/bin/env python3
"""Run the full pipeline with real EURUSD H1 data from Dukascopy."""
import sys, os, argparse
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from real_feature_extractor import RealAIFeatureExtractor, AI_FEATURE_DIM
from generate_quality_training_data import TechnicalIndicators, TradeSimulation, GeneratorConfig

def load_ohlcv(path):
    df = pd.read_csv(path)
    if 'timestamp' in df.columns and df['timestamp'].dtype == 'int64':
        df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
    elif 'timestamp' in df.columns:
        df['timestamp'] = pd.to_datetime(df['timestamp'])
    for c in ['open','high','low','close']:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    df = df.dropna(subset=['open','high','low','close']).sort_values('timestamp').reset_index(drop=True)
    df['volume'] = pd.to_numeric(df.get('volume', 1000), errors='coerce').fillna(1000)
    bad = (df['high'] < df['low']) | (df['open']<=0) | (df['close']<=0)
    if bad.any():
        df = df[~bad].reset_index(drop=True)
    print(f"Loaded {len(df)} bars: {df['timestamp'].min()} -> {df['timestamp'].max()}")
    print(f"Price range: {df['low'].min():.5f} - {df['high'].max():.5f}")
    return df

def assign_regime(close, lookback=50):
    n = len(close)
    regime = np.zeros(n, dtype=np.int32)
    for i in range(lookback, n):
        s20 = max(0, i-20)
        ret20 = (close[i] - close[s20]) / max(close[s20], 1e-10)
        rets = np.diff(close[s20:i+1]) / (close[s20:i] + 1e-10)
        vol = np.std(rets) if len(rets) > 1 else 0
        if vol > 0.015:
            regime[i] = 5 if ret20 < -0.02 else 4
        elif abs(ret20) > 0.01:
            regime[i] = 1 if ret20 > 0 else 2
        else:
            regime[i] = 3
    return regime

def simulate_trades(df, features):
    """Simulate MA crossover trades matching PASR_DATA_EXPORTER.mq5 logic."""
    close = df['close'].to_numpy()
    high = df['high'].to_numpy()
    low = df['low'].to_numpy()
    atr14 = TechnicalIndicators.atr(high, low, close, 14)
    trades = []
    n = len(close)
    
    ma20_list = pd.Series(close).rolling(20).mean().to_numpy()
    ma50_list = pd.Series(close).rolling(50).mean().to_numpy()
    
    in_trade = False
    current_trade = None
    
    for i in range(50, n - 10):
        if in_trade:
            t = current_trade
            if t.direction == 1:
                if low[i] <= t.sl_price:
                    t.hit_sl = True
                    t.exit_price = t.sl_price
                elif high[i] >= t.tp_price:
                    t.hit_tp = True
                    t.exit_price = t.tp_price
            else:
                if high[i] >= t.sl_price:
                    t.hit_sl = True
                    t.exit_price = t.sl_price
                elif low[i] <= t.tp_price:
                    t.hit_tp = True
                    t.exit_price = t.tp_price
            
            if t.hit_tp or t.hit_sl or (i - t.entry_idx) >= 100:
                if not t.hit_tp and not t.hit_sl:
                    t.exit_price = close[i]
                if t.direction == 1:
                    t.profit_pips = (t.exit_price - t.entry_price) * 10000
                else:
                    t.profit_pips = (t.entry_price - t.exit_price) * 10000
                sl_dist = abs(t.entry_price - t.sl_price) * 10000
                t.profit_r = t.profit_pips / sl_dist if sl_dist > 0 else 0
                t.duration_bars = i - t.entry_idx
                t.exit_idx = i
                trades.append(t)
                in_trade = False
            continue
        
        if i < 50 or np.isnan(ma20_list[i]) or np.isnan(ma50_list[i]):
            continue
        
        atr = max(atr14[i], 1e-8)
        signal = 0
        if close[i] > ma20_list[i] + atr * 0.3:
            slope = ma20_list[i] - (ma50_list[i-5] if i>=5 else ma50_list[i])
            if slope > 0:
                signal = 1
        elif close[i] < ma20_list[i] - atr * 0.3:
            slope = ma20_list[i] - (ma50_list[i-5] if i>=5 else ma50_list[i])
            if slope < 0:
                signal = -1
        
        if signal != 0:
            sl_mult, tp_mult = 1.8, 2.2
            entry_price = close[i]
            sl = entry_price - atr * sl_mult if signal == 1 else entry_price + atr * sl_mult
            tp = entry_price + atr * tp_mult if signal == 1 else entry_price - atr * tp_mult
            f = features[i].copy()
            pq = float(np.mean([f[17], f[18], f[29], f[30]]))
            
            current_trade = TradeSimulation(
                entry_idx=i, exit_idx=-1, direction=signal,
                entry_price=entry_price, exit_price=0.0,
                sl_price=sl, tp_price=tp,
                profit_pips=0.0, profit_r=0.0, duration_bars=0,
                hit_tp=False, hit_sl=False,
                entry_regime=int(df['regime'].iloc[i]),
                exit_regime=-1,
                features_at_entry=f, pattern_quality=pq,
                confidence=min(max(pq * 1.5, 0.1), 0.95)
            )
            in_trade = True
    
    return trades

def build_training_data(trades, df, output_path, symbol="EURUSD", timeframe="H1"):
    rows = []
    for t in trades:
        profit_r = t.profit_r
        if profit_r > 0.5:
            label = 1.0
        elif profit_r < -0.5:
            label = -1.0
        else:
            if np.random.random() > 0.4:
                continue
            label = 0.0
        
        weight = min(max(abs(profit_r), 0.1), 5.0)
        if t.hit_tp: weight *= 1.5
        if t.hit_sl: weight *= 1.3
        weight = min(max(weight, 0.1), 5.0)
        
        row = {f'f{i}': float(t.features_at_entry[i]) for i in range(AI_FEATURE_DIM)}
        row.update({
            'label': label,
            'weight': weight,
            'timestamp': df['timestamp'].iloc[t.entry_idx].isoformat(),
            'symbol': symbol,
            'timeframe': timeframe,
            'regime': t.entry_regime,
            'trade_type': 'BUY' if t.direction == 1 else 'SELL',
            'profit_pips': t.profit_pips,
            'duration_bars': t.duration_bars,
            'notes': f"hit_tp={t.hit_tp},hit_sl={t.hit_sl},regime={t.entry_regime}"
        })
        rows.append(row)
    
    df_train = pd.DataFrame(rows)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df_train.to_csv(output_path, index=False)
    
    n_win = (df_train['label'] == 1.0).sum()
    n_loss = (df_train['label'] == -1.0).sum()
    n_neutral = (df_train['label'] == 0.0).sum()
    print(f"\nSaved {len(df_train)} samples to {output_path}")
    print(f"  Wins:    {n_win} ({n_win/len(df_train)*100:.1f}%)")
    print(f"  Losses:  {n_loss} ({n_loss/len(df_train)*100:.1f}%)")
    print(f"  Neutral: {n_neutral} ({n_neutral/len(df_train)*100:.1f}%)")
    return df_train

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ohlcv", default="output/eurusd_h1_2020_2025.csv")
    parser.add_argument("--output", default="output/AI_Training_Data_Raw.csv")
    args = parser.parse_args()
    
    base = Path(__file__).parent.parent
    ohlcv_path = base / args.ohlcv
    out_path = base / args.output
    
    print("Loading real OHLCV data...")
    df = load_ohlcv(str(ohlcv_path))
    
    print("Assigning market regimes...")
    df['regime'] = assign_regime(df['close'].to_numpy())
    
    print("Computing 34 features (matching AIFeatureBuilder.mqh)...")
    extractor = RealAIFeatureExtractor()
    features = extractor.extract_all_features(df)
    print(f"  Feature matrix: {features.shape}")
    
    print("Simulating trades (MA crossover)...")
    trades = simulate_trades(df, features)
    print(f"  Total trades: {len(trades)}")
    wins = sum(1 for t in trades if t.profit_r > 0.5)
    losses = sum(1 for t in trades if t.profit_r < -0.5)
    print(f"  Wins: {wins}, Losses: {losses}, WR: {wins/len(trades)*100:.1f}%" if len(trades)>0 else "  No trades!")
    
    print("\nBuilding training dataset...")
    df_train = build_training_data(trades, df, str(out_path))
    
    print(f"\nDone. Next: python3 training/preprocess_ai_training_data.py --input {args.output} --output output/AI_Training_Data_Processed.csv")
    print(f"       python3 training/train_mlp_classifier.py --csv output/AI_Training_Data_Processed.csv --out output --epochs 300")

if __name__ == "__main__":
    main()
