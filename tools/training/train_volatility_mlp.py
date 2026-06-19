#!/usr/bin/env python3
"""
PASR Volatility MLP Predictor
==============================
Predicts future realized volatility from flattened feature sequences.
Architecture: WindowedFeatures(34×16 + 34×4stats = ~680) -> 128 -> 64 -> 1

Key insight: Instead of BPTT (too slow in pure NumPy), flatten the sequence
window + aggregate statistics to capture temporal structure efficiently.

Target: Future realized volatility (std of log returns over next 8 bars)

Usage:
  python3 train_volatility_mlp.py --npz output/volatility_h1_seqs16.npz --out output
"""
import numpy as np
import json, os, sys, struct
from pathlib import Path
from datetime import datetime, timezone

HIDDEN1 = 64
HIDDEN2 = 32
DROPOUT = 0.1
LR = 0.001
EPOCHS = 200
BATCH_SIZE = 512
PATIENCE = 60

def relu(x):
    return np.maximum(0, x)

def sigmoid(x):
    return np.where(x >= 0, 1.0 / (1.0 + np.exp(-np.clip(x, -500, 500))),
                    np.exp(np.clip(x, -500, 500)) / (1.0 + np.exp(np.clip(x, -500, 500))))

def he_init(fi, fo):
    return np.random.normal(0, np.sqrt(2.0 / max(fi, 1)), (fi, fo)).astype(np.float32)

# ======================================================================
# Feature Flattener: (batch, seq_len, 34) -> (batch, features)
# ======================================================================
def flatten_sequences(X):
    """Convert sequence data to flat features: flatten + aggregate stats."""
    batch, seq_len, feat_dim = X.shape
    flat = X.reshape(batch, seq_len * feat_dim)  # (batch, seq_len×34)

    # Aggregate statistics over time dimension
    mean = X.mean(axis=1)   # (batch, 34)
    std = X.std(axis=1)     # (batch, 34)
    xmin = X.min(axis=1)    # (batch, 34)
    xmax = X.max(axis=1)    # (batch, 34)

    return np.concatenate([flat, mean, std, xmin, xmax], axis=1).astype(np.float32)

def get_input_dim(seq_len, feat_dim):
    """Total feature dimension after flattening."""
    return seq_len * feat_dim + 4 * feat_dim  # flat + mean + std + min + max

# ======================================================================
# MLP Model
# ======================================================================
class VolatilityMLP:
    def __init__(self, input_dim, seed=42):
        np.random.seed(seed)
        self.seed = seed

        self.W1 = he_init(input_dim, HIDDEN1) * 0.5
        self.b1 = np.zeros(HIDDEN1, dtype=np.float32)
        self.W2 = he_init(HIDDEN1, HIDDEN2) * 0.5
        self.b2 = np.zeros(HIDDEN2, dtype=np.float32)
        self.W3 = np.zeros((HIDDEN2, 1), dtype=np.float32)
        self.b3 = np.zeros(1, dtype=np.float32)

    def forward(self, X, training=True):
        Z1 = X @ self.W1 + self.b1
        A1 = relu(Z1)
        if training and DROPOUT > 0:
            mask = (np.random.random(A1.shape) > DROPOUT).astype(np.float32)
            A1 = A1 * mask / (1.0 - DROPOUT)

        Z2 = A1 @ self.W2 + self.b2
        A2 = relu(Z2)
        if training and DROPOUT > 0:
            mask = (np.random.random(A2.shape) > DROPOUT).astype(np.float32)
            A2 = A2 * mask / (1.0 - DROPOUT)

        out = (A2 @ self.W3 + self.b3).flatten()
        return out, {'Z1': Z1, 'A1': A1, 'Z2': Z2, 'A2': A2}

    def predict(self, X):
        out, _ = self.forward(X, training=False)
        return out

    def mse(self, yp, yt):
        return np.mean((yp - yt) ** 2)

    def mae(self, yp, yt):
        return np.mean(np.abs(yp - yt))

