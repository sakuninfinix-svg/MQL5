#!/usr/bin/env python3
"""
PASR MT5 Trade Data Importer
=============================
Imports trade CSV exported from PASR_DATA_EXPORTER.mq5, recomputes the
34 AI features at each entry bar (matching AIFeatureBuilder.mqh exactly),
and creates training data ready for train_mlp_classifier.py.

Pipeline:
  1. Run PASR_DATA_EXPORTER.mq5 in MT5 Strategy Tester
  2. Copy PASR_trades_export.csv + PASR_ohlcv_export.csv to MQL5/tools/output/
  3. Run: python3 training/import_mt5_trades.py \\
         --csv output/PASR_trades_export.csv \\
         --ohlcv output/PASR_ohlcv_export.csv
  4. Train: python3 training/train_mlp_classifier.py --csv output/MT5_Training_Data.csv

CSV columns expected from PASR_DATA_EXPORTER.mq5:
  ticket,symbol,timeframe,entry_time,exit_time,direction,
  entry_price,exit_price,sl_price,tp_price,profit_pips,profit_r,
  hit_tp,hit_sl,duration_bars,atr_at_entry,rsi_at_entry,ma_at_entry

OHLCV CSV (exported separately from MT5 History Center or EA):
  timestamp,open,high,low,close,volume

REQUIREMENT: Both trade CSV and OHLCV CSV must be real MT5 data.
Synthetic data is NOT supported — use generate_quality_training_data.py for that.
"""

import numpy as np
import pandas as pd
import sys
import os
from pathlib import Path
from datetime import datetime, timedelta
from typing import Tuple
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from generate_quality_training_data import (
    AIFeatureExtractor, GeneratorConfig, AI_FEATURE_DIM
)


# ============================================================================
# Trade CSV Loading
# ============================================================================
MT5_REQUIRED_COLS = [
    'entry_time', 'exit_time', 'direction',
    'entry_price', 'exit_price', 'profit_r',
    'hit_tp', 'hit_sl'
]

MT5_NUMERIC_FLOAT = [
    'entry_price', 'exit_price', 'sl_price', 'tp_price',
    'profit_pips', 'profit_r', 'atr_at_entry', 'rsi_at_entry', 'ma_at_entry'
]

MT5_NUMERIC_INT = ['ticket', 'direction', 'hit_tp', 'hit_sl', 'duration_bars']


def load_mt5_csv(path: str) -> pd.DataFrame:
    """Load and validate MT5 exported trade CSV."""
    if not os.path.exists(path):
        raise FileNotFoundError(f"Trade CSV not found: {path}")

    df = pd.read_csv(path)
    if df.empty:
        raise ValueError(f"Trade CSV is empty: {path}")

    missing = [c for c in MT5_REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(
            f"Missing required columns: {missing}\n"
            f"Found columns: {list(df.columns)}\n"
            f"Ensure PASR_DATA_EXPORTER.mq5 was used to export this file."
        )

    df['entry_time'] = pd.to_datetime(df['entry_time'], errors='coerce')
    df['exit_time'] = pd.to_datetime(df['exit_time'], errors='coerce')
    null_entries = df['entry_time'].isna().sum()
    if null_entries > 0:
        print(f"  WARNING: Dropping {null_entries} rows with unparseable entry_time")
        df = df.dropna(subset=['entry_time']).reset_index(drop=True)

    for col in MT5_NUMERIC_FLOAT:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0.0)

    for col in MT5_NUMERIC_INT:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)

    # Direction normalization: accept string "buy"/"sell" or numeric 0/1
    if df['direction'].dtype == object:
        df['direction'] = df['direction'].str.lower().map({
            'buy': 1, 'sell': 0, 'long': 1, 'short': 0
        }).fillna(0).astype(int)

    n = len(df)
    wins = (df['profit_r'] > 0.5).sum()
    losses = (df['profit_r'] < -0.5).sum()
    neutral = n - wins - losses

    print(f"Loaded {n} trades from {path}")
    print(f"  Wins:    {wins:>5} ({wins/n*100:.1f}%)")
    print(f"  Losses:  {losses:>5} ({losses/n*100:.1f}%)")
    print(f"  Neutral: {neutral:>5} ({neutral/n*100:.1f}%) [will be dropped]")
    print(f"  Date range: {df['entry_time'].min()} → {df['entry_time'].max()}")

    if wins + losses < 100:
        raise ValueError(
            f"Only {wins + losses} classifiable trades (need ≥100). "
            f"Run Strategy Tester with more data."
        )

    return df


