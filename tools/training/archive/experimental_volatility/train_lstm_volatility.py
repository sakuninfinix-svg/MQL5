#!/usr/bin/env python3
"""
PASR LSTM Volatility Predictor
==============================
Predicts future realized volatility from feature sequences using LSTM.
Architecture: Feature(34) -> LSTM(64) -> Dense(16) -> Dense(1)

Key insight: Volatility clustering is well-documented in FX markets.
Instead of predicting direction (which is ~random walk at H1+), predict
volatility magnitude — this has known autocorrelation structure.

Usage:
  python3 train_lstm_volatility.py --npz output/volatility_h1_sequences.npz --out output
"""
import numpy as np
import json, os, sys, struct
from pathlib import Path
from datetime import datetime, timezone

FEATURE_DIM = 34
HIDDEN_DIM = 32
DENSE_DIM = 12
DROPOUT = 0.2
LR = 0.001
EPOCHS = 300
BATCH_SIZE = 64
PATIENCE = 50

def sigmoid(x):
    return np.where(x >= 0, 1.0 / (1.0 + np.exp(-np.clip(x, -500, 500))),
                    np.exp(np.clip(x, -500, 500)) / (1.0 + np.exp(np.clip(x, -500, 500))))

def tanh(x):
    return np.tanh(x)

def relu(x):
    return np.maximum(0, x)

def he_init(fan_in, fan_out):
    return np.random.normal(0, np.sqrt(2.0 / max(fan_in, 1)), (fan_in, fan_out)).astype(np.float32)

def glorot_init(fan_in, fan_out):
    limit = np.sqrt(6.0 / max(fan_in + fan_out, 1))
    return np.random.uniform(-limit, limit, (fan_in, fan_out)).astype(np.float32)

# ======================================================================
# LSTM Cell
# ======================================================================
class LSTMCell:
    def __init__(self, input_dim, hidden_dim):
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim
        self.W_i = glorot_init(input_dim, hidden_dim)
        self.U_i = glorot_init(hidden_dim, hidden_dim)
        self.b_i = np.zeros(hidden_dim, dtype=np.float32)
        self.W_f = glorot_init(input_dim, hidden_dim)
        self.U_f = glorot_init(hidden_dim, hidden_dim)
        self.b_f = np.zeros(hidden_dim, dtype=np.float32)
        self.W_c = glorot_init(input_dim, hidden_dim)
        self.U_c = glorot_init(hidden_dim, hidden_dim)
        self.b_c = np.zeros(hidden_dim, dtype=np.float32)
        self.W_o = glorot_init(input_dim, hidden_dim)
        self.U_o = glorot_init(hidden_dim, hidden_dim)
        self.b_o = np.zeros(hidden_dim, dtype=np.float32)

    def forward(self, x, h_prev, c_prev):
        i = sigmoid(x @ self.W_i + h_prev @ self.U_i + self.b_i)
        f = sigmoid(x @ self.W_f + h_prev @ self.U_f + self.b_f)
        c_tilde = tanh(x @ self.W_c + h_prev @ self.U_c + self.b_c)
        c = f * c_prev + i * c_tilde
        o = sigmoid(x @ self.W_o + h_prev @ self.U_o + self.b_o)
        h = o * tanh(c)
        return h, c, {'i': i, 'f': f, 'c_tilde': c_tilde, 'c': c, 'o': o, 'x': x, 'h_prev': h_prev, 'c_prev': c_prev}

    def backward(self, dh, dc_next, cache):
        i, f, c_tilde, c, o = cache['i'], cache['f'], cache['c_tilde'], cache['c'], cache['o']
        x, h_prev, c_prev = cache['x'], cache['h_prev'], cache['c_prev']

        do = dh * tanh(c)
        dc = dc_next + o * dh * (1 - tanh(c) ** 2)
        di = dc * c_tilde
        df = dc * c_prev
        dc_tilde = dc * i

        di = di * i * (1 - i)
        df = df * f * (1 - f)
        do = do * o * (1 - o)
        dc_tilde = dc_tilde * (1 - c_tilde ** 2)

        dW_i = x.T @ di
        dU_i = h_prev.T @ di
        db_i = di.sum(axis=0)
        dW_f = x.T @ df
        dU_f = h_prev.T @ df
        db_f = df.sum(axis=0)
        dW_c = x.T @ dc_tilde
        dU_c = h_prev.T @ dc_tilde
        db_c = dc_tilde.sum(axis=0)
        dW_o = x.T @ do
        dU_o = h_prev.T @ do
        db_o = do.sum(axis=0)

        dh_prev = (di @ self.U_i.T + df @ self.U_f.T + dc_tilde @ self.U_c.T + do @ self.U_o.T)
        dc_prev = dc * f

        grads = {'W_i': dW_i, 'U_i': dU_i, 'b_i': db_i,
                 'W_f': dW_f, 'U_f': dU_f, 'b_f': db_f,
                 'W_c': dW_c, 'U_c': dU_c, 'b_c': db_c,
                 'W_o': dW_o, 'U_o': dU_o, 'b_o': db_o}
        return dh_prev, dc_prev, grads

    def get_params(self):
        return {k: getattr(self, k) for k in
                ['W_i','U_i','b_i','W_f','U_f','b_f','W_c','U_c','b_c','W_o','U_o','b_o']}

    def set_params(self, params):
        for k, v in params.items():
            setattr(self, k, v)

