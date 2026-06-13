#!/usr/bin/env python3
"""
Pure-NumPy Confidence Calibration for PASR
===========================================

Implements Platt scaling calibration without scikit-learn.
Exports PASR_calibration_params.bin compatible with ConfidenceCalibrator.mqh
"""

import json
import os
import struct
import sys
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime, timezone
from typing import Tuple, Dict

SCORE_COL = "score"
OUTCOME_COL = "outcome"
RR_COL = "rr"
DEFAULT_THRESHOLD = 0.55
DEFAULT_AGREEMENT_ALPHA = 0.30
MIN_SAMPLES = 30
TEST_SPLIT = 0.20
RANDOM_STATE = 42

def sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -500, 500)))

def log_loss(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    y_pred = np.clip(y_pred, 1e-15, 1 - 1e-15)
    return -np.mean(y_true * np.log(y_pred) + (1 - y_true) * np.log(1 - y_pred))

def brier_score(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    return np.mean((y_true - y_pred) ** 2)

def roc_auc(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """Simple ROC AUC via Mann-Whitney U"""
    pos = y_pred[y_true == 1]
    neg = y_pred[y_true == 0]
    if len(pos) == 0 or len(neg) == 0:
        return 0.5
    # Rank all scores
    all_scores = np.concatenate([pos, neg])
    ranks = np.argsort(np.argsort(all_scores))
    pos_ranks = ranks[:len(pos)]
    auc = (np.sum(pos_ranks) - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))
    return float(auc)

def fit_platt_scaling(scores: np.ndarray, outcomes: np.ndarray, 
                      max_iter: int = 100, lr: float = 0.01) -> Tuple[float, float]:
    """
    Fit Platt scaling: P(y=1|score) = sigmoid(A * score + B)
    Using Newton's method / gradient descent
    """
    n = len(scores)
    targets = (outcomes == 1).astype(float)
    
    # Initialize A, B for sigmoid
    # Start with prior probability
    pos_rate = np.mean(targets)
    prior_logit = np.log(max(0.01, pos_rate) / max(0.01, 1 - pos_rate))
    A = 1.0
    B = prior_logit
    
    for _ in range(max_iter):
        logits = A * scores + B
        probs = sigmoid(logits)
        
        # Gradients
        grad_A = np.sum((probs - targets) * scores) / n
        grad_B = np.sum(probs - targets) / n
        
        # Hessian diagonal (approximate)
        hess_A = np.sum(probs * (1 - probs) * scores * scores) / n
        hess_B = np.sum(probs * (1 - probs)) / n
        
        # Newton step with damping
        A -= lr * grad_A / (hess_A + 1e-6)
        B -= lr * grad_B / (hess_B + 1e-6)
        
        # Constrain A to be positive (monotonic)
        A = max(0.1, A)
        
        if abs(grad_A) < 1e-6 and abs(grad_B) < 1e-6:
            break
    
    return float(A), float(B)

def train_calibration(csv_path: str, output_dir: str = "output",
                      method: str = "platt", threshold: float = 0.55,
                      agreement_alpha: float = 0.30) -> Dict:
    """Train confidence calibration and export params"""
    
    print(f"Loading calibration data from {csv_path}...")
    df = pd.read_csv(csv_path)
    required = {SCORE_COL, OUTCOME_COL, RR_COL}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"CSV missing columns: {missing}")
    
    # Filter out pending (outcome=0)
    df_filtered = df[df[OUTCOME_COL] != 0].copy()
    df_filtered['label'] = (df_filtered[OUTCOME_COL] == 1).astype(int)
    df_filtered[SCORE_COL] = pd.to_numeric(df_filtered[SCORE_COL], errors='coerce').fillna(0.0).clip(0.0, 1.0)
    df_filtered[RR_COL] = pd.to_numeric(df_filtered[RR_COL], errors='coerce').fillna(0.0)
    
    print(f"Loaded {len(df_filtered)} resolved trades")
    
    if len(df_filtered) < MIN_SAMPLES:
        raise ValueError(f"Only {len(df_filtered)} samples (need {MIN_SAMPLES})")
    
    # Split train/test (temporal split for time series)
    split = int(len(df_filtered) * (1 - TEST_SPLIT))
    train_df = df_filtered.iloc[:split]
    test_df = df_filtered.iloc[split:]
    
    print(f"Train: {len(train_df)}, Test: {len(test_df)}")
    
    # Fit Platt scaling
    train_scores = train_df[SCORE_COL].to_numpy()
    train_labels = train_df['label'].to_numpy()
    
    A, B = fit_platt_scaling(train_scores, train_labels)
    print(f"Platt params: A={A:.6f}, B={B:.6f}")
    
    # Evaluate on test
    test_scores = test_df[SCORE_COL].to_numpy()
    test_labels = test_df['label'].to_numpy()
    
    test_logits = A * test_scores + B
    test_proba = sigmoid(test_logits)
    
    metrics = {
        "brier_score": float(brier_score(test_labels, test_proba)),
        "log_loss": float(log_loss(test_labels, test_proba)),
        "roc_auc": float(roc_auc(test_labels, test_proba)),
        "n_train": int(len(train_df)),
        "n_test": int(len(test_df)),
        "method": method,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    
    print(f"  Brier Score: {metrics['brier_score']:.4f}")
    print(f"  Log Loss: {metrics['log_loss']:.4f}")
    print(f"  ROC AUC: {metrics['roc_auc']:.4f}")
    
    # Export binary params [A, B, threshold, agreement_alpha]
    params = {
        "platt_A": A,
        "platt_B": B,
        "threshold": max(0.40, min(0.90, float(threshold))),
        "agreement_alpha": max(0.0, min(1.0, float(agreement_alpha))),
    }
    
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Binary export
    bin_path = Path(output_dir) / "PASR_calibration_params.bin"
    values = [
        float(params["platt_A"]),
        float(params["platt_B"]),
        float(params["threshold"]),
        float(params["agreement_alpha"]),
    ]
    with open(bin_path, 'wb') as f:
        f.write(struct.pack('4f', *values))
    print(f"Binary params exported to {bin_path}")
    
    # JSON export
    json_path = Path(output_dir) / "calibration_params.json"
    with open(json_path, 'w') as f:
        json.dump({"metadata": metrics, "params": params}, f, indent=2)
    print(f"JSON params exported to {json_path}")
    
    # Simple HTML report
    html_path = Path(output_dir) / "calib_report.html"
    html_content = f"""<!DOCTYPE html>
<html><head><title>PASR Calibration Report</title></head>
<body style="font-family:sans-serif;max-width:800px;margin:40px auto">
<h1>PASR Confidence Calibration Report</h1>
<p>Generated: {metrics['timestamp']} | Method: <strong>{metrics['method']}</strong></p>
<h2>Metrics</h2>
<table border="1" cellpadding="6"><tr><th>Metric</th><th>Value</th></tr>
<tr><td>Brier Score</td><td>{metrics['brier_score']:.4f}</td></tr>
<tr><td>Log Loss</td><td>{metrics['log_loss']:.4f}</td></tr>
<tr><td>ROC AUC</td><td>{metrics['roc_auc']:.4f}</td></tr>
<tr><td>Train samples</td><td>{metrics['n_train']}</td></tr>
<tr><td>Test samples</td><td>{metrics['n_test']}</td></tr>
</table>
<h2>Exported MQL5 Params</h2>
<pre>{json.dumps(params, indent=2)}</pre>
<h2>Deployment</h2>
<ol>
<li>Copy <code>PASR_calibration_params.bin</code> to <code>MT5/MQL5/Files/</code></li>
<li>Restart EA. <code>ConfidenceCalibrator.mqh</code> loads it automatically.</li>
</ol>
</body></html>"""
    with open(html_path, 'w') as f:
        f.write(html_content)
    print(f"HTML report exported to {html_path}")
    
    return params


def main():
    import argparse
    parser = argparse.ArgumentParser(description="PASR confidence calibration (NumPy only)")
    parser.add_argument("--csv", default="output/PASR_calibration.csv")
    parser.add_argument("--out", default="output")
    parser.add_argument("--method", default="platt", choices=["platt"])
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--agreement-alpha", type=float, default=DEFAULT_AGREEMENT_ALPHA)
    args = parser.parse_args()
    
    if not os.path.exists(args.csv):
        print(f"ERROR: CSV not found: {args.csv}")
        return 1
    
    try:
        params = train_calibration(args.csv, args.out, args.method, args.threshold, args.agreement_alpha)
        print("\n✓ Calibration complete!")
        print(f"  Copy {args.out}/PASR_calibration_params.bin -> MT5/MQL5/Files/")
        return 0
    except Exception as e:
        print(f"✗ Calibration failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())