# ============================================================================
# OHLCV Loading
# ============================================================================
def load_ohlcv_csv(path: str) -> pd.DataFrame:
    """Load OHLCV CSV exported from MT5 History Center or EA."""
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"OHLCV CSV not found: {path}\n"
            f"Export OHLCV data from MT5 History Center (Ctrl+U) or "
            f"use PASR_DATA_EXPORTER.mq5 to export it.\n"
            f"Required columns: timestamp, open, high, low, close, volume"
        )

    df = pd.read_csv(path)
    if df.empty:
        raise ValueError(f"OHLCV CSV is empty: {path}")

    # Handle different timestamp column names
    ts_col = None
    for candidate in ['timestamp', 'time', 'date', 'datetime', 'Date']:
        if candidate in df.columns:
            ts_col = candidate
            break
    if ts_col is None:
        raise ValueError(
            f"No timestamp column found. Expected one of: "
            f"timestamp, time, date, datetime. Found: {list(df.columns)}"
        )
    if ts_col != 'timestamp':
        df = df.rename(columns={ts_col: 'timestamp'})

    df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')
    df = df.dropna(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)

    # Handle different OHLC column name variants
    col_map = {}
    for target, variants in [
        ('open', ['open', 'Open']),
        ('high', ['high', 'High']),
        ('low', ['low', 'Low']),
        ('close', ['close', 'Close']),
        ('volume', ['volume', 'Volume', 'tick_volume', 'vol']),
    ]:
        found = next((v for v in variants if v in df.columns), None)
        if found and found != target:
            col_map[found] = target
    if col_map:
        df = df.rename(columns=col_map)

    required_ohlcv = ['timestamp', 'open', 'high', 'low', 'close']
    missing = [c for c in required_ohlcv if c not in df.columns]
    if missing:
        raise ValueError(f"OHLCV missing columns: {missing}")

    if 'volume' not in df.columns:
        df['volume'] = 1000

    for col in ['open', 'high', 'low', 'close', 'volume']:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    df = df.dropna(subset=['open', 'high', 'low', 'close']).reset_index(drop=True)

    # Validate price sanity
    bad_prices = (df['high'] < df['low']) | (df['open'] <= 0) | (df['close'] <= 0)
    if bad_prices.any():
        n_bad = bad_prices.sum()
        print(f"  WARNING: Removing {n_bad} bars with invalid OHLC (high<low or price≤0)")
        df = df[~bad_prices].reset_index(drop=True)

    if len(df) < 100:
        raise ValueError(f"Only {len(df)} OHLCV bars loaded (need ≥100)")

    print(f"Loaded {len(df)} OHLCV bars from {path}")
    print(f"  Date range: {df['timestamp'].min()} → {df['timestamp'].max()}")
    print(f"  Price range: {df['close'].min():.5f} – {df['close'].max():.5f}")

    return df


# ============================================================================
# Regime Detection
# ============================================================================
def assign_regime(close: np.ndarray, lookback: int = 50) -> np.ndarray:
    """Assign market regime labels based on trend + volatility structure."""
    n = len(close)
    regime = np.zeros(n, dtype=np.int32)

    for i in range(lookback, n):
        start20 = max(0, i - 20)
        ret20 = (close[i] - close[start20]) / close[start20] if close[start20] > 0 else 0

        rets = np.diff(close[start20:i + 1]) / close[start20:i]
        vol = np.std(rets) if len(rets) > 1 else 0

        if vol > 0.015:
            regime[i] = 5 if ret20 < -0.02 else 4  # CRASH or VOLATILE
        elif abs(ret20) > 0.01:
            regime[i] = 1 if ret20 > 0 else 2  # TREND_UP or TREND_DOWN
        else:
            regime[i] = 3  # RANGE

    return regime


