#!/usr/bin/env python3
"""
Train and export deployable direction model.
Uses LOW+MID vol filter (exclude HIGH vol = top 30%).
Exports .bin with logistic regression weights for MQL5 inference.

.bin format (142 floats):
  [0]       = model_type (int32, 0=logistic)
  [1..36]   = BUY_LR: weights[0..34] + bias (float32)
  [37..72]  = SELL_LR: weights[0..34] + bias (float32)
  [73..107] = scaler_mean[0..34] (float32)
  [108..142]= scaler_scale[0..34] (float32)
"""
import numpy as np, sys, os, time, struct
from pathlib import Path
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, accuracy_score

d = Path('/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output')

def main():
    print("=" * 60)
    print("Export Deployable Direction Model")
    print("=" * 60)

    data = np.load(str(d / 'direction_all.npz'))
    X = data['X']          # (789504, 16, 34)
    y_dir = data['y_dir']  # -1/0/1
    y_vol = data['y_vol']  # realized vol

    n_total = len(y_dir)
    
    # Volatility filter: LOW+MID (exclude HIGH = top 30%)
    p70 = np.percentile(y_vol, 70)
    mask_lowmid = y_vol < p70
    print(f"LOW+MID filter (vol < {p70:.2e}): {mask_lowmid.sum():,}/{n_total:,} samples "
          f"({mask_lowmid.sum()/n_total*100:.1f}%)")
    
    # Features: last-bar (34) + vol (1) = 35
    X_feat = np.column_stack([X[:, -1, :], y_vol.reshape(-1, 1)])
    X_filt = X_feat[mask_lowmid]
    y_filt = y_dir[mask_lowmid]
    
    print(f"Direction: BUY={(y_filt==1).sum():>6d} SELL={(y_filt==-1).sum():>6d} NEUT={(y_filt==0).sum():>6d}")
    
    # Time split
    n = len(X_filt)
    split = int(n * 0.85)
    
    X_tr, X_te = X_filt[:split], X_filt[split:]
    y_tr, y_te = y_filt[:split], y_filt[split:]
    
    # Scale
    scaler = StandardScaler()
    X_tr_n = scaler.fit_transform(X_tr)
    X_te_n = scaler.transform(X_te)
    
    # Train BUY classifier
    print("\nTraining BUY classifier...", flush=True)
    t0 = time.time()
    buy_lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200, solver='saga',
                                 random_state=42, tol=1e-3)
    buy_lr.fit(X_tr_n, (y_tr == 1).astype(float))
    print(f"  Done in {time.time()-t0:.1f}s")
    
    buy_pred = buy_lr.predict_proba(X_te_n)[:, 1]
    buy_auc = roc_auc_score((y_te == 1).astype(float), buy_pred)
    buy_acc = accuracy_score((y_te == 1).astype(float), (buy_pred > 0.5).astype(float))
    print(f"  AUC={buy_auc:.4f} Acc={buy_acc:.4f}")
    
    # Train SELL classifier
    print("\nTraining SELL classifier...", flush=True)
    t0 = time.time()
    sell_lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200, solver='saga',
                                  random_state=42, tol=1e-3)
    sell_lr.fit(X_tr_n, (y_tr == -1).astype(float))
    print(f"  Done in {time.time()-t0:.1f}s")
    
    sell_pred = sell_lr.predict_proba(X_te_n)[:, 1]
    sell_auc = roc_auc_score((y_te == -1).astype(float), sell_pred)
    sell_acc = accuracy_score((y_te == -1).astype(float), (sell_pred > 0.5).astype(float))
    print(f"  AUC={sell_auc:.4f} Acc={sell_acc:.4f}")
    
    # --- Export .bin ---
    buy_w = buy_lr.coef_[0].astype(np.float32)  # (35,)
    buy_b = np.float32(buy_lr.intercept_[0])
    sell_w = sell_lr.coef_[0].astype(np.float32)  # (35,)
    sell_b = np.float32(sell_lr.intercept_[0])
    scaler_mean = scaler.mean_.astype(np.float32)  # (35,)
    scaler_scale = scaler.scale_.astype(np.float32)  # (35,)
    
    model_type = np.int32(1)  # 1 = direction model
    
    out_path = str(d / 'PASR_direction.bin')
    with open(out_path, 'wb') as f:
        f.write(struct.pack('i', model_type))
        f.write(buy_w.tobytes())
        f.write(struct.pack('f', buy_b))
        f.write(sell_w.tobytes())
        f.write(struct.pack('f', sell_b))
        f.write(scaler_mean.tobytes())
        f.write(scaler_scale.tobytes())
    
    # Write companion info
    info = {
        'model': 'direction_logistic_regression',
        'features': 35,  # 34 AI + 1 vol
        'filter': 'LOW+MID vol (exclude HIGH>70th percentile)',
        'buy_auc': float(buy_auc),
        'buy_acc': float(buy_acc),
        'sell_auc': float(sell_auc),
        'sell_acc': float(sell_acc),
        'n_train': int(split),
        'n_test': int(n - split),
        'export_path': str(out_path),
    }
    import json
    with open(str(d / 'direction_report.json'), 'w') as f:
        json.dump(info, f, indent=2)
    
    print(f"\nExported {out_path} ({struct.calcsize('i') + 4*35 + 4 + 4*35 + 4 + 4*35 + 4*35} bytes)")
    print(f"  model_type = {model_type}")
    print(f"  BUY: {len(buy_w)} weights, bias={buy_b:.6f}")
    print(f"  SELL: {len(sell_w)} weights, bias={sell_b:.6f}")
    print(f"  scaler: mean={scaler_mean[:3]}..., scale={scaler_scale[:3]}...")
    
    # --- Validate combined strategy ---
    print("\n" + "=" * 60)
    print("Combined Strategy Validation (on test set)")
    print("=" * 60)
    
    # Vol prediction for all data (using actual vol as proxy)
    vol_pct = np.percentile(y_vol, 70)
    test_mask = np.arange(n_total) >= int(n_total * 0.85)
    
    # On test set: predict direction only when vol < 70th percentile
    # use actual vol (y_vol) since it's already available and is ground truth
    valid_test = test_mask & (y_vol < vol_pct)
    X_vt = X_feat[valid_test]
    y_vt = y_dir[valid_test]
    y_vt_vol = y_vol[valid_test]
    
    X_vt_n = scaler.transform(X_vt)
    buy_prob = buy_lr.predict_proba(X_vt_n)[:, 1]
    sell_prob = sell_lr.predict_proba(X_vt_n)[:, 1]
    
    print(f"Valid test samples: {len(X_vt):,}")
    
    for thresh in [0.55, 0.60, 0.65, 0.70]:
        buy_sig = buy_prob > thresh
        sell_sig = sell_prob > thresh
        
        trades = buy_sig.astype(int) - sell_sig.astype(int)
        n_trades = (trades != 0).sum()
        trade_ret = trades * np.where(y_vt == 1, 1, np.where(y_vt == -1, -1, 0))
        
        win_rate = (trade_ret > 0).sum() / max(n_trades, 1)
        avg_ret = trade_ret[trades != 0].mean() if n_trades > 0 else 0
        total_ret = trade_ret.sum()
        
        # Adjust by volatility: predicted ret = signal * (1 / sqrt(vol)) — larger returns when vol is low
        risk_adj_ret = trade_ret / np.sqrt(np.maximum(y_vt_vol, 1e-10))
        avg_risk_adj = risk_adj_ret[trades != 0].mean() if n_trades > 0 else 0
        
        print(f"  thresh={thresh:.2f}: trades={n_trades:>5d} ({n_trades/len(trades)*100:5.1f}%) "
              f"win={win_rate:.1%} avg_ret={avg_ret:+.4f} total={total_ret:+.0f} "
              f"risk_adj_ret={avg_risk_adj:+.4f}")
    
    print(f"\nDone! Report saved to {d / 'direction_report.json'}")

if __name__ == '__main__':
    main()
