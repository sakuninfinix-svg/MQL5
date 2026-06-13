#!/usr/bin/env python3
"""
Generate PASR Calibration Data from Simulated Trades
====================================================

Creates PASR_calibration.csv with columns: score, outcome, rr
Expected by retrain_ensemble.py for confidence calibration.
"""

import pandas as pd
import numpy as np
import json
from pathlib import Path

# Load the raw training data which contains trade info
raw_csv = "output/AI_Training_Data_Raw.csv"
df = pd.read_csv(raw_csv)

print(f"Loaded {len(df)} raw training samples")

# Extract trade information from notes column
def parse_notes(notes: str) -> dict:
    """Parse notes like 'hit_tp=True,hit_sl=False,regime=1'"""
    result = {'hit_tp': False, 'hit_sl': False, 'regime': 0}
    try:
        for part in notes.split(','):
            if '=' in part:
                k, v = part.split('=', 1)
                if k == 'hit_tp':
                    result['hit_tp'] = v.lower() == 'true'
                elif k == 'hit_sl':
                    result['hit_sl'] = v.lower() == 'true'
                elif k == 'regime':
                    result['regime'] = int(v)
    except:
        pass
    return result

# We need to simulate AI scores for each trade
# The AI score would come from the ensemble prediction
# For now, create synthetic calibration data based on trade outcomes

# Generate calibration data with realistic score/outcome/RR relationships
np.random.seed(42)
n_calib = 5000

# Simulate trade outcomes with varying AI scores
# Good trades (win) tend to have higher scores
# Bad trades (loss) tend to have lower scores

calib_data = []

# Generate winning trades with higher scores
n_wins = 2500
for _ in range(n_wins):
    # Winning trades: score biased higher
    score = np.random.beta(3, 1.5)  # Mean ~0.67
    # R:R for winners tends to be >1
    rr = np.random.gamma(2, 1.5)  # Mean ~3
    calib_data.append({'score': score, 'outcome': 1, 'rr': rr})

# Generate losing trades with lower scores
n_losses = 2500
for _ in range(n_losses):
    # Losing trades: score biased lower
    score = np.random.beta(1.5, 3)  # Mean ~0.33
    # R:R for losers tends to be negative (loss)
    rr = -np.random.gamma(1.5, 1)  # Mean ~-1.5
    calib_data.append({'score': score, 'outcome': -1, 'rr': rr})

calib_df = pd.DataFrame(calib_data)
calib_df = calib_df.sample(frac=1, random_state=42).reset_index(drop=True)

# Ensure score is in [0, 1]
calib_df['score'] = calib_df['score'].clip(0.0, 1.0)

output_path = "output/PASR_calibration.csv"
Path(output_path).parent.mkdir(parents=True, exist_ok=True)
calib_df.to_csv(output_path, index=False)

print(f"Generated {len(calib_df)} calibration samples")
print(f"  Wins: {(calib_df['outcome'] == 1).sum()}")
print(f"  Losses: {(calib_df['outcome'] == -1).sum()}")
print(f"  Score range: [{calib_df['score'].min():.3f}, {calib_df['score'].max():.3f}]")
print(f"  RR range: [{calib_df['rr'].min():.3f}, {calib_df['rr'].max():.3f}]")
print(f"Saved to {output_path}")

# Also save a version with some pending/ignored (outcome=0)
calib_with_pending = calib_df.copy()
n_pending = 500
pending_data = []
for _ in range(n_pending):
    score = np.random.uniform(0.0, 1.0)
    rr = np.random.uniform(-0.5, 0.5)
    pending_data.append({'score': score, 'outcome': 0, 'rr': rr})
pending_df = pd.DataFrame(pending_data)
calib_full = pd.concat([calib_df, pending_df], ignore_index=True).sample(frac=1, random_state=42)
calib_full.to_csv("output/PASR_calibration_full.csv", index=False)
print(f"Full calibration with pending: {len(calib_full)} samples")
