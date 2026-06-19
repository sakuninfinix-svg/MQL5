#!/usr/bin/env python3
"""
Backtest: vol-filtered direction strategy on M15 data.
Uses per-symbol direction npz files for correct OHLCV mapping.
"""
import numpy as np, sys, os, time, json, pandas as pd
from pathlib import Path
from sklearn.linear_model import Ridge, LogisticRegression
from sklearn.preprocessing import StandardScaler

d = Path('/media/agus/40A604FEA604F666/Users/agsi/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/tools/output')

SEQ_LEN, FORECAST_BARS = 16, 8
DIR_THRESHOLD = 0.65
VOL_PCT = 70
BASE_LOT, INITIAL_CAPITAL = 0.01, 10000.0

SYMBOLS = {
    'eurusd': {'csv': 'eurusd_merged_m15_2020-2025.csv', 'count': 160008},
    'gbpusd': {'csv': 'gbpusd_m15_2020-2025.csv', 'count': 209832},
    'xauusd': {'csv': 'xauusd_m15_2020-2025.csv', 'count': 209832},
    'usdjpy': {'csv': 'usdjpy_m15_2020-2025.csv', 'count': 209832},
}

def load_symbol(sym_name, info):
    """Load direction npz + OHLCV for a symbol."""
    csv_path = d / info['csv']
    npz_path = d / f'direction_{sym_name}.npz'
    
    if not npz_path.exists() or not csv_path.exists():
        print(f"  SKIP {sym_name}")
        return None
    
    df = pd.read_csv(csv_path, parse_dates=['timestamp'])
    for c in ['open','high','low','close','volume']:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    df = df.dropna(subset=['open','high','low','close']).reset_index(drop=True)
    
    data = np.load(str(npz_path))
    X = data['X']      # (N, 16, 34)
    y_dir = data['y_dir']
    y_vol = data['y_vol']
    
    print(f"  {sym_name}: X={X.shape}, y_dir: BUY={(y_dir==1).sum()} SELL={(y_dir==-1).sum()} NEUT={(y_dir==0).sum()}")
    
    return {'X': X, 'y_dir': y_dir, 'y_vol': y_vol, 'df': df}

def prepare_features(X, y_vol):
    """Prepare vol and direction features."""
    N = len(X)
    X_last = X[:, -1, :]
    X_mean = X.mean(axis=1)
    X_std = X.std(axis=1)
    X_flat = np.column_stack([X_last, X_mean, X_std])
    
    y_prev = np.concatenate([[y_vol[0]], y_vol[:-1]])
    X_vol = np.column_stack([y_prev, X_flat])
    
    X_dir = np.column_stack([X_last, y_vol.reshape(-1, 1)])
    
    return X_vol, X_dir

def train_models(X_vol_tr, y_vol_tr, X_dir_tr, y_dir_tr):
    """Train vol + direction models."""
    # Vol model
    scaler_vol = StandardScaler()
    X_vol_tr_n = scaler_vol.fit_transform(X_vol_tr)
    vol_model = Ridge(alpha=100.0, solver='sag', max_iter=200, tol=1e-3, random_state=42)
    vol_model.fit(X_vol_tr_n, y_vol_tr)
    
    # Direction models on LOW+MID vol only
    p70 = np.percentile(y_vol_tr, VOL_PCT)
    lowmid = y_vol_tr < p70
    X_dir_f = X_dir_tr[lowmid]
    y_dir_f = y_dir_tr[lowmid]
    
    scaler_dir = StandardScaler()
    X_dir_f_n = scaler_dir.fit_transform(X_dir_f)
    
    buy_model = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200, solver='saga', random_state=42, tol=1e-3)
    buy_model.fit(X_dir_f_n, (y_dir_f == 1).astype(float))
    
    sell_model = LogisticRegression(C=1.0, class_weight='balanced', max_iter=200, solver='saga', random_state=42, tol=1e-3)
    sell_model.fit(X_dir_f_n, (y_dir_f == -1).astype(float))
    
    return vol_model, scaler_vol, buy_model, sell_model, scaler_dir, p70

