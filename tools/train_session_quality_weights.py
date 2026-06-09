#!/usr/bin/env python3
"""
train_session_quality_weights.py — Train/export PASR session quality weights

Expected CSV columns:
  label,f0,f1,f2,f3,f4,f5,f6[,weight]

label:
  1 = session conditions were favorable
  0 = session conditions were poor/noisy

Feature contract:
  f0 = hourNorm
  f1 = dayNorm
  f2 = spreadQuality
  f3 = volatilityQuality
  f4 = volumeQuality
  f5 = overlapFlag
  f6 = newsSafety

Output binary layout, float32:
  [magic, version, n_features=7, bias, w0..w6]
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
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, brier_score_loss, log_loss, roc_auc_score

MAGIC = 20260609.0
VERSION = 1.0
N_FEATURES = 7
FEATURES = [f"f{i}" for i in range(N_FEATURES)]
DEFAULT_WEIGHTS = [-2.20, 0.30, 0.20, 1.30, 0.95, 0.85, 0.90, 1.10]
FEATURE_NAMES = ["hourNorm", "dayNorm", "spreadQuality", "volatilityQuality", "volumeQuality", "overlapFlag", "newsSafety"]


def load_dataset(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, comment="#")
    required = {"label", *FEATURES}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    df = df.copy()
    for c in FEATURES:
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0.0).clip(0.0, 1.0)
    df["label"] = pd.to_numeric(df["label"], errors="coerce").fillna(0).astype(int).clip(0, 1)
    df["weight"] = pd.to_numeric(df.get("weight", 1.0), errors="coerce").fillna(1.0).clip(0.1, 10.0)
    if len(df) == 0:
        raise ValueError("No valid rows found")
    return df


def train(df: pd.DataFrame, min_samples: int) -> tuple[list[float], dict]:
    y = df["label"].to_numpy(np.int32)
    report = {"n": int(len(df)), "used_fallback": False}
    if len(df) < min_samples or len(set(y.tolist())) < 2:
        report["used_fallback"] = True
        report["reason"] = "not enough samples or only one class"
        return DEFAULT_WEIGHTS, report
    X = df[FEATURES].to_numpy(np.float32)
    w = df["weight"].to_numpy(np.float32)
    split = max(1, int(len(df) * 0.8))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]
    w_train, w_test = w[:split], w[split:]
    model = LogisticRegression(solver="lbfgs", C=1.0, max_iter=1000, random_state=42)
    model.fit(X_train, y_train, sample_weight=w_train)
    weights = [float(model.intercept_[0])] + [float(v) for v in model.coef_[0]]
    if len(y_test) > 0 and len(set(y_test.tolist())) >= 2:
        proba = model.predict_proba(X_test)[:, 1]
        pred = (proba >= 0.5).astype(int)
        report.update({
            "accuracy": float(accuracy_score(y_test, pred, sample_weight=w_test)),
            "brier": float(brier_score_loss(y_test, proba, sample_weight=w_test)),
            "log_loss": float(log_loss(y_test, proba, sample_weight=w_test)),
            "roc_auc": float(roc_auc_score(y_test, proba, sample_weight=w_test)),
        })
    else:
        report["test_note"] = "test split has one class or no rows"
    return weights, report


def export_binary(weights: list[float], out_path: str) -> None:
    if len(weights) != N_FEATURES + 1:
        raise ValueError(f"Expected bias + {N_FEATURES} weights")
    values = [MAGIC, VERSION, float(N_FEATURES)] + [float(v) for v in weights]
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack(f"{len(values)}f", *values))
    print(f"[train_session_quality_weights] wrote {out_path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True)
    parser.add_argument("--out", default="output")
    parser.add_argument("--min-samples", type=int, default=80)
    args = parser.parse_args()
    df = load_dataset(args.csv)
    weights, metrics = train(df, args.min_samples)
    out_dir = Path(args.out)
    export_binary(weights, str(out_dir / "PASR_session_quality_weights.bin"))
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_csv": os.path.abspath(args.csv),
        "feature_contract": {f"f{i}": name for i, name in enumerate(FEATURE_NAMES)},
        "metrics": metrics,
        "weights": weights,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / "session_quality_training_report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