# ============================================================================
# Feature Extraction + Trade Matching
# ============================================================================
def compute_features_at_entries(
    df_ohlcv: pd.DataFrame,
    df_trades: pd.DataFrame,
    config: GeneratorConfig,
    max_time_diff_min: float = 90.0
) -> pd.DataFrame:
    """
    Extract 34 features from OHLCV, then match each trade to its entry bar
    using pd.merge_asof for O(n log n) matching.
    """
    print("Assigning market regimes...")
    df_ohlcv['regime'] = assign_regime(df_ohlcv['close'].to_numpy())

    print("Extracting 34 features (matching AIFeatureBuilder.mqh)...")
    extractor = AIFeatureExtractor(config)
    features = extractor.extract_all_features(df_ohlcv)
    print(f"  Feature matrix: {features.shape}")

    # Store features back into OHLCV for merge
    for i in range(AI_FEATURE_DIM):
        df_ohlcv[f'feat_{i}'] = features[:, i]
    df_ohlcv['_bar_idx'] = np.arange(len(df_ohlcv))

    # Build trade lookup with entry_time as key
    df_trades = df_trades.sort_values('entry_time').reset_index(drop=True)

    # merge_asof: for each trade, find nearest OHLCV bar ≤ entry_time
    merged = pd.merge_asof(
        df_trades,
        df_ohlcv,
        left_on='entry_time',
        right_on='timestamp',
        direction='nearest',
        tolerance=pd.Timedelta(minutes=max_time_diff_min)
    )

    # Filter unmatched
    matched_mask = merged['timestamp'].notna()
    n_matched = matched_mask.sum()
    n_skipped = len(merged) - n_matched
    print(f"  Matched: {n_matched} trades to OHLCV bars")
    if n_skipped > 0:
        print(f"  Skipped: {n_skipped} trades (no bar within {max_time_diff_min:.0f} min)")

    if n_matched < 50:
        raise ValueError(
            f"Only {n_matched} trades matched to OHLCV bars (need ≥50). "
            f"Check that OHLCV date range covers trade dates."
        )

    df = merged[matched_mask].copy()

    # Drop trades in warmup zone (first 50 bars)
    warmup_mask = df['_bar_idx'] >= 50
    n_warmup = (~warmup_mask).sum()
    if n_warmup > 0:
        print(f"  Dropped: {n_warmup} trades in warmup zone (bar < 50)")
    df = df[warmup_mask].copy()

    # Binary labels: win=1, loss=-1, drop neutral
    df['label'] = 0.0
    df.loc[df['profit_r'] > 0.5, 'label'] = 1.0
    df.loc[df['profit_r'] < -0.5, 'label'] = -1.0

    n_neutral = (df['label'] == 0.0).sum()
    if n_neutral > 0:
        print(f"  Dropping {n_neutral} neutral trades (|profit_r| ≤ 0.5)")
    df = df[df['label'] != 0.0].copy()

    if len(df) < 50:
        raise ValueError(f"Only {len(df)} classifiable trades after filtering (need ≥50)")

    # Compute sample weights
    df['weight'] = compute_sample_weights(df)

    # Build output DataFrame
    rows = []
    for _, row in df.iterrows():
        r = {f'f{i}': row[f'feat_{i}'] for i in range(AI_FEATURE_DIM)}
        r['label'] = row['label']
        r['weight'] = row['weight']
        r['timestamp'] = row['entry_time'].isoformat()
        r['symbol'] = row.get('symbol', 'EURUSD')
        r['timeframe'] = row.get('timeframe', 'H1')
        r['regime'] = int(row['regime'])
        r['trade_type'] = 'BUY' if row['direction'] == 1 else 'SELL'
        r['profit_pips'] = row.get('profit_pips', 0)
        r['duration_bars'] = row.get('duration_bars', 0)
        r['notes'] = (
            f"hit_tp={row['hit_tp']},hit_sl={row['hit_sl']},"
            f"bar={int(row['_bar_idx'])},profit_r={row['profit_r']:.3f}"
        )
        rows.append(r)

    df_train = pd.DataFrame(rows)

    n_win = (df_train['label'] == 1.0).sum()
    n_loss = (df_train['label'] == -1.0).sum()
    print(f"\n  Final dataset: {len(df_train)} samples")
    print(f"  Wins: {n_win} ({n_win/len(df_train)*100:.1f}%)")
    print(f"  Losses: {n_loss} ({n_loss/len(df_train)*100:.1f}%)")
    print(f"  Win rate: {n_win/len(df_train)*100:.1f}%")

    return df_train


