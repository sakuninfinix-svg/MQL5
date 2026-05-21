#!/usr/bin/env python3
"""
retrain_ensemble.py — PASR AI Retraining Pipeline
==================================================
Reads PASR_calibration.csv exported by AICalibrationBridge.mqh,
trains a calibrated probability estimator (Platt scaling or isotonic
regression over a GradientBoosting base), and exports:
  1. weights.json  — human-readable weights for inspection
  2. PASR_weights.bin — binary float32 array for AIEnsemble.mqh pickup
  3. calib_report.html — calibration curve + metrics HTML report

Usage:
    python retrain_ensemble.py [--csv PATH] [--out DIR] [--method platt|isotonic]

Dependencies:
    pip install pandas numpy scikit-learn matplotlib jinja2
"""

import argparse
import json
import os
import struct
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Config defaults (override via CLI)
# ---------------------------------------------------------------------------
DEFAULT_CSV   = "PASR_calibration.csv"
DEFAULT_OUT   = "output"
DEFAULT_METHOD = "platt"          # 'platt' | 'isotonic'
MIN_SAMPLES    = 30               # refuse to train with fewer samples
TEST_SPLIT     = 0.20             # last 20% used for hold-out eval
RANDOM_STATE   = 42

# Feature columns expected from CSV
# (AICalibrationBridge exports: open_time, score, outcome, rr)
SCORE_COL   = "score"
OUTCOME_COL = "outcome"   # +1 win, -1 loss
RR_COL      = "rr"


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def load_calibration_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    required = {SCORE_COL, OUTCOME_COL, RR_COL}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"CSV missing columns: {missing}")
    # Convert outcome: +1 -> 1, -1 -> 0 (binary label)
    df["label"] = (df[OUTCOME_COL] == 1).astype(int)
    df = df.dropna(subset=[SCORE_COL, "label"])
    df = df[df[OUTCOME_COL] != 0]   # drop pending
    print(f"[retrain] Loaded {len(df)} resolved trades from {path}")
    return df


def export_bin(weights: list[float], path: str):
    """Write flat float32 array as .bin for MQL5 FileReadFloat() pickup."""
    with open(path, "wb") as f:
        f.write(struct.pack(f"{len(weights)}f", *weights))
    print(f"[retrain] Binary weights -> {path}  ({len(weights)} floats)")


def export_json(data: dict, path: str):
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)
    print(f"[retrain] JSON weights  -> {path}")


# ---------------------------------------------------------------------------
# Calibration model
# ---------------------------------------------------------------------------
def train_calibrated_model(df: pd.DataFrame, method: str):
    from sklearn.calibration import CalibratedClassifierCV
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import brier_score_loss, log_loss, roc_auc_score

    X = df[[SCORE_COL, RR_COL]].values.astype(np.float32)
    y = df["label"].values

    # Chronological split (no shuffle — respect time order)
    split = int(len(X) * (1 - TEST_SPLIT))
    X_train, X_test = X[:split], X[split:]
    y_train, y_test = y[:split], y[split:]

    if len(X_train) < MIN_SAMPLES:
        raise ValueError(
            f"Only {len(X_train)} training samples (need {MIN_SAMPLES}). "
            "Run more forward tests before retraining."
        )

    print(f"[retrain] Train: {len(X_train)}  Test: {len(X_test)}  Method: {method}")

    base = GradientBoostingClassifier(
        n_estimators=100,
        max_depth=3,
        learning_rate=0.05,
        random_state=RANDOM_STATE,
    )
    cal_method = "sigmoid" if method == "platt" else "isotonic"
    model = CalibratedClassifierCV(base, method=cal_method, cv=5)
    model.fit(X_train, y_train)

    # Evaluate
    proba_test = model.predict_proba(X_test)[:, 1]
    metrics = {
        "brier_score":  float(brier_score_loss(y_test, proba_test)),
        "log_loss":     float(log_loss(y_test, proba_test)),
        "roc_auc":      float(roc_auc_score(y_test, proba_test)) if len(set(y_test)) > 1 else None,
        "n_train":      int(len(X_train)),
        "n_test":       int(len(X_test)),
        "method":       method,
        "timestamp":    datetime.utcnow().isoformat(),
    }
    print(f"[retrain] Brier={metrics['brier_score']:.4f}  "
          f"LogLoss={metrics['log_loss']:.4f}  "
          f"AUC={metrics['roc_auc']}")

    return model, metrics, X_train, y_train, X_test, y_test, proba_test