def run_trades(sym_name, df, X_te, y_te, y_vol_te, vol_model, scaler_vol, buy_model, sell_model, scaler_dir, p70):
    """Run backtest on test set for one symbol."""
    close = df['close'].to_numpy()
    n_ohlcv = len(close)
    n_te = len(X_te)
    
    X_vol_te, X_dir_te = prepare_features(X_te, y_vol_te)
    X_vol_te_n = scaler_vol.transform(X_vol_te)
    X_dir_te_n = scaler_dir.transform(X_dir_te)
    
    vol_pred = vol_model.predict(X_vol_te_n)
    buy_prob = buy_model.predict_proba(X_dir_te_n)[:, 1]
    sell_prob = sell_model.predict_proba(X_dir_te_n)[:, 1]
    
    low_vol = vol_pred < p70
    max_prob = np.maximum(buy_prob, sell_prob)
    trade_mask = low_vol & (max_prob > DIR_THRESHOLD)
    trade_dir = np.where(buy_prob > sell_prob, 1, -1)
    
    trades = []
    balance = INITIAL_CAPITAL
    peak = INITIAL_CAPITAL
    total_win = total_loss = 0
    gross_profit = gross_loss = 0.0
    
    # Map: sequence index k uses OHLCV bars [k+17, k+24] for forecast
    # Since sequences start at SEQ_LEN (16) in OHLCV
    trade_idx_vals = np.where(trade_mask)[0]
    
    # Erronous overlapping logic removed — each trade is independent
    for idx in trade_idx_vals:
        entry_ohlcv = idx + SEQ_LEN + 1  # first bar after feature window
        exit_ohlcv = entry_ohlcv + FORECAST_BARS - 1  # last bar of forecast
        
        if exit_ohlcv >= n_ohlcv:
            continue
        
        direction = trade_dir[idx]
        entry_price = close[entry_ohlcv]
        exit_price = close[exit_ohlcv]
        ret_fwd = (exit_price - entry_price) / entry_price
        
        pred_vol = vol_pred[idx]
        pos_factor = 0.003 / max(pred_vol, 1e-10)
        pos_factor = max(0.1, min(pos_factor, 3.0))
        lot = BASE_LOT * pos_factor
        
        actual_ret = direction * ret_fwd
        pnl = lot * 100000 * actual_ret
        
        balance += pnl
        peak = max(peak, balance)
        
        if pnl > 0:
            total_win += 1
            gross_profit += pnl
        else:
            total_loss += 1
            gross_loss += abs(pnl)
        
        trades.append({
            'sym': sym_name,
            'direction': int(direction),
            'entry_price': float(entry_price),
            'exit_price': float(exit_price),
            'ret_fwd': float(ret_fwd),
            'actual_ret': float(actual_ret),
            'pred_vol': float(pred_vol),
            'pos_factor': float(pos_factor),
            'lot': float(lot),
            'pnl': float(pnl),
            'balance': float(balance),
        })
    
    return trades

