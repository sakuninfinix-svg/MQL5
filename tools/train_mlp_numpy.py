#!/usr/bin/env python3
"""
Pure-NumPy MLP Trainer for PASR
================================
Trains 34->64->32->1 MLP without scikit-learn dependency.
Exports binary weights compatible with AIInference.mqh::LoadWeights()
"""

import numpy as np
import json
import os
import struct
import sys
from pathlib import Path
from datetime import datetime, timezone
from typing import Tuple, List, Dict

INPUT_DIM = 34
HIDDEN1 = 64
HIDDEN2 = 32
OUTPUT_DIM = 1
DEFAULT_SEEDS = [42, 137]

# Xavier/He initialization
def xavier_init(fan_in: int, fan_out: int) -> np.ndarray:
    scale = np.sqrt(2.0 / fan_in)
    return np.random.normal(0.0, scale, size=(fan_in, fan_out)).astype(np.float32)

def he_init(fan_in: int, fan_out: int) -> np.ndarray:
    scale = np.sqrt(2.0 / fan_in)
    return np.random.normal(0.0, scale, size=(fan_in, fan_out)).astype(np.float32)

def relu(x: np.ndarray) -> np.ndarray:
    return np.maximum(0, x)

def relu_derivative(x: np.ndarray) -> np.ndarray:
    return (x > 0).astype(np.float32)

def sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(x, -500, 500)))

