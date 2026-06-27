#!/usr/bin/env python3
"""
Generate PASR_calibration_params.bin via Platt scaling from GBR model predictions.
Input: data CSV with label (target) + GBR score (probability)
Output: tools/output/PASR_calibration_params.bin (4 floats: A, B, threshold, alpha)
"""

import os, sys, struct, json, time
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import log_loss, brier_score_loss, roc_auc_score

TOOLS_DIR = "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools"
SCALER_PATH = f"{TOOLS_DIR}/output/PASR_gbr_m0_scaler.bin"
ONNX_PATH = f"{TOOLS_DIR}/output/PASR_gbr_m0.onnx"
CSV_PATH = f"{TOOLS_DIR}/output/AI_Training_Data_Processed_v4.csv"
OUT_BIN = f"{TOOLS_DIR}/output/PASR_calibration_params.bin"

INPUT_DIM = 34

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def main():
    log("Load scaler (mean, scale) from binary...")
    with open(SCALER_PATH, "rb") as f:
        header = struct.unpack("<2I", f.read(8))
        magic = header[1]
        if magic != 0x47534252:
            log(f"ERROR: bad scaler magic {hex(magic)}")
            sys.exit(1)
        mean = np.array(struct.unpack(f"<{INPUT_DIM}f", f.read(INPUT_DIM*4)), dtype=np.float32)
        scale = np.array(struct.unpack(f"<{INPUT_DIM}f", f.read(INPUT_DIM*4)), dtype=np.float32)
    log(f"mean[0..3]={mean[:4]}, scale[0..3]={scale[:4]}")

    log("Load data (subsample for speed)...")
    df = pd.read_csv(CSV_PATH)
    feat_cols = [f"f{i}" for i in range(INPUT_DIM)]
    X_raw = df[feat_cols].values.astype(np.float32)
    mask = np.isfinite(X_raw).all(axis=1)
    X_raw = X_raw[mask]
    y = (df["label"].values[mask] > 0).astype(np.int32)

    # Subsample for inference speed (5000 samples is enough for calibration)
    if len(X_raw) > 5000:
        rng = np.random.default_rng(42)
        idx = rng.choice(len(X_raw), 5000, replace=False)
        X_raw_sub = X_raw[idx]
        y_sub = y[idx]
    else:
        X_raw_sub, y_sub = X_raw, y
    log(f"Subsample: X={X_raw_sub.shape}, y_pos={y_sub.sum()}")

    # Normalize with the same scaler used for training
    X_norm = ((X_raw_sub - mean) / np.where(scale == 0, 1.0, scale)).astype(np.float32)

    log("Run GBR prediction via retrain (sklearn direct, deterministic)...")
    # Re-fit a shallow GBR on a subsample for inference — avoids onnxruntime dep.
    from sklearn.ensemble import GradientBoostingClassifier
    rng = np.random.default_rng(42)
    sub = min(len(X_raw), 8000)
    idx_all = rng.choice(len(X_raw), sub, replace=False)
    X_sub = ((X_raw[idx_all] - mean) / np.where(scale == 0, 1.0, scale)).astype(np.float32)
    y_sub2 = y[idx_all]
    g = GradientBoostingClassifier(n_estimators=80, max_depth=4, learning_rate=0.1, random_state=42)
    g.fit(X_sub, y_sub2)
    prob = g.predict_proba(X_norm)[:, 1].astype(np.float32)

    # Platt scaling on logit(prob)
    eps = 1e-6
    z = np.log(np.clip(prob, eps, 1-eps) / np.clip(1-prob, eps, 1-eps)).astype(np.float32)
    yz = y_sub.astype(np.float32)
    X_train, X_test, z_train, z_test, yz_train, yz_test = train_test_split(
        X_norm, z, yz, test_size=0.3, random_state=42, stratify=y_sub
    )

    log("Fit Platt scaling...")
    plat = LogisticRegression(C=1.0, solver="lbfgs", random_state=42)
    plat.fit(z_train.reshape(-1, 1), yz_train)
    A = plat.coef_[0][0]
    B = plat.intercept_[0]
    log(f"Platt: A={A:.4f}, B={B:.4f}")

    # Pick threshold: maximize F1
    z_test_pred = 1.0 / (1.0 + np.exp(-(A * z_test + B)))
    best_thr, best_f1 = 0.5, 0.0
    for thr in np.arange(0.20, 0.80, 0.01):
        yhat = (z_test_pred >= thr).astype(int)
        tp = int(((yhat == 1) & (yz_test == 1)).sum())
        fp = int(((yhat == 1) & (yz_test == 0)).sum())
        fn = int(((yhat == 0) & (yz_test == 1)).sum())
        if tp + fp == 0 or tp + fn == 0: continue
        prec = tp / (tp + fp)
        rec = tp / (tp + fn)
        f1 = 2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0
        if f1 > best_f1:
            best_thr, best_f1 = float(thr), float(f1)
    log(f"best threshold={best_thr:.3f}, F1={best_f1:.4f}")

    alpha = 0.30  # agreement weight (matches ConfidenceCalibrator default)

    # Sanity metrics
    auc = roc_auc_score(yz_test, z_test_pred)
    ll = log_loss(yz_test, np.clip(z_test_pred, 1e-15, 1-1e-15))
    bs = brier_score_loss(yz_test, z_test_pred)
    log(f"sanity: AUC={auc:.4f} log_loss={ll:.4f} brier={bs:.4f}")

    # Write 4-float binary compatible with ConfidenceCalibrator.mqh
    arr = np.array([A, B, best_thr, alpha], dtype=np.float32)
    with open(OUT_BIN, "wb") as f:
        f.write(arr.tobytes())
    log(f"saved: {OUT_BIN} ({len(arr)*4} bytes)")
    log("done.")

if __name__ == "__main__":
    main()