def compute_sample_weights(df: pd.DataFrame) -> pd.Series:
    """Compute per-sample weights based on trade quality signals."""
    w = pd.Series(1.0, index=df.index)

    profit_r_abs = df['profit_r'].abs()
    w *= np.where(profit_r_abs > 1.5, 2.0,
         np.where(profit_r_abs > 1.0, 1.5,
         np.where(profit_r_abs > 0.5, 1.2, 1.0)))

    if 'hit_tp' in df.columns:
        w *= np.where(df['hit_tp'] == 1, 1.5, 1.0)
    if 'hit_sl' in df.columns:
        w *= np.where(df['hit_sl'] == 1, 1.3, 1.0)

    if 'duration_bars' in df.columns:
        dur = df['duration_bars']
        w *= np.where(dur > 20, 1.2,
             np.where(dur < 3, 0.8, 1.0))

    return w.clip(0.1, 5.0)


# ============================================================================
# Main
# ============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Import real MT5 trade CSV and create ML training data"
    )
    parser.add_argument("--csv", "-i", required=True,
                        help="Path to MT5 trade export CSV (PASR_trades_export.csv)")
    parser.add_argument("--ohlcv", required=True,
                        help="Path to MT5 OHLCV export CSV (PASR_ohlcv_export.csv)")
    parser.add_argument("--output", "-o",
                        default="output/MT5_Training_Data.csv",
                        help="Output training CSV path")
    parser.add_argument("--symbol", default="EURUSD",
                        help="Trading symbol (for metadata)")
    parser.add_argument("--timeframe", default="H1",
                        help="Timeframe (for metadata)")
    parser.add_argument("--max-time-diff", type=float, default=90.0,
                        help="Max minutes between trade entry and nearest OHLCV bar")
    args = parser.parse_args()

    print("=" * 60)
    print("PASR MT5 Trade Data Importer (Real Data Only)")
    print("=" * 60)

    # 1. Load trades
    print("\n[1/3] Loading MT5 trade export...")
    df_trades = load_mt5_csv(args.csv)

    # 2. Load OHLCV (required, no synthetic fallback)
    print("\n[2/3] Loading OHLCV market data...")
    df_ohlcv = load_ohlcv_csv(args.ohlcv)

    # Validate date coverage
    trade_start = df_trades['entry_time'].min()
    trade_end = df_trades['entry_time'].max()
    ohlcv_start = df_ohlcv['timestamp'].min()
    ohlcv_end = df_ohlcv['timestamp'].max()

    if ohlcv_start > trade_start - timedelta(days=5):
        print(f"  WARNING: OHLCV starts {ohlcv_start.date()} but trades start "
              f"{trade_start.date()}. Need ≥5 days warmup.")
    if ohlcv_end < trade_end:
        print(f"  WARNING: OHLCV ends {ohlcv_end.date()} but trades go until "
              f"{trade_end.date()}. Some late trades may be unmatched.")

    # 3. Compute features and match trades
    print("\n[3/3] Computing features and creating training data...")
    config = GeneratorConfig(
        total_bars=len(df_ohlcv),
        symbol=args.symbol,
        timeframe=args.timeframe,
        base_price=float(df_ohlcv['close'].iloc[0]),
    )

    df_train = compute_features_at_entries(
        df_ohlcv, df_trades, config,
        max_time_diff_min=args.max_time_diff
    )

    # 4. Save
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df_train.to_csv(str(out_path), index=False)

    print(f"\nTraining data saved to {out_path}")
    print(f"  Total samples: {len(df_train)}")
    print(f"  Win rate: {(df_train['label'] > 0).mean()*100:.1f}%")

    print(f"\nNext step:")
    print(f"  python3 training/train_mlp_classifier.py \\")
    print(f"    --csv {out_path} --out output --epochs 300")

    return 0


if __name__ == "__main__":
    sys.exit(main())