# ======================================================================
# Model: LSTM(1 layer) -> Dense -> Output
# ======================================================================
class LSTMVolatilityModel:
    def __init__(self, seed=42):
        np.random.seed(seed)
        self.seed = seed
        self.cell = LSTMCell(FEATURE_DIM, HIDDEN_DIM)
        self.W_dense = he_init(HIDDEN_DIM, DENSE_DIM)
        self.b_dense = np.zeros(DENSE_DIM, dtype=np.float32)
        self.W_out = he_init(DENSE_DIM, 1)
        self.b_out = np.zeros(1, dtype=np.float32)

    def forward(self, X, training=True):
        batch, seq_len = X.shape[0], X.shape[1]
        h = np.zeros((batch, HIDDEN_DIM), dtype=np.float32)
        c = np.zeros((batch, HIDDEN_DIM), dtype=np.float32)
        caches = []

        for t in range(seq_len):
            h, c, cache = self.cell.forward(X[:, t, :], h, c)
            caches.append(cache)

        last_h = h
        if training and DROPOUT > 0:
            mask = (np.random.random(last_h.shape) > DROPOUT).astype(np.float32)
            last_h = last_h * mask / (1.0 - DROPOUT)

        dense = relu(last_h @ self.W_dense + self.b_dense)
        if training and DROPOUT > 0:
            mask = (np.random.random(dense.shape) > DROPOUT).astype(np.float32)
            dense = dense * mask / (1.0 - DROPOUT)

        out = dense @ self.W_out + self.b_out
        return out.flatten(), {'h': h, 'c': c, 'caches': caches, 'dense': dense, 'last_h': last_h}

    def predict(self, X):
        out, _ = self.forward(X, training=False)
        return out

    def mse(self, y_pred, y_true):
        return np.mean((y_pred - y_true) ** 2)

    def mae(self, y_pred, y_true):
        return np.mean(np.abs(y_pred - y_true))

# ======================================================================
# BPTT Gradient Computation (single LSTM layer)
# ======================================================================
def compute_gradients(model, X, y):
    batch, seq_len = X.shape[0], X.shape[1]
    out, cache = model.forward(X, training=True)
    loss = model.mse(out, y)

    d_out = 2 * (out - y) / len(y)
    d_dense = d_out.reshape(-1, 1) @ model.W_out.T

    grads = {}
    grads['W_out'] = (cache['dense'].T @ d_out.reshape(-1, 1)).astype(np.float32)
    grads['b_out'] = np.array([d_out.sum()], dtype=np.float32)

    d_dense = d_dense * (cache['dense'] > 0).astype(np.float32)
    grads['W_dense'] = (cache['last_h'].T @ d_dense).astype(np.float32)
    grads['b_dense'] = d_dense.sum(axis=0).astype(np.float32)

    dh = d_dense @ model.W_dense.T

    cell_grads = {k: np.zeros_like(getattr(model.cell, k))
                  for k in ['W_i','U_i','b_i','W_f','U_f','b_f','W_c','U_c','b_c','W_o','U_o','b_o']}

    dc = np.zeros((batch, HIDDEN_DIM), dtype=np.float32)

    for t in reversed(range(seq_len)):
        dh_t = dh if t == seq_len - 1 else dh + dh_from_above
        dh_prev, dc, g = model.cell.backward(dh_t, dc, cache['caches'][t])
        for k, v in g.items():
            cell_grads[k] += v
        dh_from_above = dh_prev

    for k, v in cell_grads.items():
        grads[k] = v

    return grads, loss

