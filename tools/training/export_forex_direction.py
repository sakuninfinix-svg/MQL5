#!/usr/bin/env python3
"""
Train and export per-symbol direction models for forex pairs only.
Excludes XAUUSD (commodity, different dynamics).

For each symbol (EURUSD, GBPUSD, USDJPY):
  1. Train BUY/SELL logistic regression (34 AI features + vol)
  2. Apply LOW+MID vol filter (exclude top 30% vol)
  3. Export .bin with per-symbol scaler + weights
  4. Also export combined forex model for generalization

.bin format (142 floats, same as before):
  [0]       = model_type (int32)
  [1..36]   = BUY weights[35] + bias
  [37..72]  = SELL weights[35] + bias
  [73..107] = scaler_mean[35]
  [108..142]= scaler_scale[35]
"""
import numpy as np, sys, os, time, struct, json
from pathlib import Path
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, accuracy_score

d = Path('/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output')

FOREX_SYMBOLS = ['eurusd', 'gbpusd', 'usdjpy']
VOL_PCT = 70  # exclude top 30% vol (HIGH vol regime)

def load_symbol(sym_name):
    npz_path = d / f'direction_{sym_name}.npz'
    if not npz_path.exists():
        print(f"  SKIP {sym_name}: {npz_path.name} not found")
        return None
    data = np.load(str(npz_path))
    X = data['X']
    y_dir = data['y_dir']
    y_vol = data['y_vol']
    print(f"  {sym_name}: X={X.shape}, "
          f"BUY={(y_dir==1).sum()} SELL={(y_dir==-1).sum()} NEUT={(y_dir==0).sum()}")
    return {'X': X, 'y_dir': y_dir, 'y_vol': y_vol}

def train_and_export(sym_name, data):
    X = data['X']
    y_dir = data['y_dir']
    y_vol = data['y_vol']
    n_total = len(y_dir)
    
    # Split
    split = int(n_total * 0.85)
    
    # Features: last-bar (34) + vol (1) = 35
    X_feat = np.column_stack([X[:, -1, :], y_vol.reshape(-1, 1)])
    
    # LOW+MID vol filter (use training set percentile)
    p70 = np.percentile(y_vol[:split], VOL_PCT)
    mask_train = y_vol[:split] < p70
    mask_test = y_vol[split:] < p70
    
    X_tr = X_feat[:split][mask_train]
    y_tr = y_dir[:split][mask_train]
    X_te = X_feat[split:][mask_test]
    y_te = y_dir[split:][mask_test]
    
    print(f"    Filtered (vol<P70={p70:.2e}): train={len(X_tr):,} test={len(X_te):,}")
    
    # Scale
    scaler = StandardScaler()
    X_tr_n = scaler.fit_transform(X_tr)
    X_te_n = scaler.transform(X_te)
    
    results = {}
    
    for target_name, target_val in [('BUY', 1), ('SELL', -1)]:
        y_bin_tr = (y_tr == target_val).astype(float)
        y_bin_te = (y_te == target_val).astype(float)
        
        n_pos_tr = int(y_bin_tr.sum())
        if n_pos_tr < 200:
            print(f"    {target_name}: n_pos={n_pos_tr} SKIP")
            results[target_name] = None
            continue
        
        t0 = time.time()
        lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200,
                                 solver='saga', random_state=42, tol=1e-3)
        lr.fit(X_tr_n, y_bin_tr)
        
        pred = lr.predict_proba(X_te_n)[:, 1]
        auc = roc_auc_score(y_bin_te, pred)
        acc = accuracy_score(y_bin_te, (pred > 0.5).astype(float))
        
        print(f"    {target_name}: AUC={auc:.4f} Acc={acc:.4f} "
              f"(train_pos={n_pos_tr:,}) [{time.time()-t0:.1f}s]")
        
        results[target_name] = {
            'coef': lr.coef_[0].astype(np.float32),
            'intercept': np.float32(lr.intercept_[0]),
            'auc': float(auc),
            'acc': float(acc),
        }
    
    if results['BUY'] is None or results['SELL'] is None:
        print(f"    SKIP export: insufficient positive samples")
        return None
    
    # Export .bin
    buy_w = results['BUY']['coef']
    buy_b = results['BUY']['intercept']
    sell_w = results['SELL']['coef']
    sell_b = results['SELL']['intercept']
    scaler_mean = scaler.mean_.astype(np.float32)
    scaler_scale = scaler.scale_.astype(np.float32)
    
    model_type = np.int32(1)  # direction model
    
    out_name = f'PASR_dir_{sym_name}.bin'
    out_path = str(d / out_name)
    with open(out_path, 'wb') as f:
        f.write(struct.pack('i', model_type))
        f.write(buy_w.tobytes())
        f.write(struct.pack('f', buy_b))
        f.write(sell_w.tobytes())
        f.write(struct.pack('f', sell_b))
        f.write(scaler_mean.tobytes())
        f.write(scaler_scale.tobytes())
    
    return {
        'symbol': sym_name,
        'p70_threshold': float(p70),
        'n_train': int(mask_train.sum()),
        'n_test': int(mask_test.sum()),
        'buy_auc': results['BUY']['auc'],
        'buy_acc': results['BUY']['acc'],
        'sell_auc': results['SELL']['auc'],
        'sell_acc': results['SELL']['acc'],
        'export_path': out_name,
    }

