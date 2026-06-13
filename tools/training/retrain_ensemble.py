#!/usr/bin/env python3
"""
retrain_ensemble.py — PASR Confidence Calibration Pipeline
==========================================================

Reads PASR_calibration.csv exported from MT5, trains a confidence calibrator,
and exports files that are actually consumed by ConfidenceCalibrator.mqh:

  1. PASR_calibration_params.bin — float32 [A, B, threshold, agreement_alpha]
  2. calibration_params.json     — human-readable metadata and params
  3. calib_report.html           — calibration metrics report

Expected CSV columns:
  score,outcome,rr

Where outcome is:
  +1 = win, -1 = loss, 0 = pending/ignored

Deployment:
  Copy PASR_calibration_params.bin to MT5/MQL5/Files/.
  ConfidenceCalibrator.mqh loads it automatically on Init().
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

DEFAULT_CSV = "PASR_calibration.csv"
DEFAULT_OUT = "output"
DEFAULT_METHOD = "platt"
MIN_SAMPLES = 30
TEST_SPLIT = 0.20
RANDOM_STATE = 42

SCORE_COL = "score"
OUTCOME_COL = "outcome"
RR_COL = "rr"
DEFAULT_THRESHOLD = 0.55
DEFAULT_AGREEMENT_ALPHA = 0.30


def load_calibration_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    required = {SCORE_COL, OUTCOME_COL, RR_COL}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"CSV missing columns: {missing}")
    df["label"] = (df[OUTCOME_COL] == 1).astype(int)
    df = df.dropna(subset=[SCORE_COL, RR_COL, "label"])
    df = df[df[OUTCOME_COL] != 0]
    df[SCORE_COL] = pd.to_numeric(df[SCORE_COL], errors="coerce").fillna(0.0).clip(0.0, 1.0)
    df[RR_COL] = pd.to_numeric(df[RR_COL], errors="coerce").fillna(0.0)
    print(f"[calibration] loaded {len(df)} resolved trades from {path}")
    return df


def train_calibrated_model(df: pd.DataFrame, method: str):
    from sklearn.calibration import CalibratedClassifierCV
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.metrics import brier_score_loss, log_loss, roc_auc_score

    X = df[[SCORE_COL, RR_COL]].values.astype(np.float32)
    y = df["label"].values

    split = int(len(X) * (1 - TEST_SPLIT))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    if len(X_train) < MIN_SAMPLES:
        raise ValueError(
            f"Only {len(X_train)} training samples (need {MIN_SAMPLES}). "
            "Run more forward tests before retraining."
        )

    base = GradientBoostingClassifier(
        n_estimators=100,
        max_depth=3,
        learning_rate=0.05,
        random_state=RANDOM_STATE,
    )
    cal_method = "sigmoid" if method == "platt" else "isotonic"
    model = CalibratedClassifierCV(base, method=cal_method, cv=5)
    model.fit(X_train, y_train)

    proba_test = model.predict_proba(X_test)[:, 1]
    metrics = {
        "brier_score": float(brier_score_loss(y_test, proba_test)),
        "log_loss": float(log_loss(y_test, proba_test)),
        "roc_auc": float(roc_auc_score(y_test, proba_test)) if len(set(y_test)) > 1 else None,
        "n_train": int(len(X_train)),
        "n_test": int(len(X_test)),
        "method": method,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    print(
        f"[calibration] Brier={metrics['brier_score']:.4f} "
        f"LogLoss={metrics['log_loss']:.4f} AUC={metrics['roc_auc']}"
    )
    return model, metrics, y_test, proba_test


def estimate_platt_params(model) -> tuple[float, float]:
    """Average sigmoid calibrator params. Falls back to conservative defaults."""
    pairs: list[tuple[float, float]] = []
    try:
        for cal_clf in model.calibrated_classifiers_:
            for cal in cal_clf.calibrators_:
                a = float(getattr(cal, "a_", np.nan))
                b = float(getattr(cal, "b_", np.nan))
                if np.isfinite(a) and np.isfinite(b):
                    pairs.append((a, b))
    except Exception:
        pairs = []

    if not pairs:
        return -1.0, 0.0
    arr = np.asarray(pairs, dtype=np.float64)
    return float(arr[:, 0].mean()), float(arr[:, 1].mean())


def export_params_bin(params: dict, path: str) -> None:
    values = [
        float(params["platt_A"]),
        float(params["platt_B"]),
        float(params["threshold"]),
        float(params["agreement_alpha"]),
    ]
    with open(path, "wb") as f:
        f.write(struct.pack("4f", *values))
    print(f"[calibration] params bin -> {path}")


def export_json(data: dict, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)
    print(f"[calibration] params json -> {path}")


def generate_html_report(metrics: dict, y_test, proba_test, df: pd.DataFrame, out_dir: str, params: dict) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.calibration import calibration_curve

        fig, axes = plt.subplots(1, 3, figsize=(15, 4))
        if len(set(y_test)) > 1:
            frac_pos, mean_pred = calibration_curve(y_test, proba_test, n_bins=10)
            axes[0].plot(mean_pred, frac_pos, "s-", label="Model")
            axes[0].plot([0, 1], [0, 1], "k--", label="Perfect")
            axes[0].set_title("Calibration Curve")
            axes[0].set_xlabel("Mean predicted probability")
            axes[0].set_ylabel("Fraction positives")
            axes[0].legend()
        else:
            axes[0].text(0.5, 0.5, "Not enough classes", ha="center")

        wins = df[df["label"] == 1][SCORE_COL]
        losses = df[df["label"] == 0][SCORE_COL]
        axes[1].hist(wins, bins=20, alpha=0.6, label="Win")
        axes[1].hist(losses, bins=20, alpha=0.6, label="Loss")
        axes[1].set_title("AI Score Distribution")
        axes[1].set_xlabel("AI Score")
        axes[1].legend()

        axes[2].hist(df[df["label"] == 1][RR_COL], bins=20, alpha=0.6, label="Win")
        axes[2].hist(df[df["label"] == 0][RR_COL], bins=20, alpha=0.6, label="Loss")
        axes[2].set_title("R:R Distribution")
        axes[2].set_xlabel("R:R achieved")
        axes[2].legend()

        plt.tight_layout()
        chart_path = os.path.join(out_dir, "calib_charts.png")
        plt.savefig(chart_path, dpi=120)
        plt.close()
        chart_img = '<img src="calib_charts.png" style="max-width:100%">'
    except Exception as e:
        chart_img = f"<p>Chart generation failed: {e}</p>"

    roc_auc = metrics["roc_auc"] if metrics["roc_auc"] is not None else "N/A"
    html = f"""
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>PASR Calibration Report</title></head>
<body style="font-family:Segoe UI,sans-serif;max-width:960px;margin:40px auto">
<h1>PASR Confidence Calibration Report</h1>
<p>Generated: {metrics['timestamp']} | Method: <strong>{metrics['method']}</strong></p>
<h2>Metrics</h2>
<table border="1" cellspacing="0" cellpadding="6">
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Brier Score</td><td>{metrics['brier_score']:.4f}</td></tr>
<tr><td>Log Loss</td><td>{metrics['log_loss']:.4f}</td></tr>
<tr><td>ROC AUC</td><td>{roc_auc}</td></tr>
<tr><td>Train samples</td><td>{metrics['n_train']}</td></tr>
<tr><td>Test samples</td><td>{metrics['n_test']}</td></tr>
</table>
<h2>Exported MQL5 Params</h2>
<pre>{json.dumps(params, indent=2)}</pre>
<h2>Charts</h2>
{chart_img}
<h2>Deployment</h2>
<ol>
<li>Copy <code>PASR_calibration_params.bin</code> to <code>MT5/MQL5/Files/</code>.</li>
<li>Restart EA. <code>ConfidenceCalibrator.mqh</code> loads it automatically.</li>
</ol>
</body></html>
"""
    report_path = os.path.join(out_dir, "calib_report.html")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[calibration] report -> {report_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="PASR confidence calibration pipeline")
    parser.add_argument("--csv", default=DEFAULT_CSV, help="Path to PASR_calibration.csv")
    parser.add_argument("--out", default=DEFAULT_OUT, help="Output directory")
    parser.add_argument("--method", default=DEFAULT_METHOD, choices=["platt", "isotonic"])
    parser.add_argument("--min-samples", type=int, default=MIN_SAMPLES)
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--agreement-alpha", type=float, default=DEFAULT_AGREEMENT_ALPHA)
    args = parser.parse_args()

    if not os.path.exists(args.csv):
        print(f"[calibration] ERROR: CSV not found: {args.csv}")
        return 1

    os.makedirs(args.out, exist_ok=True)
    df = load_calibration_csv(args.csv)
    if len(df) < args.min_samples:
        print(f"[calibration] Only {len(df)} samples (need {args.min_samples}). Aborting.")
        return 2

    model, metrics, y_test, proba_test = train_calibrated_model(df, args.method)
    A, B = estimate_platt_params(model)
    params = {
        "platt_A": A,
        "platt_B": B,
        "threshold": max(0.40, min(0.90, float(args.threshold))),
        "agreement_alpha": max(0.0, min(1.0, float(args.agreement_alpha))),
    }

    export_params_bin(params, os.path.join(args.out, "PASR_calibration_params.bin"))
    export_json({"metadata": metrics, "params": params}, os.path.join(args.out, "calibration_params.json"))
    generate_html_report(metrics, y_test, proba_test, df, args.out, params)

    print("\n[calibration] DONE")
    print("  Copy output/PASR_calibration_params.bin -> MT5/MQL5/Files/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