# ======================================================================
# Adam Optimizer
# ======================================================================
class Adam:
    def __init__(self, lr=LR, beta1=0.9, beta2=0.999, eps=1e-8, wd=1e-5):
        self.lr = lr
        self.beta1, self.beta2, self.eps, self.wd = beta1, beta2, eps, wd
        self.t = 0
        self.m, self.v = {}, {}

    def init_params(self, params):
        for k, v in params.items():
            self.m[k] = np.zeros_like(v)
            self.v[k] = np.zeros_like(v)

    def step(self, params, grads, max_norm=5.0):
        self.t += 1
        lr_t = self.lr * np.sqrt(1 - self.beta2 ** self.t) / (1 - self.beta1 ** self.t)
        gn = np.sqrt(np.sum(np.concatenate([g.ravel() for g in grads.values()]) ** 2))
        if gn > max_norm:
            factor = max_norm / max(gn, 1e-10)
            grads = {k: v * factor for k, v in grads.items()}
        new = {}
        for k in params:
            g = grads.get(k, np.zeros_like(params[k]))
            if self.wd > 0:
                g = g + self.wd * params[k]
            self.m[k] = self.beta1 * self.m[k] + (1 - self.beta1) * g
            self.v[k] = self.beta2 * self.v[k] + (1 - self.beta2) * (g ** 2)
            new[k] = params[k] - lr_t * self.m[k] / (np.sqrt(self.v[k]) + self.eps)
        return new

def collect_params(model):
    p = model.cell.get_params()
    p.update({'W_dense': model.W_dense, 'b_dense': model.b_dense,
              'W_out': model.W_out, 'b_out': model.b_out})
    return p

def set_params(model, params):
    cell_p = {k: v for k, v in params.items()
              if k in ['W_i','U_i','b_i','W_f','U_f','b_f','W_c','U_c','b_c','W_o','U_o','b_o']}
    model.cell.set_params(cell_p)
    model.W_dense = params['W_dense']
    model.b_dense = params['b_dense']
    model.W_out = params['W_out']
    model.b_out = params['b_out']