# ---------------------------------------------------------------------------
# Weight extraction — flatten model params to float32 list for MQL5
# ---------------------------------------------------------------------------
def extract_weights(model) -> list[float]:
    """
    Extract calibrated model threshold bins as a compact float32 list.
    Format: [n_bins, bin_0_low, bin_0_prob, ..., bin_N_low, bin_N_prob]
    MQL5 side reads N bins and does linear interpolation.
    """
    weights = []
    try:
        # CalibratedClassifierCV with sigmoid: each calibrated_classifier
        # has a .calibrators_ list with a _SigmoidCalibration
        for cal_clf in model.calibrated_classifiers_:
            for cal in cal_clf.calibrators_:
                a = float(getattr(cal, "a_", 0.0))
                b = float(getattr(cal, "b_", 0.0))
                weights.extend([a, b])
    except Exception:
        pass

    # Fallback: score-to-probability lookup table (20 bins, score 0..1)
    if not weights:
        bins = 20
        score_grid = np.linspace(0, 1, bins).reshape(-1, 1)
        # Need dummy RR column
        rr_mean = 0.0
        X_grid = np.column_stack([score_grid, np.full(bins, rr_mean)])
        probs = model.predict_proba(X_grid)[:, 1]
        weights = [float(bins)]
        for s, p in zip(score_grid.flatten(), probs):
            weights.extend([float(s), float(p)])

    return weights


# ---------------------------------------------------------------------------
# HTML calibration report
# ---------------------------------------------------------------------------
def generate_html_report(
    metrics: dict,
    y_test,
    proba_test,
    df: pd.DataFrame,
    out_dir: str,
):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from sklearn.calibration import calibration_curve

        fig, axes = plt.subplots(1, 3, figsize=(15, 4))

        # [0] Calibration curve
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

        # [1] Score distribution
        wins   = df[df["label"] == 1][SCORE_COL]
        losses = df[df["label"] == 0][SCORE_COL]
        axes[1].hist(wins,   bins=20, alpha=0.6, label="Win",  color="green")
        axes[1].hist(losses, bins=20, alpha=0.6, label="Loss", color="red")
        axes[1].set_title("AI Score Distribution")
        axes[1].set_xlabel("AI Score")
        axes[1].legend()

        # [2] RR distribution
        axes[2].hist(df[df["label"] == 1][RR_COL], bins=20, alpha=0.6,
                     label="Win", color="green")
        axes[2].hist(df[df["label"] == 0][RR_COL], bins=20, alpha=0.6,
                     label="Loss", color="red")
        axes[2].set_title("R:R Distribution")
        axes[2].set_xlabel("R:R achieved")
        axes[2].legend()

        plt.tight_layout()
        chart_path = os.path.join(out_dir, "calib_charts.png")
        plt.savefig(chart_path, dpi=120)
        plt.close()
        chart_img = f'<img src="calib_charts.png" style="max-width:100%">'
    except Exception as e:
        chart_img = f"<p>Chart generation failed: {e}</p>"

    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PASR Calibration Report</title>