def train_combined(data_dict):
    """Train a single model on combined forex data."""
    print(f"\n  [COMBINED FOREX]")
    X_all, y_all, v_all = [], [], []
    for sym_name in FOREX_SYMBOLS:
        if sym_name not in data_dict:
            continue
        X_all.append(data_dict[sym_name]['X'])
        y_all.append(data_dict[sym_name]['y_dir'])
        v_all.append(data_dict[sym_name]['y_vol'])
    
    X = np.concatenate(X_all)
    y_dir = np.concatenate(y_all)
    y_vol = np.concatenate(v_all)
    
    n_total = len(y_dir)
    print(f"    Combined: X={X.shape}, "
          f"BUY={(y_dir==1).sum()} SELL={(y_dir==-1).sum()} NEUT={(y_dir==0).sum()}")
    
    split = int(n_total * 0.85)
    X_feat = np.column_stack([X[:, -1, :], y_vol.reshape(-1, 1)])
    
    p70 = np.percentile(y_vol[:split], VOL_PCT)
    mask_train = y_vol[:split] < p70
    mask_test = y_vol[split:] < p70
    
    X_tr = X_feat[:split][mask_train]
    y_tr = y_dir[:split][mask_train]
    X_te = X_feat[split:][mask_test]
    y_te = y_dir[split:][mask_test]
    
    print(f"    Filtered (vol<P70={p70:.2e}): train={len(X_tr):,} test={len(X_te):,}")
    
    scaler = StandardScaler()
    X_tr_n = scaler.fit_transform(X_tr)
    X_te_n = scaler.transform(X_te)
    
    results = {}
    for target_name, target_val in [('BUY', 1), ('SELL', -1)]:
        y_bin_tr = (y_tr == target_val).astype(float)
        y_bin_te = (y_te == target_val).astype(float)
        
        lr = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200,
                                 solver='saga', random_state=42, tol=1e-3)
        lr.fit(X_tr_n, y_bin_tr)
        
        pred = lr.predict_proba(X_te_n)[:, 1]
        auc = roc_auc_score(y_bin_te, pred)
        acc = accuracy_score(y_bin_te, (pred > 0.5).astype(float))
        
        print(f"    {target_name}: AUC={auc:.4f} Acc={acc:.4f}")
        results[target_name] = {
            'coef': lr.coef_[0].astype(np.float32),
            'intercept': np.float32(lr.intercept_[0]),
            'auc': float(auc),
            'acc': float(acc),
        }
    
    # Export
    buy_w = results['BUY']['coef']
    buy_b = results['BUY']['intercept']
    sell_w = results['SELL']['coef']
    sell_b = results['SELL']['intercept']
    scaler_mean = scaler.mean_.astype(np.float32)
    scaler_scale = scaler.scale_.astype(np.float32)
    
    model_type = np.int32(2)  # combined forex direction model
    out_path = str(d / 'PASR_dir_forex.bin')
    with open(out_path, 'wb') as f:
        f.write(struct.pack('i', model_type))
        f.write(buy_w.tobytes())
        f.write(struct.pack('f', buy_b))
        f.write(sell_w.tobytes())
        f.write(struct.pack('f', sell_b))
        f.write(scaler_mean.tobytes())
        f.write(scaler_scale.tobytes())
    
    return {
        'symbol': 'forex_combined',
        'p70_threshold': float(p70),
        'n_train': int(mask_train.sum()),
        'n_test': int(mask_test.sum()),
        'buy_auc': results['BUY']['auc'],
        'buy_acc': results['BUY']['acc'],
        'sell_auc': results['SELL']['auc'],
        'sell_acc': results['SELL']['acc'],
        'export_path': 'PASR_dir_forex.bin',
    }

def main():
    print("=" * 60)
    print("PER-SYMBOL FOREX DIRECTION MODEL EXPORT")
    print("=" * 60)
    
    # Load data
    data_dict = {}
    for sym_name in FOREX_SYMBOLS:
        print(f"\nLoading {sym_name}...")
        data = load_symbol(sym_name)
        if data is not None:
            data_dict[sym_name] = data
    
    if not data_dict:
        print("No data loaded!")
        return
    
    # Train and export per-symbol
    reports = []
    for sym_name in sorted(data_dict.keys()):
        print(f"\n{'='*50}")
        print(f"Training {sym_name}...")
        print(f"{'='*50}")
        report = train_and_export(sym_name, data_dict[sym_name])
        if report:
            reports.append(report)
    
    # Also train combined forex model
    print(f"\n{'='*50}")
    print(f"Training COMBINED FOREX model...")
    print(f"{'='*50}")
    combined_report = train_combined(data_dict)
    if combined_report:
        reports.append(combined_report)
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"{'Model':20s} {'BUY AUC':>9s} {'SELL AUC':>9s} {'N Train':>9s} {'File':>24s}")
    print(f"{'-'*75}")
    for r in reports:
        ba = f"{r['buy_auc']:.4f}" if r['buy_auc'] else 'SKIP'
        sa = f"{r['sell_auc']:.4f}" if r['sell_auc'] else 'SKIP'
        print(f"{r['symbol']:20s} {ba:>9s} {sa:>9s} {r['n_train']:>9,d} {r['export_path']:>24s}")
    
    # Save report
    with open(str(d / 'forex_direction_report.json'), 'w') as f:
        json.dump(reports, f, indent=2)
    
    # Verify files
    print(f"\nExported models:")
    for r in reports:
        fp = d / r['export_path']
        if fp.exists():
            print(f"  {r['export_path']:30s} {fp.stat().st_size:>6,} bytes")
    
    print("\nDone!")

if __name__ == '__main__':
    main()
