#!/usr/bin/env python3
"""
PASR Auto-Retrain System
=========================
Monitors for retrain trigger flag from EA, retrains MLP classifier,
evaluates against current model, and deploys if improvement detected.

Designed to run via cron every 5 minutes.

Flow:
  1. EA trades → writes trade log CSV → writes retrain_trigger.flag
  2. This script detects flag file → reads trade data
  3. Retrains MLP (34→64→32→1 to match AIInference.mqh)
  4. Compares AUC with current deployed model
  5. If new model better → backup old → deploy new
  6. Removes trigger flag

Usage:
  python3 training/auto_retrain.py [--dry-run] [--min-trades 200]

Cron setup (every 5 minutes):
  */5 * * * * /path/to/tools/training/watch_trades.sh
"""

import numpy as np
import json
import os
import sys
import shutil
import time
import struct
import logging
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ============================================================================
# Configuration
# ============================================================================
TOOLS_DIR = Path(__file__).resolve().parent.parent
MQL5_FILES_DIR = TOOLS_DIR.parent / "Files"
OUTPUT_DIR = TOOLS_DIR / "output"
TRAINING_DIR = TOOLS_DIR / "training"

TRADE_LOG_FILE = "PASR_trades_export.csv"
OHLCV_LOG_FILE = "PASR_ohlcv_export.csv"
TRIGGER_FLAG = "retrain_trigger.flag"
WEIGHTS_FILE = "PASR_mlp_m0.bin"
REPORT_FILE = "mlp_classifier_report.json"
RETRAIN_STATE_FILE = "auto_retrain_state.json"

# Retraining requires this architecture to match AIInference.mqh
ARCH_HIDDEN = "64,32"

# Minimum quality gates for deployment
MIN_AUC_THRESHOLD = 0.55
MIN_IMPROVEMENT = 0.005
MIN_TRADES_DEFAULT = 200

# Logging
LOG_FILE = OUTPUT_DIR / "auto_retrain.log"


def setup_logging():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler(str(LOG_FILE)),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger("auto_retrain")


# ============================================================================
# State Management
# ============================================================================
def load_state() -> dict:
    """Load persistent state (last retrain time, current AUC, trade count)."""
    state_path = OUTPUT_DIR / RETRAIN_STATE_FILE
    if state_path.exists():
        with open(state_path) as f:
            return json.load(f)
    return {
        "last_retrain": None,
        "current_auc": 0.0,
        "total_retrains": 0,
        "total_deployments": 0,
        "last_trade_count": 0
    }


def save_state(state: dict):
    state_path = OUTPUT_DIR / RETRAIN_STATE_FILE
    with open(state_path, 'w') as f:
        json.dump(state, f, indent=2)


# ============================================================================
# Trigger Detection
# ============================================================================
def check_trigger() -> bool:
    """Check if EA has written a retrain trigger flag."""
    flag_path = MQL5_FILES_DIR / TRIGGER_FLAG
    return flag_path.exists()


def remove_trigger():
    """Remove the trigger flag after processing."""
    flag_path = MQL5_FILES_DIR / TRIGGER_FLAG
    if flag_path.exists():
        flag_path.unlink()


def read_trigger_info() -> dict:
    """Read trigger file content (trade count, timestamp)."""
    flag_path = MQL5_FILES_DIR / TRIGGER_FLAG
    info = {"trade_count": 0, "timestamp": ""}
    if flag_path.exists():
        try:
            content = flag_path.read_text().strip()
            if content:
                lines = content.split('\n')
                for line in lines:
                    if '=' in line:
                        k, v = line.split('=', 1)
                        if k == 'trade_count':
                            info['trade_count'] = int(v)
                        elif k == 'timestamp':
                            info['timestamp'] = v
        except Exception:
            pass
    return info


# ============================================================================
# Model Evaluation
# ============================================================================
def get_current_model_auc() -> float:
    """Read AUC of currently deployed model from report file."""
    report_path = OUTPUT_DIR / REPORT_FILE
    if not report_path.exists():
        return 0.0
    try:
        with open(report_path) as f:
            report = json.load(f)
        models = report.get('models', [])
        if not models:
            return 0.0
        return max(m.get('roc_auc', 0.0) for m in models)
    except Exception:
        return 0.0