<style>
  body {{ font-family: 'Segoe UI', sans-serif; max-width: 960px; margin: 40px auto;
          background: #f7f6f2; color: #28251d; }}
  h1   {{ color: #01696f; }}
  h2   {{ border-bottom: 1px solid #dcd9d5; padding-bottom: 6px; }}
  table{{ border-collapse: collapse; width: 100%; margin: 16px 0; }}
  th   {{ background: #01696f; color: white; padding: 8px 12px; text-align: left; }}
  td   {{ padding: 7px 12px; border-bottom: 1px solid #dcd9d5; }}
  tr:nth-child(even) td {{ background: #f3f0ec; }}
  .badge {{ display:inline-block; padding:3px 10px; border-radius:999px;
            font-size:13px; font-weight:600; }}
  .good  {{ background:#d4dfcc; color:#1e3f0a; }}
  .warn  {{ background:#e7d7c4; color:#4b2614; }}
  .bad   {{ background:#e0ced7; color:#561740; }}
</style>
</head>
<body>
<h1>&#x1F4CA; PASR Calibration Report</h1>
<p>Generated: {metrics['timestamp']} UTC &nbsp;|&nbsp;
   Method: <strong>{metrics['method']}</strong></p>

<h2>Metrics</h2>
<table>
  <tr><th>Metric</th><th>Value</th><th>Status</th></tr>
  <tr><td>Brier Score (lower=better)</td>
      <td>{metrics['brier_score']:.4f}</td>
      <td><span class="badge {'good' if metrics['brier_score']<0.22 else 'warn' if metrics['brier_score']<0.30 else 'bad'}">
          {'GOOD' if metrics['brier_score']<0.22 else 'WARN' if metrics['brier_score']<0.30 else 'POOR'}
      </span></td></tr>
  <tr><td>Log Loss (lower=better)</td>
      <td>{metrics['log_loss']:.4f}</td>
      <td><span class="badge {'good' if metrics['log_loss']<0.60 else 'warn' if metrics['log_loss']<0.80 else 'bad'}">
          {'GOOD' if metrics['log_loss']<0.60 else 'WARN' if metrics['log_loss']<0.80 else 'POOR'}
      </span></td></tr>
  <tr><td>ROC AUC (higher=better)</td>
      <td>{metrics['roc_auc'] if metrics['roc_auc'] else 'N/A'}</td>
      <td><span class="badge {'good' if metrics['roc_auc'] and metrics['roc_auc']>0.60 else 'warn'}">
          {'GOOD' if metrics['roc_auc'] and metrics['roc_auc']>0.60 else 'WARN'}
      </span></td></tr>
  <tr><td>Train samples</td><td>{metrics['n_train']}</td><td></td></tr>
  <tr><td>Test samples</td><td>{metrics['n_test']}</td><td></td></tr>
</table>

<h2>Calibration Charts</h2>
{chart_img}

<h2>Recommended Action</h2>
<ul>
  <li>If Brier Score &lt; 0.22 and AUC &gt; 0.60 → deploy weights to MT5 Files/</li>
  <li>If Brier Score 0.22–0.30 → collect 50 more trades then retrain</li>
  <li>If Brier Score &gt; 0.30 → AI signal may not be predictive; review features</li>
  <li>Minimum 30 samples required; 100+ recommended for stable calibration</li>
</ul>

<h2>How to Deploy Weights</h2>
<ol>
  <li>Copy <code>PASR_weights.bin</code> to <code>MQL5/Files/</code></li>
  <li>In EA inputs, enable <code>InpLoadWeights = true</code></li>
  <li>Restart EA — AIEnsemble.LoadWeights() picks up the new .bin</li>
</ol>

<hr>
<p style="color:#7a7974;font-size:13px">PASR EA &copy; 2026 &mdash; Auto-generated by retrain_ensemble.py</p>
</body></html>
"""
    report_path = os.path.join(out_dir, "calib_report.html")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[retrain] HTML report    -> {report_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="PASR AI retraining pipeline")
    parser.add_argument("--csv",    default=DEFAULT_CSV,    help="Path to PASR_calibration.csv")
    parser.add_argument("--out",    default=DEFAULT_OUT,    help="Output directory")
    parser.add_argument("--method", default=DEFAULT_METHOD,
                        choices=["platt", "isotonic"],       help="Calibration method")
    parser.add_argument("--min-samples", type=int, default=MIN_SAMPLES,
                        help="Minimum samples required to retrain")
    args = parser.parse_args()

    # Validate CSV
    if not os.path.exists(args.csv):
        print(f"[retrain] ERROR: CSV not found: {args.csv}")
        print("  Copy PASR_calibration.csv from MT5 Files/ to this directory.")
        sys.exit(1)

    os.makedirs(args.out, exist_ok=True)

    # Load
    df = load_calibration_csv(args.csv)
    if len(df) < args.min_samples:
        print(f"[retrain] Only {len(df)} samples (need {args.min_samples}). Aborting.")
        sys.exit(2)

    # Train
    model, metrics, X_tr, y_tr, X_te, y_te, proba = train_calibrated_model(df, args.method)

    # Export weights
    weights = extract_weights(model)
    export_bin(weights, os.path.join(args.out, "PASR_weights.bin"))
    export_json({"metadata": metrics, "weights": weights},
                os.path.join(args.out, "weights.json"))

    # HTML report
    generate_html_report(metrics, y_te, proba, df, args.out)

    print("\n[retrain] === DONE ===")
    print(f"  Next: copy output/PASR_weights.bin -> MT5/MQL5/Files/")
    print(f"  Then: restart EA with InpLoadWeights=true")


if __name__ == "__main__":
    main()