# ======================================================================
# Gradient Computation
# ======================================================================
def compute_gradients(model, X, y):
    out, cache = model.forward(X, training=True)
    loss = model.mse(out, y)

    d_out = 2 * (out - y) / len(y)

    dZ3 = d_out.reshape(-1, 1)
    dA2 = dZ3 @ model.W3.T
    dZ2 = dA2 * (cache['Z2'] > 0).astype(np.float32)
    dA1 = dZ2 @ model.W2.T
    dZ1 = dA1 * (cache['Z1'] > 0).astype(np.float32)

    grads = {
        'W3': (cache['A2'].T @ dZ3).astype(np.float32),
        'b3': np.array([dZ3.sum(0)[0]], dtype=np.float32),
        'W2': (cache['A1'].T @ dZ2).astype(np.float32),
        'b2': dZ2.sum(0).astype(np.float32),
        'W1': (X.T @ dZ1).astype(np.float32),
        'b1': dZ1.sum(0).astype(np.float32),
    }
    return grads, loss

# ======================================================================
# Adam
# ======================================================================
class Adam:
    def __init__(self, lr=LR, beta1=0.9, beta2=0.999, eps=1e-8, wd=1e-5):
        self.lr, self.b1, self.b2, self.eps, self.wd = lr, beta1, beta2, eps, wd
        self.t = 0
        self.m, self.v = {}, {}

    def init_params(self, params):
        for k, v in params.items():
            self.m[k] = np.zeros_like(v)
            self.v[k] = np.zeros_like(v)

    def step(self, params, grads, max_norm=5.0):
        self.t += 1
        lr_t = self.lr * np.sqrt(1 - self.b2 ** self.t) / (1 - self.b1 ** self.t)
        gn = np.sqrt(np.sum(np.concatenate([g.ravel() for g in grads.values()]) ** 2))
        if gn > max_norm:
            f = max_norm / max(gn, 1e-10)
            grads = {k: v * f for k, v in grads.items()}
        new = {}
        for k in params:
            g = grads[k] + self.wd * params[k]
            self.m[k] = self.b1 * self.m[k] + (1 - self.b1) * g
            self.v[k] = self.b2 * self.v[k] + (1 - self.b2) * (g ** 2)
            new[k] = params[k] - lr_t * self.m[k] / (np.sqrt(self.v[k]) + self.eps)
        return new

def collect_params(m):
    return {'W1': m.W1, 'b1': m.b1, 'W2': m.W2, 'b2': m.b2, 'W3': m.W3, 'b3': m.b3}

def set_params(m, p):
    for k, v in p.items():
        setattr(m, k, v)

