#!/usr/bin/env python3
"""
PASR MLP Classifier Trainer v2 — Optimized Binary Classification
=================================================================
Key improvements over v1:
  1. Focal loss (gamma=2) — handles class imbalance, focuses on hard examples
  2. Smaller default arch (34→32→16→1) — less overfitting on small datasets
  3. Gradient clipping (max_norm=1.0) — stable training
  4. Cosine annealing LR — better convergence than ReduceOnPlateau
  5. Label smoothing (0.05) — prevents overconfident predictions
  6. Class-aware focal alpha — auto-balances win/loss ratio
  7. Dropout=0.15 default

Exports binary weights 100% compatible with AIInference.mqh::LoadWeights().

Labels (binary):
  0 = loss (profit_r < -0.5 OR hit_sl)
  1 = win  (profit_r > +0.5 OR hit_tp)

Usage:
  python3 training/train_mlp_classifier.py \\
    --csv output/MT5_Training_Data.csv \\
    --out output --epochs 300 --lr 0.003 --batch-size 32 --dropout 0.15
"""

import numpy as np
import json
import os
import struct
import sys
from pathlib import Path
from datetime import datetime, timezone
from typing import Tuple, Dict, List

INPUT_DIM = 34
OUTPUT_DIM = 1
DEFAULT_SEEDS = [42, 137, 73]
EPSILON = 1e-12


# ============================================================================
# Activation Functions
# ============================================================================
def sigmoid(x: np.ndarray) -> np.ndarray:
    return np.where(x >= 0,
                    1.0 / (1.0 + np.exp(-np.clip(x, -500, 500))),
                    np.exp(np.clip(x, -500, 500)) / (1.0 + np.exp(np.clip(x, -500, 500))))


def relu(x: np.ndarray) -> np.ndarray:
    return np.maximum(0, x)


def relu_derivative(x: np.ndarray) -> np.ndarray:
    return (x > 0).astype(np.float32)


def he_init(fan_in: int, fan_out: int) -> np.ndarray:
    scale = np.sqrt(2.0 / fan_in)
    return np.random.normal(0.0, scale, size=(fan_in, fan_out)).astype(np.float32)


# ============================================================================
# Focal Loss — handles class imbalance + focuses on hard examples
# ============================================================================
def focal_loss(y_true: np.ndarray, y_pred: np.ndarray,
               gamma: float = 2.0, alpha: np.ndarray = None) -> float:
    """
    Focal loss: -alpha * (1-p)^gamma * log(p)
    gamma=0 reduces to standard BCE.
    gamma=2 focuses training on hard-to-classify examples.
    """
    p = np.clip(y_pred, EPSILON, 1.0 - EPSILON)
    ce = -(y_true * np.log(p) + (1.0 - y_true) * np.log(1.0 - p))
    p_t = y_true * p + (1.0 - y_true) * (1.0 - p)
    modulating = np.power(1.0 - p_t, gamma)
    if alpha is not None:
        alpha_t = y_true * alpha[1] + (1.0 - y_true) * alpha[0]
        return float(np.mean(alpha_t * modulating * ce))
    return float(np.mean(modulating * ce))


def focal_loss_gradient(y_true: np.ndarray, y_pred: np.ndarray,
                        gamma: float = 2.0, alpha: np.ndarray = None) -> np.ndarray:
    """Gradient of focal loss w.r.t. sigmoid input (logits)."""
    p = np.clip(y_pred, EPSILON, 1.0 - EPSILON)
    p_t = y_true * p + (1.0 - y_true) * (1.0 - p)
    ce = -(y_true * np.log(p) + (1.0 - y_true) * np.log(1.0 - p))
    modulating = np.power(1.0 - p_t, gamma)

    # d(focal)/d(logit) = gamma * (1-p_t)^(gamma-1) * p_t * CE + modulating * (p - y)
    grad = gamma * np.power(1.0 - p_t, gamma - 1.0) * p_t * ce + modulating * (p - y_true)
    # Simpler stable form: modulating * (gamma * p_t * ce / (1-p_t+eps) + 1) * (p - y)
    # Use the direct form but clip for stability
    grad = np.clip(grad, -10.0, 10.0)

    if alpha is not None:
        alpha_t = y_true * alpha[1] + (1.0 - y_true) * alpha[0]
        grad *= alpha_t

    return grad


