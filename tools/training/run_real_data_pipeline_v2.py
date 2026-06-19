#!/usr/bin/env python3
"""
Real data pipeline v2: use forward returns as labels (not trade outcomes).
This removes dependence on the specific entry/exit strategy.
"""
import sys, os
import numpy as np
import pandas as pd
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from real_feature_extractor import RealAIFeatureExtractor, AI_FEATURE_DIM

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

def main():
    base = Path(__file__).parent.parent
    ohlcv_path = base / "output/eurusd_h1_2020_2025.csv"
    out_path = base / "output/AI_Training_Data_Raw_v4.csv"
    
    print("Loading real OHLCV data...")
    df = load_ohlcv(str(ohlcv_path))
    print(f"  {len(df)} bars")
    
    print("Assigning regimes...")
    df['regime'] = assign_regime(df['close'].to_numpy())
    
    print("Computing 34 features...")
    extractor = RealAIFeatureExtractor()
    features = extractor.extract_all_features(df)
    print(f"  Feature matrix: {features.shape}")
    
    close = df['close'].to_numpy()
    
    print("Creating labels from forward returns...")
    rows = []
    
    for i in range(50, len(close) - 24):
        fwd_ret_12h = (close[i+12] - close[i]) / close[i]
        fwd_ret_24h = (close[i+24] - close[i]) / close[i]
        
        # Label: 1 if > 0.15% in 24h, -1 if < -0.15%, 0 otherwise
        if fwd_ret_24h > 0.0015:
            label = 1.0
        elif fwd_ret_24h < -0.0015:
            label = -1.0
        else:
            if np.random.random() > 0.3:
                continue
            label = 0.0
        
        # Sample weight based on confidence
        weight = min(max(abs(fwd_ret_24h) * 500, 0.5), 3.0)
        
        row = {f'f{i_}': float(features[i, i_]) for i_ in range(AI_FEATURE_DIM)}
        row.update({
            'label': label,
            'weight': weight,
            'timestamp': df['timestamp'].iloc[i].isoformat(),
            'symbol': 'EURUSD',
            'timeframe': 'H1',
            'regime': int(df['regime'].iloc[i]),
            'trade_type': 'BUY' if label > 0 else 'SELL' if label < 0 else 'NEUTRAL',
            'profit_pips': fwd_ret_24h * 10000,
            'duration_bars': 24,
            'notes': f"fwd_ret_12h={fwd_ret_12h:.5f},fwd_ret_24h={fwd_ret_24h:.5f},regime={int(df['regime'].iloc[i])}"
        })
        rows.append(row)
    
    df_train = pd.DataFrame(rows)
    df_train.to_csv(str(out_path), index=False)
    
    n = len(df_train)
    w = (df_train['label'] == 1.0).sum()
    l = (df_train['label'] == -1.0).sum()
    neut = (df_train['label'] == 0.0).sum()
    print(f"\nSaved {n} samples")
    print(f"  BUY:  {w} ({w/n*100:.1f}%)")
    print(f"  SELL: {l} ({l/n*100:.1f}%)")
    print(f"  NEUT: {neut} ({neut/n*100:.1f}%)")
    print(f"\nNext:")
    print(f"  python3 training/preprocess_ai_training_data.py --input output/AI_Training_Data_Raw_v4.csv --output output/AI_Training_Data_Processed_v4.csv")
    print(f"  python3 training/train_mlp_classifier.py --csv output/AI_Training_Data_Processed_v4.csv --out output --epochs 300")

if __name__ == "__main__":
    main()
