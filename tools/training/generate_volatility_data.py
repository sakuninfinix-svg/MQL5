#!/usr/bin/env python3
"""
Generate volatility prediction training data from multi-symbol M15 OHLCV.
Computes 34 features per bar. Target: future realized volatility over next N bars.
Output: sequences of features for LSTM training.
"""
import numpy as np
import pandas as pd
import sys, os, json
from pathlib import Path
from datetime import datetime

sys.path.insert(0, os.path.dirname(__file__))
from real_feature_extractor import RealAIFeatureExtractor, AI_FEATURE_DIM

SEQ_LEN = 16       # lookback bars
FORECAST_BARS = 8  # future bars for vol calculation
VOLATILITY_THRESHOLD = None  # None = regression; float = binary (1 if vol > thresh)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / 'output'
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def compute_realized_vol(close, i, n):
    """Future realized volatility (std of log returns) over next n bars."""
    if i + n >= len(close):
        return np.nan
    prices = close[i+1:i+1+n]
    if len(prices) < 3:
        return np.nan
    log_rets = np.diff(np.log(np.maximum(prices, 1e-10)))
    if len(log_rets) < 2:
        return np.nan
    return float(np.std(log_rets))

def generate_data(symbol_paths):
    extractor = RealAIFeatureExtractor()
    all_sequences = []
    all_targets = []
    all_metadata = []

    for symbol, path in symbol_paths.items():
        print(f"\nProcessing {symbol}...")
        df = pd.read_csv(path)
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        df = df.sort_values('timestamp').reset_index(drop=True)
        
        for c in ['open','high','low','close','volume']:
            df[c] = pd.to_numeric(df[c], errors='coerce')
        df = df.dropna(subset=['open','high','low','close'])
        print(f"  {len(df)} bars loaded")

        df['regime'] = 3  # neutral regime
        features = extractor.extract_all_features(df)
        close = df['close'].to_numpy()
        timestamps = df['timestamp'].to_numpy()

        n = len(features)
        for i in range(SEQ_LEN, n - FORECAST_BARS):
            seq = features[i - SEQ_LEN + 1 : i + 1]  # shape (SEQ_LEN, 34)
            if np.any(np.isnan(seq)) or np.any(np.isinf(seq)):
                continue

            target = compute_realized_vol(close, i, FORECAST_BARS)
            if np.isnan(target):
                continue

            all_sequences.append(seq)
            all_targets.append(target)
            all_metadata.append({
                'symbol': symbol,
                'timestamp': str(timestamps[i]),
                'idx': i,
            })

        print(f"  Generated {len(all_sequences)} sequences so far")

    X = np.stack(all_sequences, axis=0).astype(np.float32)  # (N, SEQ_LEN, 34)
    y = np.array(all_targets, dtype=np.float32)             # (N,)

    print(f"\nTotal: {len(X)} sequences, X={X.shape}, y={y.shape}")
    print(f"  y: min={y.min():.6e}, max={y.max():.6e}, mean={y.mean():.6e}, median={np.median(y):.6e}")
    return X, y, all_metadata

def save_data(X, y, metadata, name_prefix):
    npz_path = OUTPUT_DIR / f"{name_prefix}_sequences.npz"
    np.savez_compressed(npz_path, X=X, y=y)
    
    meta_path = OUTPUT_DIR / f"{name_prefix}_metadata.json"
    with open(meta_path, 'w') as f:
        json.dump({'n_samples': len(X), 'seq_len': SEQ_LEN, 'feature_dim': AI_FEATURE_DIM,
                   'forecast_bars': FORECAST_BARS, 'symbols': list(set(m['symbol'] for m in metadata)),
                   'y_min': float(y.min()), 'y_max': float(y.max()), 'y_mean': float(y.mean()),
                   'y_median': float(np.median(y))}, f, indent=2)
    
    print(f"Saved: {npz_path}")
    print(f"Saved: {meta_path}")
    return npz_path, meta_path

def find_data_files(data_dir):
    """Find available data files across all supported patterns."""
    patterns = ['*_m15_*.csv', '*_h1_*.csv']
    files = {}
    for pat in patterns:
        for f in data_dir.glob(pat):
            sym = f.name.split('_')[0]
            if sym not in files or f.stat().st_size > files[sym][1].stat().st_size:
                files[sym] = (pat, f)

    result = {}
    for sym, (pat, fpath) in files.items():
        result[sym] = str(fpath)
        print(f"{sym}: {fpath.name} ({fpath.stat().st_size//1024} KB) [{pat}]")

    if not result:
        # Try the eurusd_h1_2020_2025.csv path
        h1_path = data_dir / 'eurusd_h1_2020_2025.csv'
        if h1_path.exists():
            result['eurusd'] = str(h1_path)
            print(f"eurusd: {h1_path.name} ({h1_path.stat().st_size//1024} KB) [fallback]")
    return result


def main():
    print("=" * 60)
    print("Volatility Prediction Data Generator")
    print("=" * 60)
    
    data_dir = OUTPUT_DIR
    symbol_paths = find_data_files(data_dir)

    if not symbol_paths:
        print("ERROR: No symbol data found. Download data first.")
        sys.exit(1)

    tf = 'm15' if any('m15' in v for v in symbol_paths.values()) else 'h1'
    X, y, metadata = generate_data(symbol_paths)
    
    tag = f"volatility_{tf}"
    if len(symbol_paths) > 1:
        tag += f"_{len(symbol_paths)}sym"
    save_data(X, y, metadata, tag)
    print("\nDone!")

if __name__ == '__main__':
    main()