# ============================================================================
# Pure NumPy Metrics
# ============================================================================
def binary_accuracy(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    y_class = (y_pred > 0.5).astype(float)
    return float(np.mean(y_true == y_class))


def binary_precision(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    y_class = (y_pred > 0.5).astype(float)
    tp = np.sum((y_true == 1) & (y_class == 1))
    fp = np.sum((y_true == 0) & (y_class == 1))
    return float(tp / max(tp + fp, 1e-10))


def binary_recall(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    y_class = (y_pred > 0.5).astype(float)
    tp = np.sum((y_true == 1) & (y_class == 1))
    fn = np.sum((y_true == 1) & (y_class == 0))
    return float(tp / max(tp + fn, 1e-10))


def binary_f1(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    p = binary_precision(y_true, y_pred)
    r = binary_recall(y_true, y_pred)
    return float(2 * p * r / max(p + r, 1e-10))


def binary_confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray) -> Dict:
    y_class = (y_pred > 0.5).astype(float)
    return {
        'tn': int(np.sum((y_true == 0) & (y_class == 0))),
        'fp': int(np.sum((y_true == 0) & (y_class == 1))),
        'fn': int(np.sum((y_true == 1) & (y_class == 0))),
        'tp': int(np.sum((y_true == 1) & (y_class == 1)))
    }


def binary_roc_auc(y_true: np.ndarray, y_score: np.ndarray) -> float:
    n_pos = int(np.sum(y_true == 1))
    n_neg = int(np.sum(y_true == 0))
    if n_pos == 0 or n_neg == 0:
        return float('nan')
    order = np.argsort(-y_score)
    y_true_sorted = y_true[order]
    tpr = np.cumsum(y_true_sorted == 1) / n_pos
    fpr = np.cumsum(y_true_sorted == 0) / n_neg
    return float(np.trapz(tpr, fpr))


# ============================================================================
# Adam Optimizer with Gradient Clipping
# ============================================================================
class AdamOptimizer:
    def __init__(self, lr: float = 0.003, beta1: float = 0.9, beta2: float = 0.999,
                 epsilon: float = 1e-8, weight_decay: float = 1e-4):
        self.lr = lr
        self.beta1 = beta1
        self.beta2 = beta2
        self.epsilon = epsilon
        self.weight_decay = weight_decay
        self.t = 0
        self.m = {}
        self.v = {}

    def init_params(self, params: Dict[str, np.ndarray]):
        for name, param in params.items():
            self.m[name] = np.zeros_like(param)
            self.v[name] = np.zeros_like(param)

    def step(self, params: Dict[str, np.ndarray],
             grads: Dict[str, np.ndarray], max_grad_norm: float = 1.0) -> Dict[str, np.ndarray]:
        self.t += 1
        lr_t = self.lr * np.sqrt(1.0 - self.beta2 ** self.t) / (1.0 - self.beta1 ** self.t)

        # Global gradient clipping
        all_grads = np.concatenate([g.ravel() for g in grads.values()])
        global_norm = np.sqrt(np.sum(all_grads ** 2))
        if global_norm > max_grad_norm:
            clip_factor = max_grad_norm / (global_norm + 1e-10)
            for name in grads:
                grads[name] *= clip_factor

        new_params = {}
        for name in params:
            if name not in self.m:
                self.m[name] = np.zeros_like(params[name])
                self.v[name] = np.zeros_like(params[name])

            # Weight decay (L2 regularization)
            g = grads[name] + self.weight_decay * params[name]

            self.m[name] = self.beta1 * self.m[name] + (1.0 - self.beta1) * g
            self.v[name] = self.beta2 * self.v[name] + (1.0 - self.beta2) * (g ** 2)

            new_params[name] = params[name] - lr_t * self.m[name] / (np.sqrt(self.v[name]) + self.epsilon)

        return new_params


# ============================================================================
# Cosine Annealing LR Scheduler
# ============================================================================
def cosine_annealing_lr(base_lr: float, epoch: int, total_epochs: int,
                         min_lr: float = 1e-5) -> float:
    return min_lr + 0.5 * (base_lr - min_lr) * (1 + np.cos(np.pi * epoch / total_epochs))


# ============================================================================
# MLP Classifier with Focal Loss
# ============================================================================
class MLPClassifier:
    def __init__(self, seed: int = 42, dropout_rate: float = 0.15,
                 hidden_dims: List[int] = None, focal_gamma: float = 2.0,
                 label_smoothing: float = 0.05):
        np.random.seed(seed)
        self.seed = seed
        self.dropout_rate = dropout_rate
        self.hidden_dims = hidden_dims if hidden_dims else [32, 16]
        self.focal_gamma = focal_gamma
        self.label_smoothing = label_smoothing

        dims = [INPUT_DIM] + self.hidden_dims + [OUTPUT_DIM]
        self.layer_dims = dims

        self.weights = []
        for i in range(len(dims) - 1):
            W = he_init(dims[i], dims[i + 1])
            b = np.zeros(dims[i + 1], dtype=np.float32)
            self.weights.append({'W': W, 'b': b})

        self.optimizer = AdamOptimizer(lr=0.003, weight_decay=1e-4)
        adam_params = {}
        for i in range(len(self.weights)):
            adam_params[f'W{i}'] = self.weights[i]['W']
            adam_params[f'b{i}'] = self.weights[i]['b']
        self.optimizer.init_params(adam_params)

    def forward(self, X: np.ndarray, training: bool = True) -> Tuple[np.ndarray, Dict]:
        cache = {'X': X, 'masks': [], 'Zs': [], 'As': []}
        A = X
        for i in range(len(self.weights)):
            W = self.weights[i]['W']
            b = self.weights[i]['b']
            Z = A @ W + b

            if i == len(self.weights) - 1:
                A_out = sigmoid(Z)
                mask = np.ones_like(A_out)
            else:
                A_out = relu(Z)
                if training and self.dropout_rate > 0:
                    mask = (np.random.random(A_out.shape) > self.dropout_rate).astype(np.float32)
                    A_out = A_out * mask / (1.0 - self.dropout_rate)
                else:
                    mask = np.ones_like(A_out)

            cache['Zs'].append(Z)
            cache['As'].append(A_out)
            cache['masks'].append(mask)
            A = A_out

        return A.flatten(), cache

    def backward(self, cache: Dict, y_true: np.ndarray, w: np.ndarray,
                 focal_alpha: np.ndarray = None) -> Dict[str, np.ndarray]:
        w_sum = max(np.sum(w), 1e-10)
        n_layers = len(self.weights)

        # Label smoothing
        y_smooth = y_true * (1.0 - self.label_smoothing) + 0.5 * self.label_smoothing

        # Focal loss gradient at output
        p = cache['As'][-1].flatten()
        dZ = focal_loss_gradient(y_smooth, p, self.focal_gamma, focal_alpha) * w / w_sum

        grads = {}
        for i in range(n_layers - 1, -1, -1):
            A_prev = cache['As'][i - 1] if i > 0 else cache['X']
            mask = cache['masks'][i]
            Z = cache['Zs'][i]

            dW = A_prev.T @ dZ.reshape(-1, 1) if dZ.ndim == 1 else A_prev.T @ dZ
            db = np.sum(dZ, axis=0) if dZ.ndim > 1 else np.array([np.sum(dZ)])

            grads[f'W{i}'] = dW.astype(np.float32) if dW.ndim > 0 else np.array([dW]).astype(np.float32)
            grads[f'b{i}'] = db.astype(np.float32)

            if i > 0:
                W = self.weights[i]['W']
                if dZ.ndim == 1:
                    dA_prev = dZ.reshape(-1, 1) * W.T
                else:
                    dA_prev = dZ @ W.T
                prev_mask = cache['masks'][i - 1]
                dA_prev = dA_prev * prev_mask
                relu_grad = (A_prev > 0).astype(np.float32)
                dZ = dA_prev * relu_grad

        return grads

    def train_batch(self, X: np.ndarray, y: np.ndarray, w: np.ndarray,
                    focal_alpha: np.ndarray = None) -> Dict:
        y_pred, cache = self.forward(X, training=True)
        grads = self.backward(cache, y, w, focal_alpha)

        params = {}
        for i in range(len(self.weights)):
            params[f'W{i}'] = self.weights[i]['W']
            params[f'b{i}'] = self.weights[i]['b']

        new_params = self.optimizer.step(params, grads, max_grad_norm=1.0)

        for i in range(len(self.weights)):
            self.weights[i]['W'] = new_params[f'W{i}']
            self.weights[i]['b'] = new_params[f'b{i}']

        loss = focal_loss(y, y_pred, self.focal_gamma, focal_alpha)
        return {'loss': loss, 'accuracy': binary_accuracy(y, y_pred)}

    def predict(self, X: np.ndarray) -> np.ndarray:
        y_pred, _ = self.forward(X, training=False)
        return np.clip(y_pred, 0.0, 1.0)

    def predict_classes(self, X: np.ndarray, threshold: float = 0.5) -> np.ndarray:
        return (self.predict(X) > threshold).astype(float)

    def export_mql5(self, path: str) -> None:
        dims = self.layer_dims
        values = [float(d) for d in dims]
        for i in range(len(self.weights)):
            W = self.weights[i]['W']
            b = self.weights[i]['b']
            values.extend(W.ravel(order='C').tolist())
            values.extend(b.tolist())

        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'wb') as f:
            f.write(struct.pack(f'{len(values)}f', *values))
        print(f"  Exported {path} ({len(values)} float32 values, arch={'->'.join(str(int(d)) for d in dims)})")


# ============================================================================
# Data Loading
# ============================================================================
def load_dataset(path: str) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    import pandas as pd
    df = pd.read_csv(path, comment='#')

    cols = [f'f{i}' for i in range(INPUT_DIM)]
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise ValueError(f"Missing feature columns: {missing}")
    if 'label' not in df.columns:
        raise ValueError("CSV must contain 'label' column")

    X = df[cols].apply(pd.to_numeric, errors='coerce').fillna(0.0).to_numpy(np.float32)

    y_raw = pd.to_numeric(df['label'], errors='coerce').fillna(0.0).to_numpy(np.float32)
    mask = y_raw != 0.0
    X = X[mask]
    y = np.where(y_raw[mask] > 0, 1.0, 0.0).astype(np.float32)

    if 'weight' in df.columns:
        w_raw = pd.to_numeric(df['weight'], errors='coerce').fillna(1.0).to_numpy(np.float32)
        w = w_raw[mask]
        w = np.clip(w, 0.1, 5.0)
    else:
        w = np.ones(len(y), dtype=np.float32)

    if len(X) < 50:
        raise ValueError(f"Only {len(X)} samples after removing neutral; need 50+")

    return X, y, w


def compute_focal_alpha(y: np.ndarray) -> np.ndarray:
    """Compute class-balanced focal alpha: inversely proportional to class frequency."""
    n_pos = np.sum(y == 1)
    n_neg = np.sum(y == 0)
    total = len(y)
    alpha_neg = total / (2.0 * n_neg + 1e-10)
    alpha_pos = total / (2.0 * n_pos + 1e-10)
    return np.array([alpha_neg, alpha_pos], dtype=np.float32)


def standardize_features(X_train: np.ndarray, X_test: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Z-score standardization: zero mean, unit variance. Clips near-constant features."""
    mean = X_train.mean(axis=0)
    std = X_train.std(axis=0)
    # Replace near-zero std with 1.0 to avoid division issues
    std[std < 1e-6] = 1.0
    X_train_s = ((X_train - mean) / std).astype(np.float32)
    X_test_s = ((X_test - mean) / std).astype(np.float32)
    # Clip outliers
    X_train_s = np.clip(X_train_s, -4.0, 4.0)
    X_test_s = np.clip(X_test_s, -4.0, 4.0)
    return X_train_s, X_test_s, mean, std


# ============================================================================
# Training
# ============================================================================
def train_model(X: np.ndarray, y: np.ndarray, w: np.ndarray,
                seed: int, epochs: int = 300, lr: float = 0.003,
                batch_size: int = 32, dropout_rate: float = 0.15,
                hidden_dims: List[int] = None, focal_gamma: float = 2.0,
                label_smoothing: float = 0.05) -> Tuple[MLPClassifier, Dict]:
    np.random.seed(seed)

    n = len(X)
    split = int(n * 0.8)
    indices = np.arange(n)
    np.random.shuffle(indices)

    train_idx = indices[:split]
    test_idx = indices[split:]

    X_train, y_train, w_train = X[train_idx], y[train_idx], w[train_idx]
    X_test, y_test, w_test = X[test_idx], y[test_idx], w[test_idx]

    # Standardize features
    X_train, X_test, feat_mean, feat_std = standardize_features(X_train, X_test)

    # Class-balanced focal alpha
    focal_alpha = compute_focal_alpha(y_train)

    arch_str = 'x'.join(str(h) for h in (hidden_dims or [32, 16]))
    model = MLPClassifier(seed, dropout_rate, hidden_dims, focal_gamma, label_smoothing)
    model.optimizer.lr = lr
    best_loss = float('inf')
    best_weights = None
    patience = 80
    no_improve = 0

    win_rate = y_train.mean() * 100
    print(f"  Training classifier (seed={seed}) arch=34->{arch_str}->1 focal_gamma={focal_gamma}")
    print(f"    {len(X_train)} train, {len(X_test)} test")
    print(f"    Train: win={y_train.sum():.0f}, loss={(1-y_train).sum():.0f} ({win_rate:.1f}% win)")
    print(f"    Focal alpha: [{focal_alpha[0]:.3f}, {focal_alpha[1]:.3f}]")

    for epoch in range(epochs):
        # Cosine annealing LR
        current_lr = cosine_annealing_lr(lr, epoch, epochs, min_lr=1e-5)
        model.optimizer.lr = current_lr

        perm = np.random.permutation(len(X_train))
        X_shuf = X_train[perm]
        y_shuf = y_train[perm]
        w_shuf = w_train[perm]

        epoch_loss = 0.0
        n_batches = 0

        for i in range(0, len(X_train), batch_size):
            X_batch = X_shuf[i:i + batch_size]
            y_batch = y_shuf[i:i + batch_size]
            w_batch = w_shuf[i:i + batch_size]

            metrics = model.train_batch(X_batch, y_batch, w_batch, focal_alpha)
            epoch_loss += metrics['loss']
            n_batches += 1

        # Validation
        y_pred, _ = model.forward(X_test, training=False)
        val_loss = focal_loss(y_test, y_pred, focal_gamma, focal_alpha)
        val_acc = binary_accuracy(y_test, y_pred)

        if epoch % 20 == 0 or epoch == epochs - 1:
            val_f1 = binary_f1(y_test, y_pred)
            val_auc = binary_roc_auc(y_test, y_pred)
            print(f"    Epoch {epoch:3d}: loss={epoch_loss / n_batches:.4f}, "
                  f"val_loss={val_loss:.4f}, acc={val_acc:.4f}, "
                  f"f1={val_f1:.4f}, auc={val_auc:.4f}, lr={current_lr:.6f}")

        if not np.isnan(val_loss) and val_loss < best_loss:
            best_loss = val_loss
            best_weights = [{'W': w['W'].copy(), 'b': w['b'].copy()} for w in model.weights]
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= patience:
                print(f"    Early stopping at epoch {epoch}")
                break

    if best_weights is not None:
        model.weights = best_weights

    # Final metrics at default threshold
    y_pred_final, _ = model.forward(X_test, training=False)
    y_pred_final = np.clip(y_pred_final, 0.0, 1.0)

    # Find optimal threshold for F1
    best_f1_thresh = 0.5
    best_f1_val = 0.0
    for thresh in np.arange(0.20, 0.75, 0.01):
        y_c = (y_pred_final > thresh).astype(float)
        tp = np.sum((y_test == 1) & (y_c == 1))
        fp = np.sum((y_test == 0) & (y_c == 1))
        fn = np.sum((y_test == 1) & (y_c == 0))
        prec = tp / max(tp + fp, 1)
        rec = tp / max(tp + fn, 1)
        f = 2 * prec * rec / max(prec + rec, 1e-10)
        if f > best_f1_val:
            best_f1_val = f
            best_f1_thresh = float(thresh)

    y_class_final = (y_pred_final > best_f1_thresh).astype(float)

    n_classes = len(set(y_test.astype(int)))
    if n_classes > 1:
        f1 = binary_f1(y_test, y_pred_final)
        precision = binary_precision(y_test, y_pred_final)
        recall = binary_recall(y_test, y_pred_final)
        roc_auc = binary_roc_auc(y_test, y_pred_final)
        cm = binary_confusion_matrix(y_test, y_pred_final)
    else:
        f1 = precision = recall = roc_auc = float('nan')
        cm = {'tn': 0, 'fp': 0, 'fn': 0, 'tp': 0}

    print(f"    Optimal threshold: {best_f1_thresh:.2f} (F1={best_f1_val:.4f})")
    print(f"    @0.50 → F1={f1:.4f}, @opt → F1={best_f1_val:.4f}")

    metrics = {
        'seed': seed,
        'n_train': int(len(X_train)),
        'n_test': int(len(X_test)),
        'loss': float(best_loss),
        'accuracy': float(val_acc),
        'precision': precision,
        'recall': recall,
        'f1_score': f1,
        'roc_auc': roc_auc,
        'confusion_matrix': cm,
        'test_win_rate': float(y_test.mean()),
        'test_pred_win_rate': float(y_class_final.mean()),
        'architecture': f"34->{arch_str}->1",
        'optimizer': 'adam+weight_decay',
        'dropout_rate': dropout_rate,
        'lr_scheduler': 'cosine_annealing',
        'focal_gamma': focal_gamma,
        'label_smoothing': label_smoothing,
        'optimal_threshold': best_f1_thresh,
        'optimal_f1': best_f1_val,
    }

    return model, metrics, feat_mean, feat_std


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Train PASR MLP Classifier v2 (focal loss, optimized)"
    )
    parser.add_argument("--csv", required=True,
                        help="Training CSV with f0..f33,label[,weight]")
    parser.add_argument("--out", default="output", help="Output directory")
    parser.add_argument("--seeds", default=",".join(map(str, DEFAULT_SEEDS)))
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--lr", type=float, default=0.003)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--dropout", type=float, default=0.15,
                        help="Dropout rate (0.0 = no dropout)")
    parser.add_argument("--hidden", default="32,16",
                        help="Hidden layer dims (comma-separated, e.g. '32,16' or '64,32')")
    parser.add_argument("--focal-gamma", type=float, default=2.0,
                        help="Focal loss gamma (0=BCE, 2=default)")
    parser.add_argument("--label-smoothing", type=float, default=0.05)
    args = parser.parse_args()

    hidden_dims = [int(h.strip()) for h in args.hidden.split(",") if h.strip()]
    arch_str = '->'.join(['34'] + [str(h) for h in hidden_dims] + ['1'])

    print("=" * 60)
    print(f"PASR MLP Classifier v2 — Arch: {arch_str}")
    print(f"Focal loss (gamma={args.focal_gamma}), dropout={args.dropout}")
    print("=" * 60)

    print(f"\nLoading dataset from {args.csv}...")
    X, y, w = load_dataset(args.csv)
    print(f"Dataset: X={X.shape}, y={y.shape}")
    print(f"Binary: win={y.sum():.0f}, loss={(1-y).sum():.0f} ({y.mean()*100:.1f}% win)")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_csv": os.path.abspath(args.csv),
        "type": "classifier_binary_v2",
        "shape": [INPUT_DIM] + hidden_dims + [OUTPUT_DIM],
        "output_activation": "sigmoid",
        "optimizer": "adam+weight_decay",
        "lr_scheduler": "cosine_annealing",
        "dropout_rate": args.dropout,
        "loss_function": f"focal_loss_gamma_{args.focal_gamma}",
        "label_smoothing": args.label_smoothing,
        "models": [],
    }

    seeds = [int(s.strip()) for s in args.seeds.split(",") if s.strip()]

    for idx, seed in enumerate(seeds):
        print(f"\n{'=' * 50}")
        print(f"Training model {idx + 1}/{len(seeds)} (seed={seed})...")
        print(f"{'=' * 50}")
        model, metrics, feat_mean, feat_std = train_model(
            X, y, w, seed, args.epochs, args.lr, args.batch_size,
            args.dropout, hidden_dims, args.focal_gamma, args.label_smoothing
        )

        file_name = out_dir / f"PASR_mlp_m{idx}.bin"
        model.export_mql5(str(file_name))
        metrics["file"] = file_name.name
        report["models"].append(metrics)

        # Export feature standardization params (for potential future use)
        std_path = out_dir / f"feature_std_m{idx}.bin"
        std_values = list(feat_mean.astype(np.float32)) + list(feat_std.astype(np.float32))
        with open(std_path, 'wb') as f:
            f.write(struct.pack(f'{len(std_values)}f', *std_values))

        print(f"\n  Final metrics:")
        print(f"    Accuracy:  {metrics['accuracy']:.4f}")
        print(f"    Precision: {metrics['precision']:.4f}")
        print(f"    Recall:    {metrics['recall']:.4f}")
        print(f"    F1 Score:  {metrics['f1_score']:.4f}")
        print(f"    ROC AUC:   {metrics['roc_auc']}")
        cm = metrics['confusion_matrix']
        print(f"    Confusion: TN={cm['tn']} FP={cm['fp']} FN={cm['fn']} TP={cm['tp']}")

    report_path = out_dir / "mlp_classifier_report.json"
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport: {report_path}")
    print(f"\nDeployment:")
    print(f"  Copy {out_dir}/PASR_mlp_m*.bin -> MT5/MQL5/Files/")

    # Summary: pick best model
    best = max(report["models"], key=lambda m: m.get('roc_auc', 0) if not np.isnan(m.get('roc_auc', 0)) else 0)
    print(f"\nBest model: {best['file']} (seed={best['seed']})")
    print(f"  ROC AUC: {best['roc_auc']:.4f}, F1: {best['f1_score']:.4f}, Acc: {best['accuracy']:.4f}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
