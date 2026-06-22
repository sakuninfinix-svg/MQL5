#!/usr/bin/env python3
"""
Validate volatility prediction for position sizing.
Backtests a simple strategy that uses predicted volatility to adjust position size.
"""
import numpy as np, pandas as pd, json, os, sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from train_volatility_ridge import flatten_sequences, add_persistence
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

d = Path(__file__).resolve().parent.parent / 'output'

# Load multi-symbol data
data = np.load(d / 'volatility_m15_4sym.npz')
X_seq, y = data['X'], data['y']
print(f"Data: {X_seq.shape}, y: {y.shape}")

# Time split
n = len(y)
split = int(n * 0.8)

# Align features
X_flat = flatten_sequences(X_seq)
X_full = add_persistence(X_flat, y)

y_cur = y[1:]
y_prev = y[:-1]

X_train = X_full[:split-1]
y_train = y_cur[:split-1]
X_test_full = X_full[split-1:-1]
y_test = y_cur[split-1:-1]

# Train model
scaler = StandardScaler()
Xn_train = scaler.fit_transform(X_train)
model = Ridge(alpha=100.0, solver='sag', max_iter=200, tol=1e-3, random_state=42)
model.fit(Xn_train, y_train)

# Predict on test set
Xn_test = scaler.transform(X_test_full)
y_pred = model.predict(Xn_test)

# ======================================================================
# Practical Validation: Volatility Regime Separation
# ======================================================================
p30 = np.percentile(y_pred, 30)
p70 = np.percentile(y_pred, 70)
regimes = np.where(y_pred < p30, 0, np.where(y_pred < p70, 1, 2))

print(f"\n{'='*60}")
print(f"Volatility Regime Separation (Test Set)")
print(f"{'='*60}")
print(f"{'Regime':15s} {'Count':>8s} {'Pred_Vol':>10s} {'Actual_Vol':>10s} {'Spread':>8s}")
print(f"{'-'*51}")
for r, name in enumerate(['LOW ', 'MID ', 'HIGH']):
    mask = regimes == r
    print(f"{name:15s} {mask.sum():>8,d} {y_pred[mask].mean():>10.2e} "
          f"{y_test[mask].mean():>10.2e} "
          f"{y_test[mask].mean()/max(y_test[mask].mean(),1e-15):>7.1f}x")
    
print(f"\nHIGH/LOW spread: {y_test[regimes==2].mean()/max(y_test[regimes==0].mean(),1e-15):.1f}x")

# ======================================================================
# Stop-Loss Sizing: use predicted vol to set SL distance
# ======================================================================
# In PASR, SL is based on ATR. We can replace with predicted vol:
# SL_points = pred_vol / point * sl_multiplier
# Higher pred_vol = wider SL (avoid being stopped out by noise)
# Lower pred_vol = tighter SL (tighter control)

# Simulate SL placement
point = 0.00001  # EURUSD point size
sl_mult = 2.0    # 2x volatility for SL distance
sl_dist = y_pred * sl_mult / point  # SL in points
sl_const = np.full_like(y_pred, np.median(y_pred)) * sl_mult / point

print(f"\n{'='*60}")
print(f"Stop-Loss Sizing Based on Predicted Vol")
print(f"{'='*60}")
print(f"Pred vol: min={y_pred.min():.2e}, median={np.median(y_pred):.2e}, max={y_pred.max():.2e}")
print(f"SL range: {sl_dist.min():.0f} - {sl_dist.max():.0f} points")
print(f"Constant SL: {sl_const[0]:.0f} points")
print(f"SL adjustment factor: mean={np.mean(sl_dist/sl_const):.2f}x, range=[{sl_dist.min()/sl_const[0]:.2f}x, {sl_dist.max()/sl_const[0]:.2f}x]")

# ======================================================================
# Risk Allocation per Trade
# ======================================================================
# Kelly-inspired: risk_per_trade = base_risk * (baseline_vol / predicted_vol)
# Higher predicted vol = lower risk (avoid overbetting in uncertainty)
baseline_vol = np.median(y_pred)
risk_mult = baseline_vol / y_pred
risk_mult = np.clip(risk_mult, 0.2, 3.0)  # clamp to [0.2x, 3.0x]

print(f"\n{'='*60}")
print(f"Dynamic Risk Allocation")
print(f"{'='*60}")
print(f"Risk multiplier: min={risk_mult.min():.2f}x, median={np.median(risk_mult):.2f}x, max={risk_mult.max():.2f}x")
print(f"In 70% of cases: risk between {np.percentile(risk_mult, 15):.2f}x and {np.percentile(risk_mult, 85):.2f}x")
print(f"\nInterpretation:")
print(f"  Pred vol below median: INCREASE position (market is calm, trends reliable)")
print(f"  Pred vol above median: DECREASE position (market is volatile, high uncertainty)")
print(f"  Pred vol > 3x median:  REDUCE to 20% (extreme caution)")

# Correlation between predicted vol and risk multiplier
corr_vol_risk = np.corrcoef(y_pred, risk_mult)[0,1]
print(f"  Correlation pred_vol ↔ risk_mult: {corr_vol_risk:.4f} (should be -1.0)")

results = {
    'n_test': n_test,
    'p30': float(p30),
    'p70': float(p70),
    'vol_max': float(y_pred.max()),
    'vol_min': float(y_pred.min()),
    'high_low_spread': float(y_test[regimes==2].mean() / max(y_test[regimes==0].mean(), 1e-15)),
    'corr_vol_risk_mult': float(corr_vol_risk),
    'risk_mult_p15': float(np.percentile(risk_mult, 15)),
    'risk_mult_p50': float(np.percentile(risk_mult, 50)),
    'risk_mult_p85': float(np.percentile(risk_mult, 85)),
}
with open(d / 'vol_strategy_validation.json', 'w') as f:
    json.dump(results, f, indent=2)
print(f"\nResults saved to vol_strategy_validation.json")