def quick_evaluate_weights(weights_path: str, test_csv: str) -> float:
    """Quick AUC evaluation of a weight file against test data."""
    try:
        import pandas as pd

        df = pd.read_csv(test_csv)
        feature_cols = [f'f{i}' for i in range(34)]
        X = df[feature_cols].to_numpy(dtype=np.float32)
        y = (df['label'].to_numpy(dtype=np.float32) > 0.5).astype(np.float32)

        # Load weights
        with open(weights_path, 'rb') as f:
            data = f.read()
        floats = struct.unpack(f'{len(data)//4}f', data)
        idx = 4  # skip header
        in_dim, h1, h2, out = int(floats[0]), int(floats[1]), int(floats[2]), int(floats[3])

        W1 = np.array(floats[idx:idx + in_dim * h1]).reshape(in_dim, h1)
        idx += in_dim * h1
        b1 = np.array(floats[idx:idx + h1])
        idx += h1
        W2 = np.array(floats[idx:idx + h1 * h2]).reshape(h1, h2)
        idx += h1 * h2
        b2 = np.array(floats[idx:idx + h2])
        idx += h2
        W3 = np.array(floats[idx:idx + h2]).reshape(h2, 1)
        idx += h2
        b3 = np.array([floats[idx]])

        # Forward pass
        z1 = X @ W1 + b1
        a1 = np.maximum(0, z1)
        z2 = a1 @ W2 + b2
        a2 = np.maximum(0, z2)
        z3 = a2 @ W3 + b3
        p = 1.0 / (1.0 + np.exp(-np.clip(z3, -500, 500)))
        p = p.flatten()

        # Simple AUC
        from train_mlp_classifier import binary_roc_auc
        auc = binary_roc_auc(y, p)
        return auc

    except Exception:
        return 0.0


# ============================================================================
# Retraining
# ============================================================================
def prepare_training_data(log: logging.Logger) -> Optional[str]:
    """Import MT5 trade data and prepare training CSV."""
    trade_csv = MQL5_FILES_DIR / TRADE_LOG_FILE
    ohlcv_csv = MQL5_FILES_DIR / OHLCV_LOG_FILE

    if not trade_csv.exists():
        log.error(f"Trade log not found: {trade_csv}")
        return None

    training_csv = str(OUTPUT_DIR / "MT5_Training_Data.csv")

    if ohlcv_csv.exists():
        log.info(f"Importing trades with OHLCV: {trade_csv} + {ohlcv_csv}")
        ret = os.system(
            f'cd "{TOOLS_DIR}" && python3 training/import_mt5_trades.py '
            f'--csv "{trade_csv}" --ohlcv "{ohlcv_csv}" '
            f'--output "{training_csv}"'
        )
    else:
        log.warning("No OHLCV file — using augmented synthetic data as fallback")
        synthetic = OUTPUT_DIR / "AI_Training_Data_Augmented.csv"
        if synthetic.exists():
            shutil.copy2(str(synthetic), training_csv)
            ret = 0
        else:
            log.error("No training data available (no OHLCV, no augmented data)")
            return None

    if ret != 0 or not os.path.exists(training_csv):
        log.error("Training data preparation failed")
        return None

    return training_csv


def retrain_model(training_csv: str, log: logging.Logger) -> Optional[str]:
    """Retrain MLP classifier and return path to new weights."""
    out_dir = str(OUTPUT_DIR)
    new_weights = str(OUTPUT_DIR / "PASR_mlp_new.bin")

    log.info("Training MLP classifier (34→64→32→1)...")
    ret = os.system(
        f'cd "{TOOLS_DIR}" && python3 training/train_mlp_classifier.py '
        f'--csv "{training_csv}" --out "{out_dir}" '
        f'--epochs 300 --lr 0.001 --batch-size 64 '
        f'--dropout 0.1 --hidden "{ARCH_HIDDEN}" '
        f'--seeds 42,137,73 --focal-gamma 1.0 --label-smoothing 0.02'
    )

    if ret != 0:
        log.error("Training failed")
        return None

    # Find best model from report
    report_path = OUTPUT_DIR / REPORT_FILE
    if not report_path.exists():
        log.error("Training report not found")
        return None

    with open(report_path) as f:
        report = json.load(f)

    models = report.get('models', [])
    if not models:
        log.error("No models in report")
        return None

    best = max(models, key=lambda m: m.get('roc_auc', 0))
    best_file = OUTPUT_DIR / best['file']

    if not best_file.exists():
        log.error(f"Best model file not found: {best_file}")
        return None

    shutil.copy2(str(best_file), new_weights)
    log.info(f"Best model: {best['file']} (AUC={best.get('roc_auc', 0):.4f}, "
             f"F1={best.get('f1_score', 0):.4f})")

    return new_weights