# ======================================================================
# Training
# ======================================================================
def train_model(X_seq, y, seed=42):
    np.random.seed(seed)
    X = flatten_sequences(X_seq)
    input_dim = X.shape[1]

    n = len(X)
    split = int(n * 0.8)
    idx = np.random.permutation(n)
    X_train, y_train = X[idx[:split]], y[idx[:split]]
    X_test, y_test = X[idx[split:]], y[idx[split:]]

    y_mu, y_sig = y_train.mean(), max(y_train.std(), 1e-10)
    y_train_n = (y_train - y_mu) / y_sig
    y_test_n = (y_test - y_mu) / y_sig

    model = VolatilityMLP(input_dim, seed=seed)
    params = collect_params(model)
    opt = Adam(lr=LR, wd=1e-4)
    opt.init_params(params)

    print(f"  Input dim: {input_dim}")
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")
    print(f"  y: mean={y_mu:.6e}, std={y_sig:.6e}")
    print(f"  Model: {input_dim} -> {HIDDEN1} -> {HIDDEN2} -> 1")

    best_loss = float('inf')
    best_params = None
    no_improve = 0

    for epoch in range(EPOCHS):
        perm = np.random.permutation(len(X_train))
        X_s, y_s = X_train[perm], y_train_n[perm]
        epoch_loss = 0.0
        nb = 0

        for i in range(0, len(X_train), BATCH_SIZE):
            Xb, yb = X_s[i:i+BATCH_SIZE], y_s[i:i+BATCH_SIZE]
            g, l = compute_gradients(model, Xb, yb)
            params = opt.step(params, g)
            set_params(model, params)
            epoch_loss += l
            nb += 1

        pred_test = model.predict(X_test)
        val_mse = model.mse(pred_test, y_test_n)
        val_mae = model.mae(pred_test, y_test_n)

        if epoch % 50 == 0 or epoch == EPOCHS - 1:
            print(f"    Epoch {epoch:3d}: loss={epoch_loss/nb:.6f} val_mse={val_mse:.6f} val_mae={val_mae:.6f}")

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
    p_test = pred_test * y_sig + y_mu
    y_test_d = y_test * y_sig + y_mu

    top_k = max(len(p_test) // 10, 1)
    top_idx = np.argsort(-pred_test)[:top_k]
    bot_idx = np.argsort(pred_test)[:top_k]

    corr = float(np.corrcoef(pred_test, y_test_n)[0, 1])

    print(f"\n  Results:")
    print(f"    Train MSE: {model.mse(pred_train, y_train_n):.6f}")
    print(f"    Test MSE:  {model.mse(pred_test, y_test_n):.6f}")
    print(f"    Test MAE:  {model.mae(pred_test, y_test_n):.6f}")
    print(f"    Pearson r: {corr:.4f}")
    print(f"    Top 10% predicted vol: {y_test_d[top_idx].mean():.6e}")
    print(f"    Bottom 10%:             {y_test_d[bot_idx].mean():.6e}")
    ratio = y_test_d[top_idx].mean() / max(y_test_d[bot_idx].mean(), 1e-15)
    print(f"    Spread ratio: {ratio:.3f}x")

    metrics = {
        'seed': seed,
        'n_train': len(X_train),
        'n_test': len(X_test),
        'train_mse': float(model.mse(pred_train, y_train_n)),
        'test_mse': float(model.mse(pred_test, y_test_n)),
        'test_mae': float(model.mae(pred_test, y_test_n)),
        'pearson_r': corr,
        'top10_vol': float(y_test_d[top_idx].mean()),
        'bottom10_vol': float(y_test_d[bot_idx].mean()),
        'spread_ratio': float(ratio),
        'y_mean': float(y_mu),
        'y_std': float(y_sig),
    }
    return model, metrics

def export_mql5(model, path, seq_len, feat_dim, y_mu, y_sig):
    vals = [3, seq_len * feat_dim + 4 * feat_dim, HIDDEN1, HIDDEN2, 1]
    for k in ['W1','b1','W2','b2','W3','b3']:
        v = getattr(model, k).ravel().tolist()
        vals.extend(v)
    vals += [float(y_mu), float(y_sig)]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(struct.pack(f'{len(vals)}f', *vals))
    print(f"  Exported {path} ({len(vals)} floats)")

def cli_main():
    import argparse
    parser = argparse.ArgumentParser(description="Volatility MLP Predictor")
    parser.add_argument("--npz", required=True)
    parser.add_argument("--out", default="output")
    parser.add_argument("--seeds", default="42,137,73")
    parser.add_argument("--epochs", type=int, default=500)
    parser.add_argument("--lr", type=float, default=0.003)
    parser.add_argument("--batch-size", type=int, default=256)
    args = parser.parse_args()

    global EPOCHS, LR, BATCH_SIZE
    EPOCHS, LR, BATCH_SIZE = args.epochs, args.lr, args.batch_size

    print("=" * 60)
    print("PASR Volatility MLP Predictor")
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
        "type": "volatility_mlp_regression",
        "architecture": f"FlattenedSeq({X.shape[1]}x{X.shape[2]})->{HIDDEN1}->{HIDDEN2}->1",
        "models": []
    }

    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]
    for idx, seed in enumerate(seeds):
        print(f"\n--- Model {idx+1}/{len(seeds)} (seed={seed}) ---")
        model, metrics = train_model(X, y, seed)
        fname = out_dir / f"PASR_vol_mlp_m{idx}.bin"
        export_mql5(model, str(fname), X.shape[1], X.shape[2], metrics['y_mean'], metrics['y_std'])
        metrics["file"] = fname.name
        report["models"].append(metrics)

    report_path = out_dir / "volatility_mlp_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport: {report_path}")

    best = max(report["models"], key=lambda m: m.get('pearson_r', -1))
    print(f"\nBest: {best['file']} (seed={best['seed']}, r={best['pearson_r']:.4f}, spread={best['spread_ratio']:.2f}x)")

if __name__ == '__main__':
    cli_main()
