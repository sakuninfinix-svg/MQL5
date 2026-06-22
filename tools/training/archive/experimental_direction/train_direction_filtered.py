#!/usr/bin/env python3
"""
Train direction model FILTERED by predicted volatility.
Hypothesis: Filtering out LOW vol (noise) + HIGH vol (whipsaw) reveals
directional signal in MID vol regime.

Uses pre-computed direction_all.npz (X=789k sequences, y_dir, y_vol)
"""
import numpy as np, sys, os, time
from pathlib import Path
from sklearn.linear_model import Ridge, LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, accuracy_score

d = Path('/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output')
SEQ_LEN = 16

def main():
    print("=" * 65)
    print("Direction Model with Volatility Filtering")
    print("=" * 65)
    
    data = np.load(str(d / 'direction_all.npz'))
    X = data['X']        # (789504, 16, 34)
    y_dir = data['y_dir'] # (789504,) -1/0/1
    y_vol = data['y_vol'] # (789504,) realized vol
    
    print(f"Loaded: X={X.shape}, "
          f"BUY={(y_dir==1).sum():>5d} SELL={(y_dir==-1).sum():>5d} NEUT={(y_dir==0).sum():>6d}")
    
    # --- Step 1: Predict volatility (for filtering) ---
    # Use same approach as Ridge model: last-bar features + aggregates + persistence
    print("\n[1] Training volatility model for filtering...", flush=True)
    t0 = time.time()
    X_last = X[:, -1, :]           # (N, 34)
    X_mean = X.mean(axis=1)        # (N, 34)
    X_std = X.std(axis=1)          # (N, 34)
    X_flat = np.column_stack([X_last, X_mean, X_std])  # (N, 102)
    
    y_prev = y_vol[:-1]   # persistence: vol at t-1
    X_full = np.column_stack([y_prev, X_flat[1:]])     # (N-1, 103)
    y_curr = y_vol[1:]    # predict vol at t from vol at t-1
    
    n = len(y_curr)
    n_total = len(y_dir)
    split = int(n * 0.8)
    
    scaler = StandardScaler()
    X_tr = scaler.fit_transform(X_full[:split])
    X_te = scaler.transform(X_full[split:])
    
    ridge = Ridge(alpha=100.0, solver='sag', max_iter=200, tol=1e-3, random_state=42)
    ridge.fit(X_tr, y_curr[:split])
    
    y_pred_train = ridge.predict(X_tr)
    y_pred_test = ridge.predict(X_te)
    y_pred_all = np.concatenate([y_pred_train, y_pred_test])
    
    train_r2 = 1 - ((y_curr[:split] - y_pred_train)**2).sum() / ((y_curr[:split] - y_curr[:split].mean())**2).sum()
    test_r2 = 1 - ((y_curr[split:] - y_pred_test)**2).sum() / ((y_curr[split:] - y_curr[split:].mean())**2).sum()
    print(f"  Vol model: Train R²={train_r2:.4f} Test R²={test_r2:.4f} ({time.time()-t0:.1f}s)")
    
    # Align: y_pred_all[t] = predicted vol for window [t+1, t+8]
    # We need y_pred_all aligned with y_dir[1:] (since we used y_vol[1:] as target)
    # So y_pred_all[i] corresponds to y_dir[i+1]
    y_pred_vol = np.zeros(n + 1)
    y_pred_vol[0] = y_vol[0]  # fill first with actual
    y_pred_vol[1:] = y_pred_all
    
    # --- Step 2: Define volatility regimes ---
    print("\n[2] Volatility regime analysis...", flush=True)
    p30, p50, p70 = np.percentile(y_pred_vol, [30, 50, 70])
    print(f"  p30={p30:.2e} p50={p50:.2e} p70={p70:.2e}")
    
    regimes = np.where(y_pred_vol < p30, 0, np.where(y_pred_vol < p70, 1, 2))
    
    print(f"\n{'Regime':8s} {'n':>8s} {'BUY%':>7s} {'SELL%':>7s} {'NEUT%':>8s} {'Vol':>11s}")
    print("-" * 49)
    for r, name in enumerate(['LOW', 'MID', 'HIGH']):
        mask = regimes == r
        n_r = mask.sum()
        vol_mean = y_pred_vol[mask].mean()
        print(f"{name:8s} {n_r:>8,d} {(y_dir[mask]==1).mean()*100:>6.2f}% "
              f"{(y_dir[mask]==-1).mean()*100:>6.2f}% {(y_dir[mask]==0).mean()*100:>7.2f}% "
              f"{vol_mean:>9.2e}")
    
    # --- Step 3: Direction models ---
    print("\n[3] Training direction classifiers...", flush=True)
    
    # Features: last-bar features (34) + predicted vol (1) = 35
    X_feat = np.column_stack([X[:, -1, :], y_pred_vol.reshape(-1, 1)])
    
    all_results = []
    
    for regime_name, train_mask, test_mask in [
        ("ALL DATA", np.arange(n_total) < split, np.arange(n_total) >= split),
        ("MID VOL  ", (regimes == 1) & (np.arange(n_total) < split),
                      (regimes == 1) & (np.arange(n_total) >= split)),
        ("LOW+MID  ", (regimes != 2) & (np.arange(n_total) < split),
                      (regimes != 2) & (np.arange(n_total) >= split)),
        ("MID+HIGH ", (regimes != 0) & (np.arange(n_total) < split),
                      (regimes != 0) & (np.arange(n_total) >= split)),
    ]:
        X_tr = X_feat[train_mask]
        y_tr = y_dir[train_mask]
        X_te = X_feat[test_mask]
        y_te = y_dir[test_mask]
        
        n_tr, n_te = len(X_tr), len(X_te)
        if n_tr < 1000 or n_te < 100:
            print(f"  {regime_name}: n_train={n_tr} n_test={n_te} SKIP (too small)")
            continue
        
        scaler_c = StandardScaler()
        X_tr_n = scaler_c.fit_transform(X_tr)
        X_te_n = scaler_c.transform(X_te)
        
        print(f"\n  {regime_name}: n_train={n_tr:,} n_test={n_te:,}")
        
        for target, y_bin_tr, y_bin_te in [
            ("BUY", (y_tr == 1).astype(float), (y_te == 1).astype(float)),
            ("SELL", (y_tr == -1).astype(float), (y_te == -1).astype(float)),
        ]:
            n_pos = int(y_bin_tr.sum())
            if n_pos < 200:
                print(f"    {target:5s}: n_pos={n_pos} SKIP (too few)")
                continue
            
            lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200, solver='saga',
                                     random_state=42, tol=1e-3)
            lr.fit(X_tr_n, y_bin_tr)
            
            pred = lr.predict_proba(X_te_n)[:, 1]
            auc = roc_auc_score(y_bin_te, pred)
            acc = accuracy_score(y_bin_te, (pred > 0.5).astype(float))
            
            print(f"    {target:5s}: AUC={auc:.4f} Acc={acc:.4f} "
                  f"(train_pos={n_pos:,})")
            
            all_results.append({
                'regime': regime_name.strip(),
                'target': target,
                'auc': float(auc),
                'acc': float(acc),
                'n_train': int(n_tr),
                'n_test': int(n_te),
            })
    
    # --- Step 4: Trade simulation ---
    print("\n[4] Trade simulation (MID vol only + direction signal)...", flush=True)
    test_mask = np.arange(n_total) >= split
    mid_test = (regimes == 1) & test_mask
    mid_train = (regimes == 1) & (~test_mask)
    
    X_m_tr = X_feat[mid_train]
    y_m_tr = y_dir[mid_train]
    X_m_te = X_feat[mid_test]
    y_m_te = y_dir[mid_test]
    
    if len(X_m_tr) > 1000 and len(X_m_te) > 100:
        scaler_s = StandardScaler()
        X_m_tr_n = scaler_s.fit_transform(X_m_tr)
        X_m_te_n = scaler_s.transform(X_m_te)
        
        buy_lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=500, solver='sag', random_state=42)
        buy_lr.fit(X_m_tr_n, (y_m_tr == 1).astype(float))
        buy_pred = buy_lr.predict_proba(X_m_te_n)[:, 1]
        
        sell_lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=500, solver='sag', random_state=42)
        sell_lr.fit(X_m_tr_n, (y_m_tr == -1).astype(float))
        sell_pred = sell_lr.predict_proba(X_m_te_n)[:, 1]
        
        for threshold in [0.55, 0.6, 0.7]:
            buy_signal = buy_pred > threshold
            sell_signal = sell_pred > threshold
            
            trades = buy_signal.astype(int) - sell_signal.astype(int)
            n_trades = (trades != 0).sum()
            
            # Forward returns: actual direction
            ret_fwd = np.where(y_m_te == 1, 1, np.where(y_m_te == -1, -1, 0))
            trade_returns = trades * ret_fwd
            
            win_rate = (trade_returns > 0).sum() / max(n_trades, 1)
            avg_ret = trade_returns[trades != 0].mean() if n_trades > 0 else 0
            total_ret = trade_returns.sum()
            
            print(f"  thresh={threshold:.2f}: trades={n_trades:>5d} "
                  f"({n_trades/len(trades)*100:5.1f}%) "
                  f"win={win_rate:.2%} avg_ret={avg_ret:+.4f} total={total_ret:+.1f}")
    
    # --- Summary ---
    print("\n" + "=" * 65)
    print("SUMMARY")
    print("=" * 65)
    for r in all_results:
        print(f"  {r['regime']:10s} {r['target']:5s}: AUC={r['auc']:.4f} "
              f"(n_train={r['n_train']:,})")
    
    print("\nDone!")

if __name__ == '__main__':
    main()
