#!/usr/bin/env python3
"""
Train GBR for PASR — exports ONNX + scaler params.
Input: tools/output/AI_Training_Data_Processed_v4.csv (real MT5 EURUSD H1 2020-2025)
Output:
  - tools/output/PASR_gbr_m0.onnx            (binary classification: BUY vs NON-BUY)
  - tools/output/PASR_gbr_m0_scaler.bin     (mean[34] + scale[34] for input normalization)
  - tools/output/gbr_metrics.json
"""

import os, sys, struct, json, time
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score, confusion_matrix
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

TOOLS_DIR = "/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools"
CSV_PATH = f"{TOOLS_DIR}/output/AI_Training_Data_Processed_v4.csv"
OUT_DIR = f"{TOOLS_DIR}/output"
INPUT_DIM = 34

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def main():
    log("Load dataset...")
    df = pd.read_csv(CSV_PATH)
    log(f"rows={len(df)}, cols={list(df.columns[:5])}...")

    feat_cols = [f"f{i}" for i in range(INPUT_DIM)]
    for c in feat_cols:
        if c not in df.columns:
            log(f"ERROR: missing feature column {c}")
            sys.exit(1)

    X = df[feat_cols].values.astype(np.float32)

    # Binary label: BUY (1) vs not-BUY (0), so we merge label=0 (NEUTRAL) with SELL (-1)
    y = (df["label"].values > 0).astype(np.int32)

    # Pure tradeoff: drop rows where any feature is NaN / Inf
    mask = np.isfinite(X).all(axis=1)
    X, y = X[mask], y[mask]
    log(f"after nan/inf drop: X={X.shape}, BUY={y.sum()}, non-BUY={(1-y).sum()}")

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.20, random_state=42, stratify=y
    )
    log(f"train={len(X_train)} test={len(X_test)}")

    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train).astype(np.float32)
    X_test_s = scaler.transform(X_test).astype(np.float32)

    log("Fit GBR (n_estimators=120, max_depth=4)...")
    t0 = time.time()
    gbr = GradientBoostingClassifier(
        n_estimators=120,
        max_depth=4,
        learning_rate=0.08,
        subsample=0.8,
        random_state=42,
    )
    gbr.fit(X_train_s, y_train)
    log(f"fit done in {time.time()-t0:.1f}s")

    y_prob = gbr.predict_proba(X_test_s)[:, 1]
    y_pred = (y_prob >= 0.5).astype(np.int32)
    acc = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, zero_division=0)
    auc = roc_auc_score(y_test, y_prob)
    tn, fp, fn, tp = confusion_matrix(y_test, y_pred).ravel()
    log(f"acc={acc:.4f} f1={f1:.4f} auc={auc:.4f} TP={tp} TN={tn} FP={fp} FN={fn}")

    # Export ONNX
    log("Sklearn => ONNX...")
    initial_type = [("features", FloatTensorType([None, INPUT_DIM]))]
    onnx_model = convert_sklearn(gbr, initial_types=initial_type, target_opset=12)
    onnx_path = f"{OUT_DIR}/PASR_gbr_m0.onnx"
    with open(onnx_path, "wb") as f:
        f.write(onnx_model.SerializeToString())
    log(f"ONNX saved: {onnx_path} ({os.path.getsize(onnx_path)/1024:.0f} KB)")

    # Export scaler (mean, scale) — needed because GBR trained on standardized inputs.
    scaler_path = f"{OUT_DIR}/PASR_gbr_m0_scaler.bin"
    mean = scaler.mean_.astype(np.float32)
    scale = scaler.scale_.astype(np.float32)
    with open(scaler_path, "wb") as f:
        # Header: 2 float32 dims hint then data
        f.write(struct.pack("<2I", INPUT_DIM, 0x47534252))  # magic 'GSBR'
        f.write(struct.pack(f"<{INPUT_DIM}f", *mean))
        f.write(struct.pack(f"<{INPUT_DIM}f", *scale))
    log(f"Scaler saved: {scaler_path} ({INPUT_DIM*2*4} bytes)")

    with open(f"{OUT_DIR}/gbr_metrics.json", "w") as f:
        json.dump({
            "model": "GBR",
            "n_estimators": 120,
            "max_depth": 4,
            "lr": 0.08,
            "subsample": 0.8,
            "input_dim": INPUT_DIM,
            "acc": float(acc), "f1": float(f1), "auc": float(auc),
            "tp": int(tp), "tn": int(tn), "fp": int(fp), "fn": int(fn),
            "rows_total": int(len(X)),
            "rows_train": int(len(X_train)),
            "rows_test": int(len(X_test)),
            "label_distribution": {"buy": int(y.sum()), "not_buy": int((1-y).sum())},
        }, f, indent=2)

    log("done.")

if __name__ == "__main__":
    main()
