#!/usr/bin/env python3
"""
train_mlp.py — Train PASR MLP weights for AIInference.mqh
==========================================================

Input CSV format:
  f0..f33,label,weight(optional),timestamp/symbol/etc(optional)

Output files:
  PASR_mlp_m0.bin, PASR_mlp_m1.bin  -> copy to MT5 MQL5/Files/
  mlp_training_report.json          -> quick metrics and metadata

Binary layout, float32, row-major:
  [input_dim, hidden1, hidden2, output_dim,
   w1[input_dim][hidden1], b1[hidden1],
   w2[hidden1][hidden2], b2[hidden2],
   w3[hidden2], b3]

This matches Include/PASR/AI/AIInference.mqh::LoadWeights().
"""

from __future__ import annotations

import argparse
import json
import os
import struct
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPRegressor

INPUT_DIM = 34
HIDDEN1 = 64
HIDDEN2 = 32
OUTPUT_DIM = 1
DEFAULT_SEEDS = [42, 137]


def feature_columns(df: pd.DataFrame) -> list[str]:
    cols = [f"f{i}" for i in range(INPUT_DIM)]
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise ValueError(f"Missing feature columns: {missing}")
    return cols


def load_dataset(path: str) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    df = pd.read_csv(path, comment="#")
    cols = feature_columns(df)
    if "label" not in df.columns:
        raise ValueError("CSV must contain a 'label' column with values in [-1, 1]")

    X = df[cols].apply(pd.to_numeric, errors="coerce").fillna(0.0).to_numpy(np.float32)
    y = pd.to_numeric(df["label"], errors="coerce").fillna(0.0).to_numpy(np.float32)
    y = np.clip(y, -1.0, 1.0)

    if "weight" in df.columns:
        w = pd.to_numeric(df["weight"], errors="coerce").fillna(1.0).to_numpy(np.float32)
        w = np.clip(w, 0.1, 5.0)
    else:
        w = np.ones(len(df), dtype=np.float32)

    if len(X) < 50:
        raise ValueError(f"Only {len(X)} samples found; collect at least 50, preferably 500+")
    return X, y, w


def train_one_model(X: np.ndarray, y: np.ndarray, w: np.ndarray, seed: int) -> tuple[MLPRegressor, dict]:
    split = train_test_split(X, y, w, test_size=0.2, shuffle=False)
    X_train, X_test, y_train, y_test, w_train, w_test = split

    model = MLPRegressor(
        hidden_layer_sizes=(HIDDEN1, HIDDEN2),
        activation="relu",
        solver="adam",
        alpha=1e-4,
        batch_size="auto",
        learning_rate_init=1e-3,
        max_iter=500,
        early_stopping=True,
        validation_fraction=0.15,
        n_iter_no_change=25,
        random_state=seed,
        verbose=False,
    )
    model.fit(X_train, y_train)

    pred = np.clip(model.predict(X_test), -1.0, 1.0)
    metrics = {
        "seed": seed,
        "n_train": int(len(X_train)),
        "n_test": int(len(X_test)),
        "mae": float(mean_absolute_error(y_test, pred, sample_weight=w_test)),
        "mse": float(mean_squared_error(y_test, pred, sample_weight=w_test)),
        "r2": float(r2_score(y_test, pred, sample_weight=w_test)) if len(set(np.round(y_test, 6))) > 1 else None,
        "iterations": int(model.n_iter_),
        "loss": float(model.loss_),
    }
    return model, metrics


def export_mql5_weights(model: MLPRegressor, path: str) -> None:
    if len(model.coefs_) != 3 or len(model.intercepts_) != 3:
        raise ValueError("Unexpected MLP shape; expected 34->64->32->1")

    w1, w2, w3 = model.coefs_
    b1, b2, b3 = model.intercepts_
    expected = ((INPUT_DIM, HIDDEN1), (HIDDEN1, HIDDEN2), (HIDDEN2, OUTPUT_DIM))
    actual = (w1.shape, w2.shape, w3.shape)
    if actual != expected:
        raise ValueError(f"Unexpected MLP shape {actual}, expected {expected}")

    values: list[float] = [float(INPUT_DIM), float(HIDDEN1), float(HIDDEN2), float(OUTPUT_DIM)]
    values.extend(w1.astype(np.float32).ravel(order="C"))
    values.extend(b1.astype(np.float32))
    values.extend(w2.astype(np.float32).ravel(order="C"))
    values.extend(b2.astype(np.float32))
    values.extend(w3[:, 0].astype(np.float32))
    values.append(float(b3[0]))

    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack(f"{len(values)}f", *values))
    print(f"[train_mlp] wrote {path} ({len(values)} float32 values)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Train PASR MLP weights for MQL5 AIInference.mqh")
    parser.add_argument("--csv", required=True, help="Training CSV with f0..f33,label[,weight]")
    parser.add_argument("--out", default="output", help="Output directory")
    parser.add_argument("--seeds", default=",".join(map(str, DEFAULT_SEEDS)), help="Comma-separated seeds/models")
    args = parser.parse_args()

    X, y, w = load_dataset(args.csv)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_csv": os.path.abspath(args.csv),
        "shape": [INPUT_DIM, HIDDEN1, HIDDEN2, OUTPUT_DIM],
        "models": [],
    }

    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]
    for idx, seed in enumerate(seeds):
        model, metrics = train_one_model(X, y, w, seed)
        file_name = out_dir / f"PASR_mlp_m{idx}.bin"
        export_mql5_weights(model, str(file_name))
        metrics["file"] = file_name.name
        report["models"].append(metrics)

    report_path = out_dir / "mlp_training_report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"[train_mlp] report -> {report_path}")
    print("[train_mlp] copy PASR_mlp_m*.bin to MT5/MQL5/Files/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
