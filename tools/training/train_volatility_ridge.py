#!/usr/bin/env python3
"""
PASR Volatility Ridge Predictor
================================
Predicts future realized volatility using persistence + feature aggregates.
Uses Ridge regression (fast, interpretable, deployable).

Features:
  - persistence: y[t-1] (realized vol over previous forecast window)
  - last bar features: 34 features at bar t
  - aggregate features: mean + std of 34 features over lookback window

Usage:
  python3 train_volatility_ridge.py --npz output/volatility_h1_seqs16.npz --out output
"""
import numpy as np
import json, os, sys, struct
from pathlib import Path
from datetime import datetime, timezone
from sklearn.linear_model import RidgeCV
from sklearn.preprocessing import StandardScaler

def flatten_sequences(X_seq):
    """Extract prediction features from sequence."""
    X_last = X_seq[:, -1, :]
    X_mean = X_seq.mean(axis=1)
    X_std = X_seq.std(axis=1)
    return np.column_stack([X_last, X_mean, X_std]).astype(np.float32)

def add_persistence(X_flat, y):
    """Add y[t-1] as a feature."""
    return np.column_stack([y[:-1], X_flat[1:]])

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Volatility Ridge Predictor")
    parser.add_argument("--npz", required=True)
    parser.add_argument("--out", default="output")
    parser.add_argument("--alpha", type=float, default=None,
                        help="Ridge alpha (default: CV search)")
    args = parser.parse_args()

    print("=" * 60)
    print("PASR Volatility Ridge Predictor")
    print("=" * 60)

    d = args.out
    print(f"\nLoading {args.npz}...")
    data = np.load(args.npz)
    X_seq, y = data['X'], data['y']
    print(f"X: {X_seq.shape}, y: {y.shape}")

    # Time split (80/20)
    n = len(y)
    split = int(n * 0.8)

    # Align: features at t predict y[t] (vol over [t+1, t+8])
    y_cur = y[1:]  # y[t]
    y_prev = y[:-1]  # y[t-1]

    X_flat = flatten_sequences(X_seq)
    X_full = add_persistence(X_flat, y)

    X_train = X_full[:split-1]
    y_train = y_cur[:split-1]
    X_test = X_full[split-1:-1]
    y_test = y_cur[split-1:-1]

    print(f"Train: {len(X_train)}, Test: {len(X_test)}")
    print(f"Features: {X_train.shape[1]} (1 persistence + 102 feature agg)")

    # Normalize
    scaler = StandardScaler()
    Xn_train = scaler.fit_transform(X_train)
    Xn_test = scaler.transform(X_test)

    # Train Ridge
    from sklearn.linear_model import Ridge
    if args.alpha:
        model = Ridge(alpha=args.alpha)
        model.fit(Xn_train, y_train)
    else:
        from sklearn.linear_model import RidgeCV
        alphas = np.logspace(-1, 3, 9)
        model = RidgeCV(alphas=alphas, scoring='neg_mean_squared_error', cv=5)
        model.fit(Xn_train, y_train)

    pred_train = model.predict(Xn_train)
    pred_test = model.predict(Xn_test)

    train_mse = np.mean((pred_train - y_train) ** 2)
    test_mse = np.mean((pred_test - y_test) ** 2)
    test_mae = np.mean(np.abs(pred_test - y_test))

    # Baselines
    base_mean = np.full_like(y_test, y_train.mean())
    base_mse = np.mean((base_mean - y_test) ** 2)
    base_persist = y_prev[split-1:-1]  # y[t-1] as prediction for y[t]
    base_p_mse = np.mean((base_persist - y_test) ** 2)

    r2_mean = 1 - test_mse / base_mse
    r2_persist = 1 - test_mse / base_p_mse

    # Top/bottom decile spread
    top_k = max(len(pred_test) // 10, 1)
    top_idx = np.argsort(-pred_test)[:top_k]
    bot_idx = np.argsort(pred_test)[:top_k]
    top_realized = y_test[top_idx].mean()
    bot_realized = y_test[bot_idx].mean()
    spread = top_realized / max(bot_realized, 1e-15)

    corr = float(np.corrcoef(pred_test, y_test)[0, 1])

    print(f"\n  Results:")
    print(f"  Ridge(alpha={model.alpha if hasattr(model, 'alpha') else model.alpha_:.3f})")
    print(f"  Train MSE: {train_mse:.3e}")
    print(f"  Test MSE:  {test_mse:.3e}")
    print(f"  Test MAE:  {test_mae:.3e}")
    print(f"  Pearson r: {corr:.4f}")
    print(f"  R² vs mean:     {r2_mean:.4f}")
    print(f"  R² vs persist:  {r2_persist:.4f}")
    print(f"  Top10 vol: {top_realized:.3e}")
    print(f"  Bot10 vol: {bot_realized:.3e}")
    print(f"  Spread: {spread:.3f}x")

    # Export model
    out_dir = Path(d)
    out_dir.mkdir(parents=True, exist_ok=True)

    export_path = out_dir / "PASR_vol_ridge.bin"
    export_model(model, scaler, str(export_path))
    print(f"\nExported: {export_path}")

    alpha_val = float(model.alpha) if hasattr(model, 'alpha') else float(model.alpha_)
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_npz": os.path.abspath(args.npz),
        "type": "volatility_ridge",
        "model": "Ridge(alpha={:.3f})".format(alpha_val),
        "alpha": alpha_val,
        "n_features": X_train.shape[1],
        "n_train": len(X_train),
        "n_test": len(X_test),
        "train_mse": float(train_mse),
        "test_mse": float(test_mse),
        "test_mae": float(test_mae),
        "pearson_r": corr,
        "r2_vs_mean": float(r2_mean),
        "r2_vs_persist": float(r2_persist),
        "top10_vol": float(top_realized),
        "bottom10_vol": float(bot_realized),
        "spread_ratio": float(spread),
    }

    report_path = out_dir / "volatility_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"Report: {report_path}")

def export_model(model, scaler, path):
    """Export Ridge model + scaler to binary for MQL5 inference."""
    w = model.coef_.astype(np.float32)
    b = np.array([model.intercept_], dtype=np.float32)
    mu = scaler.mean_.astype(np.float32)
    sig = scaler.scale_.astype(np.float32)

    header = np.array([len(w)], dtype=np.int32)
    with open(path, 'wb') as f:
        f.write(header.tobytes())
        f.write(w.tobytes())
        f.write(b.tobytes())
        f.write(mu.tobytes())
        f.write(sig.tobytes())

    n_floats = 1 + len(w) + 1 + len(mu) + len(sig)
    print(f"  Exported {n_floats} floats (int32 header + coefs + bias + norm params)")

if __name__ == '__main__':
    main()