def main():
    print("=" * 70)
    print("PASR BACKTEST: VOL-FILTERED DIRECTION")
    print("=" * 70)
    
    all_trades = []
    
    for sym_name, info in SYMBOLS.items():
        print(f"\n[{sym_name}]")
        sym_data = load_symbol(sym_name, info)
        if sym_data is None:
            continue
        
        X, y_dir, y_vol = sym_data['X'], sym_data['y_dir'], sym_data['y_vol']
        df = sym_data['df']
        N = len(X)
        split = int(N * 0.85)
        
        print(f"  Train: {split} / Test: {N - split}")
        
        # Prepare features
        X_vol, X_dir = prepare_features(X, y_vol)
        
        # Train on train set
        X_vol_tr, X_dir_tr = X_vol[:split], X_dir[:split]
        y_vol_tr, y_dir_tr = y_vol[:split], y_dir[:split]
        
        vol_model, scaler_vol, buy_model, sell_model, scaler_dir, p70 = train_models(
            X_vol_tr, y_vol_tr, X_dir_tr, y_dir_tr
        )
        
        print(f"  Vol P70={p70:.2e}, Vol R² train={vol_model.score(scaler_vol.transform(X_vol_tr), y_vol_tr):.4f}")
        
        # Test on test set
        X_te, y_te, y_vol_te = X[split:], y_dir[split:], y_vol[split:]
        trades = run_trades(sym_name, df, X_te, y_te, y_vol_te,
                           vol_model, scaler_vol, buy_model, sell_model, scaler_dir, p70)
        
        print(f"  Trades: {len(trades)}")
        all_trades.extend(trades)
    
    # Aggregate results
    print(f"\n{'='*70}")
    print("AGGREGATE RESULTS")
    print(f"{'='*70}")
    
    if not all_trades:
        print("NO TRADES")
        return
    
    n_trades = len(all_trades)
    total_pnl = sum(t['pnl'] for t in all_trades)
    wins = [t for t in all_trades if t['pnl'] > 0]
    losses = [t for t in all_trades if t['pnl'] < 0]
    win_rate = len(wins) / max(n_trades, 1)
    gross_profit = sum(t['pnl'] for t in wins)
    gross_loss = sum(abs(t['pnl']) for t in losses)
    profit_factor = gross_profit / max(gross_loss, 1e-10)
    avg_win = gross_profit / max(len(wins), 1)
    avg_loss = gross_loss / max(len(losses), 1)
    
    pnl_arr = np.array([t['pnl'] for t in all_trades])
    sharpe = pnl_arr.mean() / max(pnl_arr.std(), 1e-10) * np.sqrt(365*24*4)
    
    final_balance = INITIAL_CAPITAL + total_pnl
    peak_balance = INITIAL_CAPITAL
    running_balance = INITIAL_CAPITAL
    max_dd = 0.0
    for t in all_trades:
        running_balance += t['pnl']
        peak_balance = max(peak_balance, running_balance)
        dd = (peak_balance - running_balance) / peak_balance
        max_dd = max(max_dd, dd)
    
    print(f"  Total trades: {n_trades:,}")
    print(f"  Win rate: {win_rate:.1%} ({len(wins)}W/{len(losses)}L)")
    print(f"  Profit factor: {profit_factor:.2f}")
    print(f"  Avg win: ${avg_win:.2f}")
    print(f"  Avg loss: ${avg_loss:.2f}")
    print(f"  Gross PnL: ${total_pnl:.2f}")
    print(f"  Final balance: ${final_balance:.2f}")
    print(f"  Return: {(final_balance/INITIAL_CAPITAL-1)*100:.1f}%")
    print(f"  Max drawdown: {max_dd*100:.1f}%")
    print(f"  Sharpe: {sharpe:.2f}")
    
    # Symbol breakdown
    sym_stats = {}
    for t in all_trades:
        s = t['sym']
        if s not in sym_stats:
            sym_stats[s] = {'trades': [], 'pnl': []}
        sym_stats[s]['trades'].append(t)
        sym_stats[s]['pnl'].append(t['pnl'])
    
    print(f"\n{'='*70}")
    print("SYMBOL BREAKDOWN")
    print(f"{'='*70}")
    print(f"  {'Symbol':10s} {'Trades':>8s} {'WinRate':>9s} {'AvgPnl':>9s} {'Total':>10s}")
    print(f"  {'-'*50}")
    for sym_name, stats in sorted(sym_stats.items()):
        n = len(stats['trades'])
        wr = sum(1 for p in stats['pnl'] if p > 0) / max(n, 1)
        avg = np.mean(stats['pnl'])
        total = sum(stats['pnl'])
        print(f"  {sym_name:10s} {n:>8,d} {wr:>8.1%} ${avg:>+7.2f} ${total:>+8.2f}")
    
    # Predicted vol decile analysis
    all_vols = np.array([t['pred_vol'] for t in all_trades])
    print(f"\n{'='*70}")
    print("PERFORMANCE BY PREDICTED VOL DECILE")
    print(f"{'='*70}")
    print(f"  {'Decile':8s} {'Trades':>8s} {'WinRate':>9s} {'AvgRet':>10s} {'AvgPnl':>9s}")
    print(f"  {'-'*50}")
    
    deciles = np.percentile(all_vols, np.arange(10, 100, 10))
    for dec in range(10):
        if dec == 0:
            mask = all_vols <= deciles[0]
        elif dec == 9:
            mask = all_vols > deciles[8]
        else:
            mask = (all_vols > deciles[dec-1]) & (all_vols <= deciles[dec])
        
        dec_trades = [t for i, t in enumerate(all_trades) if mask[i]]
        if not dec_trades:
            continue
        dec_wr = sum(1 for t in dec_trades if t['pnl'] > 0) / len(dec_trades)
        dec_ret = np.mean([t['actual_ret'] for t in dec_trades])
        dec_pnl = np.mean([t['pnl'] for t in dec_trades])
        print(f"  D{dec+1:2d}:     {len(dec_trades):>8,d} {dec_wr:>8.1%} {dec_ret:>+9.4f} ${dec_pnl:>+8.2f}")
    
    # Save
    results = {
        'n_trades': n_trades,
        'win_rate': float(win_rate),
        'profit_factor': float(profit_factor),
        'avg_win': float(avg_win),
        'avg_loss': float(avg_loss),
        'total_pnl': float(total_pnl),
        'return_pct': float((final_balance/INITIAL_CAPITAL-1)*100),
        'max_drawdown_pct': float(max_dd*100),
        'sharpe': float(sharpe),
        'symbol_breakdown': {s: {
            'trades': len(st['trades']),
            'win_rate': float(sum(1 for p in st['pnl'] if p > 0) / max(len(st['pnl']), 1)),
            'avg_pnl': float(np.mean(st['pnl'])),
            'total_pnl': float(sum(st['pnl'])),
        } for s, st in sym_stats.items()},
    }
    with open(str(d / 'backtest_results.json'), 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to backtest_results.json")
    print("Done!")

if __name__ == '__main__':
    main()
