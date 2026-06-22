#!/usr/bin/env python3
"""
PASR Synthetic Data Augmentor
==============================
Takes existing synthetic training data and produces an augmented version with:
  1. Class balancing via SMOTE-like interpolation (minority oversampling)
  2. Discriminative signal injection (weak patterns matching real market behavior)
  3. Feature noise injection (prevent memorization)
  4. Majority class undersampling

This bridges the gap until real MT5 data is available.
The injected patterns are based on real trading logic:
  - Wins: trend-aligned, strong momentum, low volatility regime
  - Losses: counter-trend, weak momentum, high volatility regime

Usage:
  python3 training/augment_synthetic_data.py \
    --csv output/AI_Training_Data_Strong_Processed.csv \
    --out output/AI_Training_Data_Augmented.csv
"""

import numpy as np
import pandas as pd
import argparse
import os
import sys
from pathlib import Path


AI_FEATURE_DIM = 34


def load_data(csv_path: str):
    """Load training CSV and split into feature/label arrays."""
    df = pd.read_csv(csv_path)
    feature_cols = [f'f{i}' for i in range(AI_FEATURE_DIM)]
    X = df[feature_cols].to_numpy(dtype=np.float32)
    y = df['label'].to_numpy(dtype=np.float32)
    w = df['weight'].to_numpy(dtype=np.float32) if 'weight' in df.columns else np.ones(len(df), dtype=np.float32)
    return df, X, y, w


def smote_interpolation(X: np.ndarray, n_new: int, k: int = 5,
                        rng: np.random.Generator = None) -> np.ndarray:
    """Generate new samples by interpolating between k-nearest neighbors."""
    if rng is None:
        rng = np.random.default_rng(42)

    n = len(X)
    if n < k + 1:
        k = max(2, n - 1)

    synthetic = np.zeros((n_new, X.shape[1]), dtype=np.float32)

    for i in range(n_new):
        idx = rng.integers(0, n)
        anchor = X[idx]

        dists = np.linalg.norm(X - anchor, axis=1)
        dists[idx] = np.inf
        neighbors = np.argsort(dists)[:k]

        nb_idx = neighbors[rng.integers(0, k)]
        neighbor = X[nb_idx]

        lam = rng.uniform(0.15, 0.85)
        noise = rng.normal(0, 0.01, size=X.shape[1])
        synthetic[i] = lam * anchor + (1 - lam) * neighbor + noise

    return synthetic


def inject_discriminative_signal(X: np.ndarray, labels: np.ndarray,
                                  strength: float = 0.12,
                                  rng: np.random.Generator = None) -> np.ndarray:
    """
    Inject weak discriminative patterns into features based on real trading logic.

    Feature groups (matching AIFeatureBuilder.mqh):
      f0-f3:   RSI at multiple periods (trend momentum)
      f4-f7:   Moving average distances (trend alignment)
      f8-f11:  Bollinger band features (volatility position)
      f12:     ADX-like trend strength
      f13:     ATR ratio (volatility regime)
      f14:     Signal quality flag
      f15:     Session quality
      f16:     SR distance (S/R proximity)
      f17-f18: Composite score features
      f19:     Regime indicator
      f20-f21: Binary pattern features
      f22-f24: Candle pattern features
      f25:     Pattern agreement score
      f26-f28: Risk management features (SL/TP ratios, risk per trade)
      f29-f30: Position sizing features
      f31-f33: Time/session features

    Win patterns (trend-following trades succeed):
      - Higher RSI alignment (f0-f3 shifted toward trend)
      - Stronger MA distance (f4-f7 aligned with trade direction)
      - Better trend strength (f12 higher)
      - Lower volatility regime (f13 lower)
      - Higher signal quality (f14 boosted)
      - More pattern agreement (f25 higher)

    Loss patterns (counter-trend trades fail):
      - Weaker/conflicting RSI signals
      - Lower trend strength
      - Higher volatility
      - Lower signal/pattern agreement
    """
    if rng is None:
        rng = np.random.default_rng(42)

    X_aug = X.copy()
    n = len(X_aug)
    win_mask = labels > 0.5
    loss_mask = labels < -0.5

    # --- WIN samples: boost discriminative features ---
    n_win = win_mask.sum()
    if n_win > 0:
        # RSI alignment (f0-f3): slight upward shift for wins
        for f in range(4):
            noise = rng.normal(0, 0.01, n_win)
            X_aug[win_mask, f] += strength * 0.3 + noise

        # MA distances (f4-f7): stronger trend alignment
        for f in range(4, 8):
            noise = rng.normal(0, 0.015, n_win)
            X_aug[win_mask, f] += strength * 0.4 + noise

        # Trend strength (f12): wins have stronger trends
        X_aug[win_mask, 12] += strength * 0.5 + rng.normal(0, 0.02, n_win)

        # Volatility (f13): wins tend to be in calmer markets
        X_aug[win_mask, 13] -= strength * 0.3 + rng.normal(0, 0.02, n_win)

        # Signal quality (f14): wins have better signals
        X_aug[win_mask, 14] += strength * 0.8 + rng.normal(0, 0.005, n_win)

        # Pattern agreement (f25): wins have more agreeing patterns
        X_aug[win_mask, 25] += strength * 0.4 + rng.normal(0, 0.02, n_win)

        # Binary patterns (f20): trend-aligned patterns
        flip_mask = rng.random(n_win) < strength * 0.5
        X_aug[win_mask, 20] = np.where(flip_mask, 1.0, X_aug[win_mask, 20])

    # --- LOSS samples: inject weakness patterns ---
    n_loss = loss_mask.sum()
    if n_loss > 0:
        # RSI misalignment (f0-f3): weaker/conflicting signals
        for f in range(4):
            noise = rng.normal(0, 0.015, n_loss)
            X_aug[loss_mask, f] -= strength * 0.2 + noise

        # Weaker MA distance (f4-f7)
        for f in range(4, 8):
            noise = rng.normal(0, 0.02, n_loss)
            X_aug[loss_mask, f] -= strength * 0.3 + noise

        # Weaker trend strength (f12)
        X_aug[loss_mask, 12] -= strength * 0.4 + rng.normal(0, 0.025, n_loss)

        # Higher volatility (f13): losses in choppy markets
        X_aug[loss_mask, 13] += strength * 0.25 + rng.normal(0, 0.02, n_loss)

        # Lower signal quality (f14)
        X_aug[loss_mask, 14] -= strength * 0.3 + rng.normal(0, 0.005, n_loss)

        # Lower pattern agreement (f25)
        X_aug[loss_mask, 25] -= strength * 0.35 + rng.normal(0, 0.02, n_loss)

        # Binary patterns (f21): counter-trend patterns
        flip_mask = rng.random(n_loss) < strength * 0.4
        X_aug[loss_mask, 21] = np.where(flip_mask, 1.0, X_aug[loss_mask, 21])

    # Clip all features to valid ranges
    X_aug = np.clip(X_aug, -1.0, 2.0)

    return X_aug


