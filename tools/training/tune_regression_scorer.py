#!/usr/bin/env python3
"""
tune_regression_scorer.py — Universal hyperparameter tuner for PASR regression-style scorers
==========================================================================================

This script trains/tunes the small logistic-regression style scorers used by PASR:

  pattern        -> PASR_pattern_weights.bin       (special multi-pattern format)
  sr_zone        -> PASR_sr_zone_weights.bin
  regime         -> PASR_regime_weights.bin        (one-vs-rest multi-class format)
  exit_pressure  -> PASR_exit_pressure_weights.bin
  entry_quality  -> PASR_entry_quality_weights.bin
  recovery       -> PASR_recovery_weights.bin
  session_quality-> PASR_session_quality_weights.bin

For binary scorers, expected CSV columns:
  label,f0,f1,...[,weight]

For regime:
  label,f0..f5[,weight]
  label in: trend, range, volatile, squeeze, transition
  aliases: trend_up/trend_down -> trend, crash/vol -> volatile

For pattern:
  pattern,label,f0..f4[,weight]
  pattern in: pinbar, engulf, tweezer, fakey, inside

Output:
  output/<model_file>.bin
  output/<scorer>_tuning_report.json

Recommended starting examples:

  python tools/tune_regression_scorer.py --scorer sr_zone --csv sr_zone_training.csv --out output
  python tools/tune_regression_scorer.py --scorer entry_quality --csv entry_quality_training.csv --out output --metric brier
  python tools/tune_regression_scorer.py --scorer regime --csv regime_training.csv --out output --metric log_loss

Design goal:
  Use conservative logistic regression with small grid-search. This keeps weights interpretable,
  tiny, and compatible with MQL5 float32 binary readers.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, brier_score_loss, f1_score, log_loss, roc_auc_score
from sklearn.model_selection import TimeSeriesSplit, StratifiedKFold

MAGIC = 20260609.0
VERSION = 1.0

BINARY_SCORERS: dict[str, dict[str, Any]] = {
    "sr_zone": {
        "file": "PASR_sr_zone_weights.bin",
        "features": 7,
        "defaults": [-2.35, 1.60, 1.45, 1.05, 1.15, 0.75, 0.80, 0.40],
        "names": ["distanceQuality", "strengthNorm", "touchNorm", "recencyScore", "reactionNorm", "htfScore", "mergeNorm"],
    },
    "exit_pressure": {
        "file": "PASR_exit_pressure_weights.bin",
        "features": 7,
        "defaults": [-2.40, 0.70, 1.10, 0.80, 1.40, 2.20, 1.60, 0.60],
        "names": ["profitNorm", "adverseMoveNorm", "barsHeldNorm", "rsiFadeNorm", "structureBreakNorm", "chandelierProximity", "volatilityNorm"],
    },
    "entry_quality": {
        "file": "PASR_entry_quality_weights.bin",
        "features": 8,
        "defaults": [-3.00, 1.25, 1.35, 0.85, 1.10, 1.20, 0.70, 0.60, 0.55],
        "names": ["patternScore", "zoneScore", "regimeConfidence", "aiScore", "rrNorm", "spreadQuality", "volatilityQuality", "sessionQuality"],
    },
    "recovery": {
        "file": "PASR_recovery_weights.bin",
        "features": 7,
        "defaults": [-2.85, -1.10, 1.35, 1.20, 0.95, 0.70, 1.40, 0.90],
        "names": ["lossNorm", "zoneQuality", "patternRecovery", "regimeStability", "spreadQuality", "drawdownSafety", "retrySafety"],
    },
    "session_quality": {
        "file": "PASR_session_quality_weights.bin",
        "features": 7,
        "defaults": [-2.20, 0.30, 0.20, 1.30, 0.95, 0.85, 0.90, 1.10],
        "names": ["hourNorm", "dayNorm", "spreadQuality", "volatilityQuality", "volumeQuality", "overlapFlag", "newsSafety"],
    },
}

REGIME_CLASSES = ["trend", "range", "volatile", "squeeze", "transition"]
REGIME_ALIASES = {"trend_up": "trend", "trend_down": "trend", "crash": "volatile", "vol": "volatile"}
REGIME_DEFAULTS = {
    "trend":      [-3.00, -0.30, 3.40, 0.30, -0.80, -1.20, 0.80],
    "range":      [-1.20, -0.80, -2.00, 0.20, 0.80, -1.20, -0.40],
    "volatile":   [-2.80, 3.20, 0.40, 0.00, -0.20, 1.30, -0.20],
    "squeeze":    [-2.10, -0.70, -0.80, 0.00, 2.80, -0.80, -0.30],
    "transition": [-1.40, 0.30, 0.40, -0.10, 0.20, -0.20, 0.20],
}

PATTERN_CLASSES = ["pinbar", "engulf", "tweezer", "fakey", "inside"]
PATTERN_DEFAULTS = {
    "pinbar":  [-2.20, 2.80, 1.30, 1.00, 0.70, 0.00],
    "engulf":  [-2.05, 2.20, 1.25, 1.25, 0.80, 0.00],
    "tweezer": [-2.10, 2.60, 1.40, 1.00, 0.65, 0.00],
    "fakey":   [-2.00, 2.00, 1.65, 1.15, 0.90, 0.00],
    "inside":  [-2.15, 2.40, 1.55, 1.20, 0.55, 0.00],
}


@dataclass
class CandidateResult:
    params: dict[str, Any]
    score: float
    threshold: float
    metrics: dict[str, float]


def feature_cols(n: int) -> list[str]:
    return [f"f{i}" for i in range(n)]


def normalize_label(value: object) -> str:
    s = str(value).strip().lower().replace(" ", "_").replace("-", "_")
    return REGIME_ALIASES.get(s, s)


def parse_grid(values: str, cast=float) -> list[Any]:
    return [cast(v.strip()) for v in values.split(",") if v.strip()]


def safe_metrics(y_true: np.ndarray, proba: np.ndarray, threshold: float, sample_weight: np.ndarray | None = None) -> dict[str, float]:
    pred = (proba >= threshold).astype(int)
    out: dict[str, float] = {
        "accuracy": float(accuracy_score(y_true, pred, sample_weight=sample_weight)),
        "f1": float(f1_score(y_true, pred, sample_weight=sample_weight, zero_division=0)),
        "brier": float(brier_score_loss(y_true, proba, sample_weight=sample_weight)),
    }
    try:
        out["log_loss"] = float(log_loss(y_true, proba, sample_weight=sample_weight, labels=[0, 1]))
    except Exception:
        out["log_loss"] = float("nan")
    try:
        out["roc_auc"] = float(roc_auc_score(y_true, proba, sample_weight=sample_weight))
    except Exception:
        out["roc_auc"] = float("nan")
    return out


def metric_value(metrics: dict[str, float], metric: str) -> float:
    value = metrics.get(metric, float("nan"))
    if math.isnan(value):
        return -1e9 if metric in {"accuracy", "f1", "roc_auc"} else 1e9
    return value


def is_better(candidate: CandidateResult | None, best: CandidateResult | None, metric: str) -> bool:
    if best is None:
        return True
    if candidate is None:
        return False
    if metric in {"brier", "log_loss"}:
        return candidate.score < best.score
    return candidate.score > best.score


def load_binary_df(path: str, n_features: int) -> pd.DataFrame:
    df = pd.read_csv(path, comment="#")
    required = {"label", *feature_cols(n_features)}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    df = df.copy()
    for c in feature_cols(n_features):
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0.0).clip(0.0, 1.0)
    df["label"] = pd.to_numeric(df["label"], errors="coerce").fillna(0).astype(int).clip(0, 1)
    if "weight" in df.columns:
        df["weight"] = pd.to_numeric(df["weight"], errors="coerce").fillna(1.0).clip(0.1, 10.0)
    else:
        df["weight"] = 1.0
    return df


def get_cv(n_rows: int, n_splits: int, time_series: bool, y: np.ndarray):
    splits = max(2, min(n_splits, n_rows // 2))
    if time_series:
        return TimeSeriesSplit(n_splits=splits).split(np.zeros(n_rows), y)
    min_class = int(min(np.bincount(y))) if len(set(y.tolist())) == 2 else 0
    if min_class >= splits:
        return StratifiedKFold(n_splits=splits, shuffle=True, random_state=42).split(np.zeros(n_rows), y)
    return TimeSeriesSplit(n_splits=splits).split(np.zeros(n_rows), y)


def fit_model(X: np.ndarray, y: np.ndarray, w: np.ndarray, c_value: float, class_weight: str | None, max_iter: int) -> LogisticRegression:
    model = LogisticRegression(
        solver="lbfgs",
        C=c_value,
        max_iter=max_iter,
        random_state=42,
        class_weight=class_weight,
    )
    model.fit(X, y, sample_weight=w)
    return model


def tune_binary_weights(
    df: pd.DataFrame,
    n_features: int,
    default_weights: list[float],
    c_grid: list[float],
    threshold_grid: list[float],
    class_weight_grid: list[str | None],
    metric: str,
    n_splits: int,
    time_series: bool,
    min_samples: int,
    max_iter: int,
) -> tuple[list[float], dict[str, Any]]:
    y = df["label"].to_numpy(np.int32)
    X = df[feature_cols(n_features)].to_numpy(np.float32)
    w = df["weight"].to_numpy(np.float32)

    report: dict[str, Any] = {"n": int(len(df)), "positives": int(y.sum()), "used_fallback": False, "candidates": []}
    if len(df) < min_samples or len(set(y.tolist())) < 2:
        report.update({"used_fallback": True, "reason": "not enough samples or only one class"})
        return default_weights, report

    best: CandidateResult | None = None
    for c_value in c_grid:
        for class_weight in class_weight_grid:
            for threshold in threshold_grid:
                fold_metrics: list[dict[str, float]] = []
                for train_idx, test_idx in get_cv(len(df), n_splits, time_series, y):
                    if len(set(y[train_idx].tolist())) < 2 or len(test_idx) == 0:
                        continue
                    model = fit_model(X[train_idx], y[train_idx], w[train_idx], c_value, class_weight, max_iter)
                    proba = model.predict_proba(X[test_idx])[:, 1]
                    fold_metrics.append(safe_metrics(y[test_idx], proba, threshold, w[test_idx]))
                if not fold_metrics:
                    continue
                avg = {k: float(np.nanmean([m[k] for m in fold_metrics])) for k in fold_metrics[0].keys()}
                candidate = CandidateResult(
                    params={"C": c_value, "class_weight": class_weight, "max_iter": max_iter},
                    score=metric_value(avg, metric),
                    threshold=threshold,
                    metrics=avg,
                )
                report["candidates"].append({**candidate.params, "threshold": threshold, "score": candidate.score, "metrics": avg})
                if is_better(candidate, best, metric):
                    best = candidate

    if best is None:
        report.update({"used_fallback": True, "reason": "no valid CV candidate"})
        return default_weights, report

    final_model = fit_model(X, y, w, float(best.params["C"]), best.params["class_weight"], max_iter)
    weights = [float(final_model.intercept_[0])] + [float(v) for v in final_model.coef_[0]]
    in_sample = safe_metrics(y, final_model.predict_proba(X)[:, 1], best.threshold, w)
    report.update({
        "best": {"params": best.params, "threshold": best.threshold, "cv_metric": metric, "cv_score": best.score, "cv_metrics": best.metrics},
        "in_sample_metrics": in_sample,
        "weights": weights,
    })
    return weights, report


def export_float32(values: list[float], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack(f"{len(values)}f", *[float(v) for v in values]))


def run_binary_scorer(args: argparse.Namespace) -> dict[str, Any]:
    spec = BINARY_SCORERS[args.scorer]
    n_features = int(spec["features"])
    df = load_binary_df(args.csv, n_features)
    weights, report = tune_binary_weights(
        df=df,
        n_features=n_features,
        default_weights=list(spec["defaults"]),
        c_grid=args.c_grid,
        threshold_grid=args.threshold_grid,
        class_weight_grid=args.class_weight_grid,
        metric=args.metric,
        n_splits=args.cv_splits,
        time_series=args.time_series,
        min_samples=args.min_samples,
        max_iter=args.max_iter,
    )
    values = [MAGIC, VERSION, float(n_features)] + weights
    out_path = Path(args.out) / spec["file"]
    export_float32(values, out_path)
    report.update({"scorer": args.scorer, "output_file": str(out_path), "feature_contract": {f"f{i}": n for i, n in enumerate(spec["names"])}})
    return report


def run_regime(args: argparse.Namespace) -> dict[str, Any]:
    df = pd.read_csv(args.csv, comment="#")
    required = {"label", *feature_cols(6)}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    df = df.copy()
    df["label"] = df["label"].map(normalize_label)
    df = df[df["label"].isin(REGIME_CLASSES)]
    for c in feature_cols(6):
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0.0).clip(0.0, 1.0)
    if "weight" in df.columns:
        df["weight"] = pd.to_numeric(df["weight"], errors="coerce").fillna(1.0).clip(0.1, 10.0)
    else:
        df["weight"] = 1.0

    report: dict[str, Any] = {"scorer": "regime", "classes": []}
    weights_by_class: dict[str, list[float]] = {}
    for cls in REGIME_CLASSES:
        one = df.copy()
        one["label"] = (one["label"] == cls).astype(int)
        weights, cls_report = tune_binary_weights(
            df=one,
            n_features=6,
            default_weights=REGIME_DEFAULTS[cls],
            c_grid=args.c_grid,
            threshold_grid=args.threshold_grid,
            class_weight_grid=args.class_weight_grid,
            metric=args.metric,
            n_splits=args.cv_splits,
            time_series=args.time_series,
            min_samples=args.min_samples,
            max_iter=args.max_iter,
        )
        weights_by_class[cls] = weights
        report["classes"].append({"class": cls, **cls_report})

    values = [MAGIC, VERSION, float(len(REGIME_CLASSES)), 6.0]
    for cls in REGIME_CLASSES:
        values.extend(weights_by_class[cls])
    out_path = Path(args.out) / "PASR_regime_weights.bin"
    export_float32(values, out_path)
    report["output_file"] = str(out_path)
    report["feature_contract"] = {"f0": "volNorm", "f1": "adxNorm", "f2": "momentumNorm", "f3": "bbCompression", "f4": "crashPressure", "f5": "currentTrendFlag"}
    return report


def run_pattern(args: argparse.Namespace) -> dict[str, Any]:
    df = pd.read_csv(args.csv, comment="#")
    required = {"pattern", "label", *feature_cols(5)}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")
    df = df.copy()
    df["pattern"] = df["pattern"].astype(str).str.lower().str.strip()
    df = df[df["pattern"].isin(PATTERN_CLASSES)]
    for c in feature_cols(5):
        df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0.0).clip(0.0, 1.0)
    df["label"] = pd.to_numeric(df["label"], errors="coerce").fillna(0).astype(int).clip(0, 1)
    if "weight" in df.columns:
        df["weight"] = pd.to_numeric(df["weight"], errors="coerce").fillna(1.0).clip(0.1, 10.0)
    else:
        df["weight"] = 1.0

    report: dict[str, Any] = {"scorer": "pattern", "patterns": []}
    weights_by_pattern: dict[str, list[float]] = {}
    for pat in PATTERN_CLASSES:
        one = df[df["pattern"] == pat].copy()
        if len(one) == 0:
            weights_by_pattern[pat] = PATTERN_DEFAULTS[pat]
            report["patterns"].append({"pattern": pat, "used_fallback": True, "reason": "no rows"})
            continue
        weights, pat_report = tune_binary_weights(
            df=one,
            n_features=5,
            default_weights=PATTERN_DEFAULTS[pat],
            c_grid=args.c_grid,
            threshold_grid=args.threshold_grid,
            class_weight_grid=args.class_weight_grid,
            metric=args.metric,
            n_splits=args.cv_splits,
            time_series=args.time_series,
            min_samples=args.min_samples,
            max_iter=args.max_iter,
        )
        weights_by_pattern[pat] = weights
        report["patterns"].append({"pattern": pat, **pat_report})

    values = [MAGIC, VERSION, float(len(PATTERN_CLASSES)), 5.0]
    for pat in PATTERN_CLASSES:
        values.extend(weights_by_pattern[pat])
    out_path = Path(args.out) / "PASR_pattern_weights.bin"
    export_float32(values, out_path)
    report["output_file"] = str(out_path)
    report["feature_contract"] = {"f0": "shape/body quality", "f1": "rejection quality", "f2": "context", "f3": "follow-through", "f4": "reserved/extra"}
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Tune PASR regression-style scorer hyperparameters")
    parser.add_argument("--scorer", required=True, choices=["pattern", "regime", *BINARY_SCORERS.keys()])
    parser.add_argument("--csv", required=True)
    parser.add_argument("--out", default="output")
    parser.add_argument("--metric", default="brier", choices=["brier", "log_loss", "accuracy", "f1", "roc_auc"])
    parser.add_argument("--c-grid", default="0.03,0.1,0.3,1.0,3.0")
    parser.add_argument("--threshold-grid", default="0.40,0.45,0.50,0.55,0.60,0.65")
    parser.add_argument("--class-weight-grid", default="none,balanced", help="comma list: none,balanced")
    parser.add_argument("--cv-splits", type=int, default=5)
    parser.add_argument("--time-series", action="store_true", help="Use time-series CV instead of shuffled stratified CV when possible")
    parser.add_argument("--min-samples", type=int, default=80)
    parser.add_argument("--max-iter", type=int, default=1000)
    args = parser.parse_args()

    args.c_grid = parse_grid(args.c_grid, float)
    args.threshold_grid = parse_grid(args.threshold_grid, float)
    args.class_weight_grid = [None if v.strip().lower() in {"none", "null", "0"} else v.strip() for v in args.class_weight_grid.split(",") if v.strip()]

    if args.scorer == "regime":
        report = run_regime(args)
    elif args.scorer == "pattern":
        report = run_pattern(args)
    else:
        report = run_binary_scorer(args)

    report.update({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "input_csv": os.path.abspath(args.csv),
        "hyperparameters": {
            "metric": args.metric,
            "c_grid": args.c_grid,
            "threshold_grid": args.threshold_grid,
            "class_weight_grid": args.class_weight_grid,
            "cv_splits": args.cv_splits,
            "time_series": bool(args.time_series),
            "min_samples": args.min_samples,
            "max_iter": args.max_iter,
        },
    })

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / f"{args.scorer}_tuning_report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"[tune_regression_scorer] wrote report: {report_path}")
    print(f"[tune_regression_scorer] wrote model: {report.get('output_file')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