# ======================================================================
# Training
# ======================================================================
def train_model(X, y, seed=42):
    np.random.seed(seed)
    n = len(X)
    split = int(n * 0.8)
    idx = np.random.permutation(n)
    X_train, y_train = X[idx[:split]], y[idx[:split]]
    X_test, y_test = X[idx[split:]], y[idx[split:]]

    y_mu, y_sig = y_train.mean(), max(y_train.std(), 1e-10)
    y_train_n = (y_train - y_mu) / y_sig
    y_test_n = (y_test - y_mu) / y_sig

    model = LSTMVolatilityModel(seed=seed)
    params = collect_params(model)
    opt = Adam(lr=LR)
    opt.init_params(params)

    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")
    print(f"  y: mean={y_mu:.6e}, std={y_sig:.6e}")
    print(f"  Model: LSTM(1x{HIDDEN_DIM}) -> Dense({DENSE_DIM}) -> 1")

    best_loss = float('inf')
    best_params = None
    no_improve = 0

    for epoch in range(EPOCHS):
        perm = np.random.permutation(len(X_train))
        X_s, y_s = X_train[perm], y_train_n[perm]
        epoch_loss = 0.0
        n_batches = 0

        for i in range(0, len(X_train), BATCH_SIZE):
            X_b, y_b = X_s[i:i+BATCH_SIZE], y_s[i:i+BATCH_SIZE]
            grads, l = compute_gradients(model, X_b, y_b)
            params = opt.step(params, grads)
            set_params(model, params)
            epoch_loss += l
            n_batches += 1

        pred_test = model.predict(X_test)
        val_mse = model.mse(pred_test, y_test_n)
        val_mae = model.mae(pred_test, y_test_n)

        if epoch % 20 == 0 or epoch == EPOCHS - 1:
            print(f"    Epoch {epoch:3d}: loss={epoch_loss/n_batches:.6f} val_mse={val_mse:.6f} val_mae={val_mae:.6f}")

        if val_mse < best_loss:
            best_loss = val_mse
            best_params = {k: v.copy() for k, v in params.items()}
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= PATIENCE:
                print(f"    Early stop at epoch {epoch}")
                break

    if best_params:
        set_params(model, best_params)

    pred_train = model.predict(X_train)
    pred_test = model.predict(X_test)

    # Denormalize
    p_test = pred_test * y_sig + y_mu
    y_test_d = y_test_n * y_sig + y_mu

    top_k = max(len(p_test) // 10, 1)
    top_idx = np.argsort(-pred_test)[:top_k]
    bot_idx = np.argsort(pred_test)[:top_k]

    print(f"\n  Results:")
    print(f"    Train MSE: {model.mse(pred_train, y_train_n):.6f}")
    print(f"    Test MSE:  {model.mse(pred_test, y_test_n):.6f}")
    print(f"    Test MAE:  {model.mae(pred_test, y_test_n):.6f}")
    print(f"    Top 10% predicted vol: {y_test_d[top_idx].mean():.6e}")
    print(f"    Bottom 10%:             {y_test_d[bot_idx].mean():.6e}")
    ratio = y_test_d[top_idx].mean() / max(y_test_d[bot_idx].mean(), 1e-15)
    print(f"    Spread ratio: {ratio:.3f}x")

    # Correlation: higher is better for volatility forecasting
    corr = np.corrcoef(pred_test, y_test_n)[0, 1]
    print(f"    Pearson r: {corr:.4f}")

    metrics = {
        'seed': seed,
        'n_train': len(X_train),
        'n_test': len(X_test),
        'train_mse': float(model.mse(pred_train, y_train_n)),
        'test_mse': float(model.mse(pred_test, y_test_n)),
        'test_mae': float(model.mae(pred_test, y_test_n)),
        'top10_vol': float(y_test_d[top_idx].mean()),
        'bottom10_vol': float(y_test_d[bot_idx].mean()),
        'spread_ratio': float(ratio),
        'pearson_r': float(corr),
        'y_mean': float(y_mu),
        'y_std': float(y_sig),
    }
    return model, metrics

def export_mql5(model, path, y_mu, y_sig):
    p = collect_params(model)
    vals = [1, 1, HIDDEN_DIM, FEATURE_DIM, DENSE_DIM]
    for k in ['W_i','U_i','b_i','W_f','U_f','b_f','W_c','U_c','b_c','W_o','U_o','b_o']:
        vals.extend(p[k].ravel().tolist())
    vals.extend(model.W_dense.ravel().tolist())
    vals.extend(model.b_dense.ravel().tolist())
    vals.extend(model.W_out.ravel().tolist())
    vals.extend(model.b_out.ravel().tolist())
    vals.append(float(y_mu))
    vals.append(float(y_sig))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(struct.pack(f'{len(vals)}f', *vals))
    print(f"  Exported {path} ({len(vals)} floats)")

def cli_main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--npz", required=True)
    parser.add_argument("--out", default="output")
    parser.add_argument("--seeds", default="42,137,73")
    parser.add_argument("--epochs", type=int, default=200)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--batch-size", type=int, default=128)
    args = parser.parse_args()

    global EPOCHS, LR, BATCH_SIZE
    EPOCHS, LR, BATCH_SIZE = args.epochs, args.lr, args.batch_size

    print("=" * 60)
    print("PASR LSTM Volatility Predictor")
    print("=" * 60)
    print(f"\nLoading {args.npz}...")
    data = np.load(args.npz)
    X, y = data['X'], data['y']
    print(f"X: {X.shape}, y: {y.shape}")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_npz": os.path.abspath(args.npz),
        "type": "lstm_volatility_regression",
        "architecture": f"LSTM(1x{HIDDEN_DIM})->Dense({DENSE_DIM})->1",
        "models": []
    }

    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]
    for idx, seed in enumerate(seeds):
        print(f"\n--- Model {idx+1}/{len(seeds)} (seed={seed}) ---")
        model, metrics = train_model(X, y, seed)
        fname = out_dir / f"PASR_lstm_vol_m{idx}.bin"
        export_mql5(model, str(fname), metrics['y_mean'], metrics['y_std'])
        metrics["file"] = fname.name
        report["models"].append(metrics)

    report_path = out_dir / "lstm_volatility_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport: {report_path}")

    best = max(report["models"], key=lambda m: m.get('pearson_r', -1))
    print(f"\nBest: {best['file']} (seed={best['seed']}, r={best['pearson_r']:.4f}, spread={best['spread_ratio']:.2f}x)")

if __name__ == '__main__':
    cli_main()

    print("=" * 60)
    print("PASR LSTM Volatility Predictor")
    print("=" * 60)
    print(f"\nLoading {args.npz}...")
    data = np.load(args.npz)
    X, y = data['X'], data['y']
    print(f"X: {X.shape}, y: {y.shape}")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_npz": os.path.abspath(args.npz),
        "type": "lstm_volatility_regression",
        "architecture": f"LSTM(1x{HIDDEN_DIM})->Dense({DENSE_DIM})->1",
        "models": []
    }

    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]
    for idx, seed in enumerate(seeds):
        print(f"\n--- Model {idx+1}/{len(seeds)} (seed={seed}) ---")
        model, metrics = train_model(X, y, seed)
        fname = out_dir / f"PASR_lstm_vol_m{idx}.bin"
        export_mql5(model, str(fname), metrics['y_mean'], metrics['y_std'])
        metrics["file"] = fname.name
        report["models"].append(metrics)

    report_path = out_dir / "lstm_volatility_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport: {report_path}")

    best = max(report["models"], key=lambda m: m.get('pearson_r', -1))
    print(f"\nBest: {best['file']} (seed={best['seed']}, r={best['pearson_r']:.4f}, spread={best['spread_ratio']:.2f}x)")