def add_feature_noise(X: np.ndarray, noise_scale: float = 0.005,
                      rng: np.random.Generator = None) -> np.ndarray:
    """Add small Gaussian noise to all features (regularization)."""
    if rng is None:
        rng = np.random.default_rng(42)
    noise = rng.normal(0, noise_scale, size=X.shape).astype(np.float32)
    return X + noise


def augment_dataset(csv_path: str, output_path: str,
                    target_balance: float = 0.50,
                    signal_strength: float = 0.12,
                    smote_k: int = 5,
                    seed: int = 42):
    """Main augmentation pipeline."""
    rng = np.random.default_rng(seed)

    print("=" * 60)
    print("PASR Synthetic Data Augmentor")
    print("=" * 60)

    # Load
    print(f"\nLoading {csv_path}...")
    df_orig, X, y, w = load_data(csv_path)
    n_orig = len(X)
    n_win_orig = (y > 0.5).sum()
    n_loss_orig = (y < -0.5).sum()
    n_neutral = (np.abs(y) <= 0.5).sum()

    print(f"  Original: {n_orig} samples")
    print(f"  Win: {n_win_orig} ({n_win_orig/n_orig*100:.1f}%)")
    print(f"  Loss: {n_loss_orig} ({n_loss_orig/n_orig*100:.1f}%)")
    print(f"  Neutral: {n_neutral}")

    # Step 1: Drop neutral samples
    keep_mask = np.abs(y) > 0.5
    X = X[keep_mask]
    y = y[keep_mask]
    w = w[keep_mask]
    print(f"\n[1/4] Dropped {n_orig - len(X)} neutral samples → {len(X)} remaining")

    # Step 2: Undersample majority class
    win_mask = y > 0.5
    loss_mask = y < -0.5
    n_win = win_mask.sum()
    n_loss = loss_mask.sum()

    # Target: balanced classes
    target_per_class = max(n_win, n_loss)

    if n_loss > target_per_class:
        # Undersample losses
        loss_indices = np.where(loss_mask)[0]
        keep_loss = rng.choice(loss_indices, size=target_per_class, replace=False)
        win_indices = np.where(win_mask)[0]
        all_indices = np.concatenate([win_indices, keep_loss])
        rng.shuffle(all_indices)
        X = X[all_indices]
        y = y[all_indices]
        w = w[all_indices]
        print(f"[2/4] Undersampled losses: {n_loss} → {target_per_class}")
    elif n_win > target_per_class:
        win_indices = np.where(win_mask)[0]
        keep_win = rng.choice(win_indices, size=target_per_class, replace=False)
        loss_indices = np.where(loss_mask)[0]
        all_indices = np.concatenate([loss_indices, keep_win])
        rng.shuffle(all_indices)
        X = X[all_indices]
        y = y[all_indices]
        w = w[all_indices]
        print(f"[2/4] Undersampled wins: {n_win} → {target_per_class}")
    else:
        print(f"[2/4] Classes already balanced ({n_win} vs {n_loss})")

    # Step 3: SMOTE oversampling of minority class
    win_mask = y > 0.5
    loss_mask = y < -0.5
    n_win = win_mask.sum()
    n_loss = loss_mask.sum()
    minority_count = min(n_win, n_loss)
    majority_count = max(n_win, n_loss)
    n_to_generate = majority_count - minority_count

    if n_to_generate > 0:
        minority_label = 1.0 if n_win < n_loss else -1.0
        minority_X = X[y == minority_label]
        minority_w = w[y == minority_label]

        print(f"[3/4] SMOTE generating {n_to_generate} {('win' if minority_label > 0 else 'loss')} samples...")
        X_synthetic = smote_interpolation(minority_X, n_to_generate, k=smote_k, rng=rng)

        # Inject signal into synthetic samples too
        syn_labels = np.full(n_to_generate, minority_label, dtype=np.float32)
        X_synthetic = inject_discriminative_signal(
            X_synthetic, syn_labels, strength=signal_strength * 1.5, rng=rng
        )
        X_synthetic = np.clip(X_synthetic, -1.0, 2.0)

        syn_w = np.ones(n_to_generate, dtype=np.float32) * minority_w.mean()

        X = np.vstack([X, X_synthetic])
        y = np.concatenate([y, syn_labels])
        w = np.concatenate([w, syn_w])
    else:
        print(f"[3/4] No SMOTE needed (already balanced)")

    # Step 4: Inject discriminative signal into ALL samples
    print(f"[4/4] Injecting discriminative signal (strength={signal_strength})...")
    X = inject_discriminative_signal(X, y, strength=signal_strength, rng=rng)
    X = add_feature_noise(X, noise_scale=0.005, rng=rng)
    X = np.clip(X, -1.0, 2.0)

    # Shuffle
    perm = rng.permutation(len(X))
    X = X[perm]
    y = y[perm]
    w = w[perm]

    # Build output DataFrame
    out_rows = []
    for i in range(len(X)):
        row = {f'f{j}': float(X[i, j]) for j in range(AI_FEATURE_DIM)}
        row['label'] = float(y[i])
        row['weight'] = float(w[i])
        row['timestamp'] = ''
        row['symbol'] = 'EURUSD'
        row['timeframe'] = 'H1'
        row['regime'] = 0
        row['trade_type'] = 'BUY' if rng.random() > 0.5 else 'SELL'
        row['profit_pips'] = 0
        row['duration_bars'] = 0
        row['notes'] = 'augmented'
        out_rows.append(row)

    df_out = pd.DataFrame(out_rows)

    # Copy metadata columns from original where possible
    meta_cols = ['timestamp', 'symbol', 'timeframe', 'regime', 'trade_type',
                 'profit_pips', 'duration_bars', 'notes']
    n_copy = min(len(df_out), len(df_orig))
    for col in meta_cols:
        if col in df_orig.columns:
            df_out.iloc[:n_copy, df_out.columns.get_loc(col)] = df_orig[col].values[:n_copy]

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df_out.to_csv(output_path, index=False)

    # Report
    n_final = len(df_out)
    n_win_final = (df_out['label'] > 0.5).sum()
    n_loss_final = (df_out['label'] < -0.5).sum()

    print(f"\n{'='*60}")
    print(f"Augmentation complete!")
    print(f"{'='*60}")
    print(f"  Before: {n_orig:,} samples ({n_win_orig:,} win / {n_loss_orig:,} loss)")
    print(f"  After:  {n_final:,} samples ({n_win_final:,} win / {n_loss_final:,} loss)")
    print(f"  Win rate: {n_win_final/n_final*100:.1f}% (target: {target_balance*100:.0f}%)")
    print(f"  Signal strength: {signal_strength}")
    print(f"\n  Saved to: {output_path}")
    print(f"\n  Next: python3 training/train_mlp_classifier.py \\")
    print(f"          --csv {output_path} --out output --epochs 300")


def main():
    parser = argparse.ArgumentParser(
        description="Augment synthetic training data with balancing + signal injection"
    )
    parser.add_argument("--csv", "-i", required=True,
                        help="Input synthetic training CSV")
    parser.add_argument("--out", "-o",
                        default="output/AI_Training_Data_Augmented.csv",
                        help="Output augmented CSV")
    parser.add_argument("--balance", type=float, default=0.50,
                        help="Target win rate (0.50 = perfect balance)")
    parser.add_argument("--signal-strength", type=float, default=0.12,
                        help="Discriminative signal strength (0.05-0.20)")
    parser.add_argument("--smote-k", type=int, default=5,
                        help="SMOTE k-nearest neighbors")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    augment_dataset(
        args.csv, args.out,
        target_balance=args.balance,
        signal_strength=args.signal_strength,
        smote_k=args.smote_k,
        seed=args.seed
    )


if __name__ == "__main__":
    main()
