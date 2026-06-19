#!/usr/bin/env python3
"""
PASR Volatility Prediction Pipeline
=====================================
End-to-end pipeline:
1. Download OHLCV data (if missing)
2. Extract 34 AI features
3. Generate volatility sequences (lookback N bars → future vol over N bars)
4. Train Ridge volatility model + export .bin

Usage:
  python3 training/run_volatility_pipeline.py [--symbols eurusd,gbpusd,xauusd,usdjpy] [--timeframe m15]
"""
import os, sys, subprocess, time, json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / 'output'
TRAINING_DIR = BASE_DIR / 'training'

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def run_step(cmd, desc, timeout=7200):
    log(f"=== {desc} ===")
    log(f"$ {cmd}")
    t0 = time.time()
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        elapsed = time.time() - t0
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                log(f"  {line}")
        if result.stderr.strip():
            err = result.stderr.strip().split('\n')[-3:]
            for line in err:
                log(f"  ! {line}")
        log(f"  -> Done in {elapsed:.0f}s (code={result.returncode})")
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        log(f"  -> TIMEOUT after {timeout}s")
        return False

def check_data_files(symbols, timeframe):
    """Check which symbols have data files."""
    missing = []
    for sym in symbols:
        candidates = list(OUTPUT_DIR.glob(f"{sym}_{timeframe}_*.csv"))
        if candidates:
            best = max(candidates, key=lambda p: p.stat().st_size)
            if best.stat().st_size > 100000:
                log(f"  {sym}: {best.name} ({best.stat().st_size//1024} KB)")
                continue
        missing.append(sym)
    return missing

def main():
    import argparse
    parser = argparse.ArgumentParser(description="PASR Volatility Pipeline")
    parser.add_argument("--symbols", default="eurusd,gbpusd,xauusd,usdjpy",
                        help="Comma-separated symbols")
    parser.add_argument("--timeframe", default="m15",
                        help="Timeframe (m5, m15, m30, h1)")
    parser.add_argument("--seq-len", type=int, default=16,
                        help="Lookback sequence length")
    parser.add_argument("--forecast", type=int, default=8,
                        help="Forecast horizon in bars")
    parser.add_argument("--alpha", type=float, default=316.0,
                        help="Ridge regularization alpha")
    parser.add_argument("--skip-download", action="store_true",
                        help="Skip data download step")
    parser.add_argument("--skip-features", action="store_true",
                        help="Skip feature extraction (reuse cached)")
    parser.add_argument("--skip-train", action="store_true",
                        help="Skip model training")
    args = parser.parse_args()

    symbols = [s.strip() for s in args.symbols.split(',') if s.strip()]
    tf = args.timeframe

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    os.chdir(BASE_DIR)

    log("=" * 60)
    log("PASR Volatility Prediction Pipeline")
    log(f"Symbols: {symbols}, Timeframe: {tf}")
    log("=" * 60)

    # Step 1: Download data
    if not args.skip_download:
        missing = check_data_files(symbols, tf)
        if missing:
            log(f"Missing data for: {missing}. Would you like to download?")
            log("  Use dukascopy-node for each missing symbol.")
            for sym in missing:
                # Download yearly chunks
                for year in range(2020, 2026):
                    csv_name = f"{sym}_{tf}_{year}.csv"
                    csv_path = OUTPUT_DIR / csv_name
                    if csv_path.exists() and csv_path.stat().st_size > 100000:
                        log(f"  {sym} {year}: cached")
                        continue
                    log(f"  Downloading {sym} {tf} {year}...")
                    cmd = (f"npx dukascopy-node -i {sym} -from {year}-01-01 -to {year}-12-31 "
                           f"-t {tf} -p bid -v -f csv -dir {OUTPUT_DIR} "
                           f"-bs 15 -bp 300 -r 3 -rp 3000 --flats")
                    run_step(cmd, f"Download {sym} {year}", timeout=1800)
            
            # Merge yearly chunks into single file
            for sym in symbols:
                yearly = sorted(OUTPUT_DIR.glob(f"{sym}_{tf}_2*.csv"), key=lambda p: p.name)
                merged = OUTPUT_DIR / f"{sym}_{tf}_2020-2025.csv"
                if yearly:
                    import pandas as pd
                    chunks = [pd.read_csv(f, parse_dates=['timestamp']) for f in yearly]
                    df = pd.concat(chunks, ignore_index=True)
                    df = df.drop_duplicates(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)
                    df.to_csv(merged, index=False)
                    log(f"  Merged {sym}: {len(df)} bars -> {merged.name}")
        else:
            log("All data files exist.")
    else:
        log("Skipping download.")

    # Step 2: Generate volatility data
    if not args.skip_features:
        log("\n=== Generating Volatility Sequences ===")
        cmd = (f"python3 {TRAINING_DIR}/generate_volatility_data.py")
        run_step(cmd, "Generate volatility data", timeout=7200)
    else:
        log("Skipping feature extraction.")

    # Step 3: Find generated npz
    npz_candidates = list(OUTPUT_DIR.glob(f"volatility_{tf}*.npz"))
    if not npz_candidates:
        # Try H1 fallback
        npz_candidates = list(OUTPUT_DIR.glob("volatility_h1*.npz"))
    
    if not npz_candidates:
        log("ERROR: No volatility npz found. Run feature extraction first.")
        sys.exit(1)
    
    best_npz = max(npz_candidates, key=lambda p: p.stat().st_size)
    log(f"\nUsing: {best_npz.name} ({best_npz.stat().st_size//1024} KB)")

    # Step 4: Train model
    if not args.skip_train:
        log("\n=== Training Volatility Model ===")
        cmd = (f"python3 {TRAINING_DIR}/train_volatility_ridge.py "
               f"--npz {best_npz} --out {OUTPUT_DIR} --alpha {args.alpha}")
        run_step(cmd, "Train Ridge model", timeout=600)
    else:
        log("Skipping training.")

    # Print final results
    report_path = OUTPUT_DIR / "volatility_report.json"
    if report_path.exists():
        with open(report_path) as f:
            report = json.load(f)
        log("\n" + "=" * 60)
        log("FINAL RESULTS")
        log("=" * 60)
        log(f"  Model: {report['model']}")
        log(f"  Data: {report['n_train']+report['n_test']:,} samples ({report['n_features']} features)")
        log(f"  Test MSE:  {report['test_mse']:.3e}")
        log(f"  Test MAE:  {report['test_mae']:.3e}")
        log(f"  Pearson r: {report['pearson_r']:.4f}")
        log(f"  R² (vs mean):    {report['r2_vs_mean']:.4f}")
        log(f"  R² (vs persist): {report['r2_vs_persist']:.4f}")
        log(f"  Spread ratio:    {report['spread_ratio']:.1f}x")
        log(f"  Model file: PASR_vol_ridge.bin")
        log("=" * 60)
    else:
        log("No report found.")

if __name__ == '__main__':
    main()