def mse_loss(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    return np.mean((y_true - y_pred) ** 2)

def mae_loss(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    return np.mean(np.abs(y_true - y_pred))

def r2_score(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    ss_res = np.sum((y_true - y_pred) ** 2)
    ss_tot = np.sum((y_true - np.mean(y_true)) ** 2)
    return 1 - ss_res / (ss_tot + 1e-10)

class MLP:
    """3-layer MLP: INPUT_DIM -> HIDDEN1 -> HIDDEN2 -> 1"""
    
    def __init__(self, seed: int = 42):
        np.random.seed(seed)
        self.seed = seed
        
        # Weights and biases
        self.W1 = he_init(INPUT_DIM, HIDDEN1)
        self.b1 = np.zeros(HIDDEN1, dtype=np.float32)
        self.W2 = he_init(HIDDEN1, HIDDEN2)
        self.b2 = np.zeros(HIDDEN2, dtype=np.float32)
        self.W3 = he_init(HIDDEN2, OUTPUT_DIM)
        self.b3 = np.zeros(OUTPUT_DIM, dtype=np.float32)
        
    def forward(self, X: np.ndarray) -> Tuple[np.ndarray, Dict]:
        """Forward pass, returns output and cache for backprop"""
        # Layer 1
        Z1 = X @ self.W1 + self.b1
        A1 = relu(Z1)
        
        # Layer 2
        Z2 = A1 @ self.W2 + self.b2
        A2 = relu(Z2)
        
        # Layer 3 (output)
        Z3 = A2 @ self.W3 + self.b3
        A3 = np.tanh(Z3)  # tanh for [-1, 1] output
        
        cache = {
            'X': X, 'Z1': Z1, 'A1': A1, 'Z2': Z2, 'A2': A2, 'Z3': Z3, 'A3': A3
        }
        return A3.flatten(), cache
    
    def backward(self, cache: Dict, y_true: np.ndarray, lr: float) -> None:
        """Backward pass with gradient descent"""
        m = y_true.shape[0]
        y_pred = cache['A3'].flatten()
        
        # Output layer gradients (tanh derivative = 1 - tanh^2)
        dZ3 = 2.0 * (y_pred - y_true) * (1.0 - y_pred ** 2) / m
        dW3 = cache['A2'].T @ dZ3.reshape(-1, 1)
        db3 = np.sum(dZ3, axis=0)
        
        # Hidden layer 2
        dA2 = dZ3.reshape(-1, 1) @ self.W3.T
        dZ2 = dA2 * relu_derivative(cache['Z2'])
        dW2 = cache['A1'].T @ dZ2
        db2 = np.sum(dZ2, axis=0)
        
        # Hidden layer 1
        dA1 = dZ2 @ self.W2.T
        dZ1 = dA1 * relu_derivative(cache['Z1'])
        dW1 = cache['X'].T @ dZ1
        db1 = np.sum(dZ1, axis=0)
        
        # Update weights
        self.W3 -= lr * dW3.astype(np.float32)
        self.b3 -= lr * db3.astype(np.float32)
        self.W2 -= lr * dW2.astype(np.float32)
        self.b2 -= lr * db2.astype(np.float32)
        self.W1 -= lr * dW1.astype(np.float32)
        self.b1 -= lr * db1.astype(np.float32)
    
    def train_batch(self, X: np.ndarray, y: np.ndarray, lr: float) -> Dict:
        """Train on a batch"""
        y_pred, cache = self.forward(X)
        self.backward(cache, y, lr)
        return {
            'loss': mse_loss(y, y_pred),
            'mae': mae_loss(y, y_pred),
            'r2': r2_score(y, y_pred)
        }
    
    def predict(self, X: np.ndarray) -> np.ndarray:
        y_pred, _ = self.forward(X)
        return np.clip(y_pred, -1.0, 1.0)
    
    def export_mql5(self, path: str) -> None:
        """Export weights in MQL5 AIInference.mqh LoadWeights() format"""
        # Binary layout: [in_dim, h1, h2, out_dim, W1, b1, W2, b2, W3, b3]
        values = [
            float(INPUT_DIM), float(HIDDEN1), float(HIDDEN2), float(OUTPUT_DIM)
        ]
        values.extend(self.W1.ravel(order='C'))
        values.extend(self.b1)
        values.extend(self.W2.ravel(order='C'))
        values.extend(self.b2)
        values.extend(self.W3[:, 0])  # W3 is (HIDDEN2, 1)
        values.append(float(self.b3[0]))
        
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'wb') as f:
            f.write(struct.pack(f'{len(values)}f', *values))
        print(f"  Exported {path} ({len(values)} float32 values)")


def load_dataset(path: str) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Load and validate dataset"""
    import pandas as pd
    df = pd.read_csv(path, comment='#')
    
    cols = [f'f{i}' for i in range(INPUT_DIM)]
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise ValueError(f"Missing feature columns: {missing}")
    if 'label' not in df.columns:
        raise ValueError("CSV must contain 'label' column")
    
    X = df[cols].apply(pd.to_numeric, errors='coerce').fillna(0.0).to_numpy(np.float32)
    y = pd.to_numeric(df['label'], errors='coerce').fillna(0.0).to_numpy(np.float32)
    y = np.clip(y, -1.0, 1.0)
    
    if 'weight' in df.columns:
        w = pd.to_numeric(df['weight'], errors='coerce').fillna(1.0).to_numpy(np.float32)
        w = np.clip(w, 0.1, 5.0)
    else:
        w = np.ones(len(df), dtype=np.float32)
    
    if len(X) < 50:
        raise ValueError(f"Only {len(X)} samples; need 50+")
    
    return X, y, w


def train_model(X: np.ndarray, y: np.ndarray, w: np.ndarray, 
                seed: int, epochs: int = 500, lr: float = 0.001,
                batch_size: int = 64) -> Tuple[MLP, Dict]:
    """Train a single MLP model"""
    np.random.seed(seed)
    
    # Split
    n = len(X)
    split = int(n * 0.8)
    indices = np.arange(n)
    np.random.shuffle(indices)
    
    train_idx = indices[:split]
    test_idx = indices[split:]
    
    X_train, y_train, w_train = X[train_idx], y[train_idx], w[train_idx]
    X_test, y_test, w_test = X[test_idx], y[test_idx], w[test_idx]
    
    model = MLP(seed)
    best_loss = float('inf')
    patience = 25
    no_improve = 0
    
    print(f"  Training model (seed={seed}): {len(X_train)} train, {len(X_test)} test")
    
    for epoch in range(epochs):
        # Shuffle training data
        perm = np.random.permutation(len(X_train))
        X_shuf = X_train[perm]
        y_shuf = y_train[perm]
        w_shuf = w_train[perm]
        
        epoch_loss = 0.0
        n_batches = 0
        
        for i in range(0, len(X_train), batch_size):
            X_batch = X_shuf[i:i+batch_size]
            y_batch = y_shuf[i:i+batch_size]
            w_batch = w_shuf[i:i+batch_size]
            
            # Weighted loss via sample weighting in backward pass
            metrics = model.train_batch(X_batch, y_batch, lr)
            epoch_loss += metrics['loss']
            n_batches += 1
        
        # Validation
        y_pred = model.predict(X_test)
        val_loss = mse_loss(y_test, y_pred)
        val_mae = mae_loss(y_test, y_pred)
        val_r2 = r2_score(y_test, y_pred) if len(set(np.round(y_test, 6))) > 1 else 0.0
        
        if epoch % 50 == 0:
            print(f"    Epoch {epoch}: train_loss={epoch_loss/n_batches:.6f}, val_loss={val_loss:.6f}, val_mae={val_mae:.6f}, r2={val_r2:.4f}")
        
        # Early stopping
        if val_loss < best_loss:
            best_loss = val_loss
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= patience:
                print(f"    Early stopping at epoch {epoch}")
                break
    
    # Final validation metrics
    y_pred_final = model.predict(X_test)
    final_metrics = {
        'seed': seed,
        'n_train': int(len(X_train)),
        'n_test': int(len(X_test)),
        'mae': float(mae_loss(y_test, y_pred_final)),
        'mse': float(mse_loss(y_test, y_pred_final)),
        'r2': float(r2_score(y_test, y_pred_final)) if len(set(np.round(y_test, 6))) > 1 else None,
        'loss': float(best_loss),
    }
    
    return model, final_metrics


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Train PASR MLP weights (NumPy only)")
    parser.add_argument("--csv", required=True, help="Training CSV with f0..f33,label[,weight]")
    parser.add_argument("--out", default="output", help="Output directory")
    parser.add_argument("--seeds", default=",".join(map(str, DEFAULT_SEEDS)))
    parser.add_argument("--epochs", type=int, default=500)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--batch-size", type=int, default=64)
    args = parser.parse_args()
    
    print(f"Loading dataset from {args.csv}...")
    X, y, w = load_dataset(args.csv)
    print(f"Dataset shape: X={X.shape}, y={y.shape}, w={w.shape}")
    print(f"Label range: [{y.min():.3f}, {y.max():.3f}], mean={y.mean():.3f}")
    print(f"Label distribution: {np.bincount((y > 0).astype(int))}")
    
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_csv": os.path.abspath(args.csv),
        "shape": [INPUT_DIM, HIDDEN1, HIDDEN2, OUTPUT_DIM],
        "models": [],
    }
    
    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]
    
    for idx, seed in enumerate(seeds):
        print(f"\nTraining model {idx+1}/{len(seeds)} (seed={seed})...")
        model, metrics = train_model(X, y, w, seed, args.epochs, args.lr, args.batch_size)
        
        file_name = out_dir / f"PASR_mlp_m{idx}.bin"
        model.export_mql5(str(file_name))
        metrics["file"] = file_name.name
        report["models"].append(metrics)
        
        print(f"  Final metrics: MAE={metrics['mae']:.6f}, MSE={metrics['mse']:.6f}, R2={metrics['r2']}")
    
    report_path = out_dir / "mlp_training_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved to {report_path}")
    print(f"\nCopy {out_dir}/PASR_mlp_m*.bin to MT5/MQL5/Files/")
    return 0


if __name__ == "__main__":
    sys.exit(main())