def deploy_weights(new_weights: str, log: logging.Logger) -> bool:
    """Deploy new weights to MQL5/Files/ with backup."""
    deploy_path = MQL5_FILES_DIR / WEIGHTS_FILE
    backup_path = MQL5_FILES_DIR / f"{WEIGHTS_FILE}.bak"

    if deploy_path.exists():
        shutil.copy2(str(deploy_path), str(backup_path))
        log.info(f"Backed up old weights to {backup_path.name}")

    shutil.copy2(new_weights, str(deploy_path))
    log.info(f"Deployed new weights to {deploy_path}")

    # Write deployment marker
    marker = MQL5_FILES_DIR / "retrain_deploy.marker"
    marker.write_text(
        f"timestamp={datetime.now(timezone.utc).isoformat()}\n"
        f"source={new_weights}\n"
    )

    return True


# ============================================================================
# Main Pipeline
# ============================================================================
def run_pipeline(dry_run: bool = False, min_trades: int = MIN_TRADES_DEFAULT):
    log = setup_logging()
    log.info("=" * 50)
    log.info("PASR Auto-Retrain: checking trigger...")

    if not check_trigger():
        return

    log.info("Trigger detected! Starting retrain pipeline...")

    # Read trigger info
    info = read_trigger_info()
    trade_count = info.get('trade_count', 0)
    log.info(f"Trade count from EA: {trade_count}")

    if trade_count > 0 and trade_count < min_trades:
        log.info(f"Not enough trades ({trade_count} < {min_trades}), skipping")
        return

    state = load_state()

    # Step 1: Prepare training data
    log.info("\n[1/4] Preparing training data...")
    training_csv = prepare_training_data(log)
    if training_csv is None:
        remove_trigger()
        return

    if dry_run:
        log.info("[DRY RUN] Would retrain now. Exiting.")
        remove_trigger()
        return

    # Step 2: Retrain
    log.info("\n[2/4] Retraining MLP...")
    new_weights = retrain_model(training_csv, log)
    if new_weights is None:
        remove_trigger()
        return

    # Step 3: Evaluate
    log.info("\n[3/4] Evaluating new model...")
    current_auc = get_current_model_auc()
    new_auc = quick_evaluate_weights(new_weights, training_csv)
    log.info(f"Current model AUC: {current_auc:.4f}")
    log.info(f"New model AUC:     {new_auc:.4f}")

    # Quality gates
    if new_auc < MIN_AUC_THRESHOLD:
        log.warning(f"New model AUC ({new_auc:.4f}) below minimum ({MIN_AUC_THRESHOLD})")
        log.warning("Skipping deployment — model not good enough")
        remove_trigger()
        state['total_retrains'] += 1
        save_state(state)
        return

    if current_auc > 0 and new_auc < current_auc + MIN_IMPROVEMENT:
        log.warning(f"New model ({new_auc:.4f}) not better than current ({current_auc:.4f}) "
                    f"by ≥{MIN_IMPROVEMENT}")
        log.warning("Skipping deployment")
        remove_trigger()
        state['total_retrains'] += 1
        save_state(state)
        return

    # Step 4: Deploy
    log.info("\n[4/4] Deploying new weights...")
    if deploy_weights(new_weights, log):
        state['last_retrain'] = datetime.now(timezone.utc).isoformat()
        state['current_auc'] = new_auc
        state['total_retrains'] += 1
        state['total_deployments'] += 1
        state['last_trade_count'] = trade_count
        save_state(state)
        log.info(f"Deployment successful! AUC: {current_auc:.4f} → {new_auc:.4f}")
    else:
        log.error("Deployment failed!")

    # Cleanup
    remove_trigger()
    if os.path.exists(new_weights):
        os.unlink(new_weights)

    log.info("Auto-retrain complete.")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="PASR Auto-Retrain System")
    parser.add_argument("--dry-run", action="store_true",
                        help="Check trigger and prepare data, but don't retrain")
    parser.add_argument("--min-trades", type=int, default=MIN_TRADES_DEFAULT,
                        help="Minimum trades before retrain")
    parser.add_argument("--force", action="store_true",
                        help="Force retrain even without trigger flag")
    args = parser.parse_args()

    if args.force:
        flag_path = MQL5_FILES_DIR / TRIGGER_FLAG
        flag_path.parent.mkdir(parents=True, exist_ok=True)
        flag_path.write_text("trade_count=999\ntimestamp=forced\n")

    run_pipeline(dry_run=args.dry_run, min_trades=args.min_trades)


if __name__ == "__main__":
    main()
