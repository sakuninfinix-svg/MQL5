#!/usr/bin/env python3
"""Download M15 OHLCV data for multiple symbols via dukascopy-node (parallel yearly chunks)."""
import os, sys, subprocess, shutil, tempfile, time
import pandas as pd
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed

SYMBOLS = ['eurusd', 'gbpusd', 'xauusd', 'usdjpy']
TIMEFRAME = 'm15'
YEARS = [2020, 2021, 2022, 2023, 2024, 2025]
OUTPUT_DIR = Path(__file__).resolve().parent.parent / 'output'
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
MAX_WORKERS = 4

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

def download_year_chunk(symbol, year, output_dir, retries=3):
    """Download one year of data for one symbol."""
    fname = f"{symbol}_{TIMEFRAME}_{year}.csv"
    fpath = os.path.join(output_dir, fname)
    if os.path.exists(fpath) and os.path.getsize(fpath) > 10000:
        return fpath, year, "cached"

    for attempt in range(retries):
        try:
            with tempfile.TemporaryDirectory() as tmp:
                subprocess.run([
                    'npx', 'dukascopy-node',
                    '-i', symbol,
                    '-from', f'{year}-01-01',
                    '-to', f'{year}-12-31',
                    '-t', TIMEFRAME,
                    '-p', 'bid',
                    '-v',
                    '-f', 'csv',
                    '-dir', tmp,
                    '-bs', '10',
                    '-bp', '500',
                    '-r', '3',
                    '-rp', '5000',
                    '--flats'
                ], check=True, capture_output=True, text=True, timeout=1200)

                for f in os.listdir(tmp):
                    if f.endswith('.csv'):
                        src = os.path.join(tmp, f)
                        df = pd.read_csv(src)
                        if 'timestamp' in df.columns and df['timestamp'].dtype == 'int64':
                            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='ms')
                        df = df.sort_values('timestamp').reset_index(drop=True)
                        
                        col_map = {}
                        for c in df.columns:
                            cl = c.lower()
                            if cl in ['timestamp','time','date']: col_map[c] = 'timestamp'
                            elif cl in ['open','o']: col_map[c] = 'open'
                            elif cl in ['high','h']: col_map[c] = 'high'
                            elif cl in ['low','l']: col_map[c] = 'low'
                            elif cl in ['close','c']: col_map[c] = 'close'
                            elif cl in ['volume','vol','tickvolume','tick_volume']: col_map[c] = 'volume'
                        df = df.rename(columns=col_map)
                        cols = ['timestamp','open','high','low','close']
                        if 'volume' in df.columns: cols.append('volume')
                        df = df[[c for c in cols if c in df.columns]]
                        if 'volume' not in df.columns: df['volume'] = 1000
                        
                        df.to_csv(fpath, index=False)
                        return fpath, year, f"downloaded ({len(df)} bars)"

            if attempt < retries - 1:
                time.sleep(5)
        except subprocess.TimeoutExpired:
            log(f"  {symbol} {year}: timeout, retry {attempt+1}/{retries}")
        except subprocess.CalledProcessError as e:
            log(f"  {symbol} {year}: error: {str(e.stderr)[:100]}, retry {attempt+1}/{retries}")
        except Exception as e:
            log(f"  {symbol} {year}: {e}, retry {attempt+1}/{retries}")

    return None, year, "failed"

def download_symbol(symbol, output_dir):
    """Download all years for a symbol in parallel and merge."""
    log(f"Downloading {symbol} {TIMEFRAME}...")
    
    results = []
    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {executor.submit(download_year_chunk, symbol, y, str(output_dir)): y for y in YEARS}
        for future in as_completed(futures):
            result = future.result()
            if result[0]:
                results.append(result)
                log(f"  {result[1]}: {result[2]}")
            else:
                log(f"  {result[1]}: {result[2]}")

    if not results:
        log(f"  {symbol}: all years failed")
        return None

    # Merge all years into single file
    merged_path = output_dir / f"{symbol}_{TIMEFRAME}_{YEARS[0]}-{YEARS[-1]}.csv"
    chunks = []
    for fpath, year, status in results:
        df = pd.read_csv(fpath)
        chunks.append(df)
    
    df_all = pd.concat(chunks, ignore_index=True)
    if 'timestamp' in df_all.columns:
        df_all['timestamp'] = pd.to_datetime(df_all['timestamp'])
    df_all = df_all.drop_duplicates(subset=['timestamp']).sort_values('timestamp').reset_index(drop=True)
    df_all.to_csv(str(merged_path), index=False)
    
    log(f"  {symbol}: merged {len(df_all)} bars -> {merged_path.name}")
    return str(merged_path)

def main():
    log(f"Downloading {len(SYMBOLS)} symbols at {TIMEFRAME} (parallel yearly chunks) ...")
    results = {}
    for sym in SYMBOLS:
        results[sym] = download_symbol(sym, OUTPUT_DIR)
    
    log("\n=== Summary ===")
    for sym, path in results.items():
        if path:
            df = pd.read_csv(path)
            log(f"  {sym}: {len(df):,} bars, {str(df['timestamp'].iloc[0])[:10]} to {str(df['timestamp'].iloc[-1])[:10]}")
        else:
            log(f"  {sym}: FAILED")
    log(f"\nFiles in: {OUTPUT_DIR}")

if __name__ == '__main__':
    main()
