#!/usr/bin/env python3
"""
walkforward_harness.py — PASR Walk-Forward Test Harness
========================================================
Splits a date range into N in-sample / out-of-sample windows,
runs MT5 Strategy Tester for each window via subprocess (MT5 CLI),
aggregates equity curves, and exports a combined HTML report.

Usage:
    python walkforward_harness.py [OPTIONS]

Options:
    --mt5       PATH    Path to MetaTrader5 terminal64.exe
    --ea        NAME    EA filename (default: PASR_MODULAR)
    --symbol    SYM     Symbol (default: EURUSD)
    --tf        TF      Timeframe (default: H1)
    --start     DATE    History start YYYY-MM-DD (default: 2023-01-01)
    --end       DATE    History end   YYYY-MM-DD (default: today)
    --windows   N       Number of WF windows (default: 6)
    --is-ratio  R       In-sample ratio 0..1 (default: 0.70)
    --out       DIR     Output directory (default: wf_output)
    --deposit   D       Initial deposit (default: 10000)
    --currency  C       Deposit currency (default: USD)

Requirements:
    pip install pandas numpy matplotlib
    MetaTrader5 terminal must be installed (Windows only for actual runs).
    On non-Windows / CI, harness generates mock equity curves for testing.
"""

import argparse
import csv
import json
import os
import platform
import subprocess
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DEFAULT_MT5    = r"C:\Program Files\MetaTrader 5\terminal64.exe"
DEFAULT_EA     = "PASR_MODULAR"
DEFAULT_SYMBOL = "EURUSD"
DEFAULT_TF     = "H1"
DEFAULT_START  = "2023-01-01"
DEFAULT_END    = date.today().isoformat()
DEFAULT_WINDOWS = 6
DEFAULT_IS_RATIO = 0.70
DEFAULT_DEPOSIT  = 10000
DEFAULT_CURRENCY = "USD"


# ---------------------------------------------------------------------------
# Date helpers
# ---------------------------------------------------------------------------
def parse_date(s: str) -> date:
    return datetime.strptime(s, "%Y-%m-%d").date()


def split_windows(start: date, end: date, n_windows: int, is_ratio: float):
    """Return list of (is_start, is_end, oos_start, oos_end) tuples."""
    total_days = (end - start).days
    window_size = total_days // n_windows
    is_size  = int(window_size * is_ratio)
    oos_size = window_size - is_size
    windows = []
    for i in range(n_windows):
        w_start  = start + timedelta(days=i * window_size)
        is_start = w_start
        is_end   = w_start + timedelta(days=is_size - 1)
        oos_start= is_end  + timedelta(days=1)
        oos_end  = oos_start + timedelta(days=oos_size - 1)
        if oos_end > end:
            oos_end = end
        if oos_start >= end:
            break
        windows.append((is_start, is_end, oos_start, oos_end))
    return windows


# ---------------------------------------------------------------------------
# MT5 INI generator for Strategy Tester CLI
# ---------------------------------------------------------------------------
def write_tester_ini(path: str, ea: str, symbol: str, tf: str,
                    start: date, end: date,
                    deposit: int, currency: str):
    content = f"""[Tester]
Expert={ea}
Symbol={symbol}
Period={tf}
FromDate={start.strftime('%Y.%m.%d')}
ToDate={end.strftime('%Y.%m.%d')}
Deposit={deposit}
Currency={currency}
Model=1
ExecutionMode=0
Optimization=0
OptimizationCriterion=0
Report=result
ReplaceReport=1
ShutdownTerminal=1
"""
    with open(path, "w") as f:
        f.write(content)


# ---------------------------------------------------------------------------
# Run one backtest window
# ---------------------------------------------------------------------------
def run_backtest(mt5_path: str, ini_path: str, out_dir: str, window_id: int) -> dict:
    """Run MT5 tester via CLI. Returns dict with equity curve data."""
    is_windows = platform.system() == "Windows"

    if is_windows and os.path.exists(mt5_path):
        report_path = os.path.join(out_dir, f"result_w{window_id}.xml")
        cmd = [
            mt5_path,
            f"/config:{ini_path}",
            f"/log:{os.path.join(out_dir, f'log_w{window_id}.log')}",
        ]
        try:
            subprocess.run(cmd, timeout=300, check=True)
            return parse_mt5_report(report_path)
        except Exception as e:
            print(f"  [WF] Window {window_id} MT5 run failed: {e}")
            return generate_mock_result(window_id)
    else:
        # Non-Windows or MT5 not found: generate mock data for CI/testing
        print(f"  [WF] Window {window_id}: MT5 not available, using mock data")
        return generate_mock_result(window_id)


def parse_mt5_report(xml_path: str) -> dict:
    """Parse MT5 XML report. Returns equity curve + summary stats."""
    if not os.path.exists(xml_path):
        return generate_mock_result(0)
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(xml_path)
        root = tree.getroot()
        equity = []
        for deal in root.iter("Deal"):
            eq = deal.get("equity")
            if eq:
                equity.append(float(eq))
        profit = float(root.findtext(".//NetProfit", "0"))
        dd     = float(root.findtext(".//MaxDrawdown", "0"))
        trades = int(root.findtext(".//Trades", "0"))
        return {"equity": equity, "net_profit": profit,
                "max_dd": dd, "trades": trades, "source": "mt5"}
    except Exception as e:
        print(f"  [WF] XML parse failed: {e}")
        return generate_mock_result(0)


def generate_mock_result(seed: int) -> dict:
    """Generate synthetic equity curve for testing/CI."""
    rng = np.random.RandomState(seed + 42)
    n = 100
    returns = rng.normal(0.0008, 0.012, n)
    equity  = 10000 * np.cumprod(1 + returns)
    dd = float(np.max(np.maximum.accumulate(equity) - equity) / np.max(equity) * 100)
    return {
        "equity":     equity.tolist(),
        "net_profit": float(equity[-1] - equity[0]),
        "max_dd":     dd,
        "trades":     int(rng.randint(20, 80)),
        "source":     "mock",
    }


# ---------------------------------------------------------------------------
# Aggregate + HTML report
# ---------------------------------------------------------------------------
def compute_wf_stats(results: list[dict], windows: list) -> dict:
    profits  = [r["net_profit"] for r in results]
    dds      = [r["max_dd"]     for r in results]
    trades   = [r["trades"]     for r in results]
    pf_ratio = sum(p for p in profits if p > 0) / max(1, abs(sum(p for p in profits if p < 0)))
    return {
        "n_windows":      len(results),
        "total_profit":   sum(profits),
        "avg_profit":     float(np.mean(profits)),
        "win_windows":    sum(1 for p in profits if p > 0),
        "avg_max_dd":     float(np.mean(dds)),
        "max_max_dd":     float(np.max(dds)),
        "total_trades":   sum(trades),
        "profit_factor":  pf_ratio,
        "consistency":    float(np.std(profits)),
    }


def generate_wf_html(windows, results, stats, args, out_dir: str):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, axes = plt.subplots(1, 3, figsize=(15, 4))

        # [0] Equity curves per OOS window
        colors = plt.cm.tab10.colors
        for i, r in enumerate(results):
            eq = r["equity"]
            axes[0].plot(np.linspace(0, 1, len(eq)), eq,
                         color=colors[i % 10], alpha=0.8,
                         label=f"W{i+1} ({'mock' if r['source']=='mock' else 'live'})")
        axes[0].set_title("OOS Equity Curves")
        axes[0].set_xlabel("Normalized time")
        axes[0].set_ylabel("Equity")
        axes[0].legend(fontsize=7)

        # [1] Net profit per window
        profits = [r["net_profit"] for r in results]
        bar_colors = ["green" if p > 0 else "red" for p in profits]
        axes[1].bar(range(1, len(profits)+1), profits, color=bar_colors)
        axes[1].axhline(0, color="black", linewidth=0.8)
        axes[1].set_title("OOS Net Profit per Window")
        axes[1].set_xlabel("Window")
        axes[1].set_ylabel("Profit (USD)")

        # [2] Max DD per window
        dds = [r["max_dd"] for r in results]
        axes[2].bar(range(1, len(dds)+1), dds, color="#a12c7b", alpha=0.7)
        axes[2].set_title("Max Drawdown per Window (%)")
        axes[2].set_xlabel("Window")
        axes[2].set_ylabel("Max DD %")

        plt.tight_layout()
        chart_path = os.path.join(out_dir, "wf_charts.png")
        plt.savefig(chart_path, dpi=120)
        plt.close()
        chart_html = '<img src="wf_charts.png" style="max-width:100%">'
    except Exception as e:
        chart_html = f"<p>Chart error: {e}</p>"

    rows = ""
    for i, (r, w) in enumerate(zip(results, windows)):
        is_s, is_e, oos_s, oos_e = w
        color = "green" if r["net_profit"] > 0 else "red"
        rows += f"""
        <tr>
          <td>W{i+1}</td>
          <td>{is_s} → {is_e}</td>
          <td>{oos_s} → {oos_e}</td>
          <td style='color:{color};font-weight:600'>{r['net_profit']:+.2f}</td>
          <td>{r['max_dd']:.1f}%</td>
          <td>{r['trades']}</td>
          <td style='color:#7a7974;font-size:12px'>{r['source']}</td>
        </tr>"""

    def badge(val, good_thresh, warn_thresh, higher_is_better=True):
        if higher_is_better:
            cls = "good" if val >= good_thresh else ("warn" if val >= warn_thresh else "bad")
        else:
            cls = "good" if val <= good_thresh else ("warn" if val <= warn_thresh else "bad")
        label = "GOOD" if cls == "good" else ("WARN" if cls == "warn" else "POOR")
        return f'<span class="badge {cls}">{label}</span>'

    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>PASR Walk-Forward Report</title>
<style>
  body  {{ font-family:'Segoe UI',sans-serif;max-width:1100px;margin:40px auto;
           background:#f7f6f2;color:#28251d; }}
  h1    {{ color:#01696f; }}
  h2    {{ border-bottom:1px solid #dcd9d5;padding-bottom:6px; }}
  table {{ border-collapse:collapse;width:100%;margin:16px 0; }}
  th    {{ background:#01696f;color:white;padding:8px 12px;text-align:left; }}
  td    {{ padding:7px 12px;border-bottom:1px solid #dcd9d5; }}
  tr:nth-child(even) td {{ background:#f3f0ec; }}
  .badge {{ display:inline-block;padding:3px 10px;border-radius:999px;
            font-size:12px;font-weight:600; }}
  .good {{ background:#d4dfcc;color:#1e3f0a; }}
  .warn {{ background:#e7d7c4;color:#4b2614; }}
  .bad  {{ background:#e0ced7;color:#561740; }}
  .stat {{ display:inline-block;background:white;border:1px solid #dcd9d5;
           border-radius:8px;padding:12px 20px;margin:6px;min-width:160px;
           text-align:center; }}
  .stat-val {{ font-size:22px;font-weight:700;color:#01696f; }}
  .stat-lbl {{ font-size:12px;color:#7a7974;margin-top:4px; }}
</style>
</head>
<body>
<h1>&#x1F4C8; PASR Walk-Forward Report</h1>
<p>EA: <strong>{args.ea}</strong> &nbsp;|&nbsp;
   Symbol: <strong>{args.symbol}</strong> &nbsp;|&nbsp;
   TF: <strong>{args.tf}</strong> &nbsp;|&nbsp;
   Period: {args.start} → {args.end} &nbsp;|&nbsp;
   Windows: {stats['n_windows']} &nbsp;|&nbsp;
   IS ratio: {int(args.is_ratio*100)}%</p>

<h2>Summary</h2>
<div>
  <div class="stat"><div class="stat-val">{stats['total_profit']:+.0f}</div>
    <div class="stat-lbl">Total OOS Profit (USD)</div></div>
  <div class="stat"><div class="stat-val">{stats['win_windows']}/{stats['n_windows']}</div>
    <div class="stat-lbl">Profitable Windows</div></div>
  <div class="stat"><div class="stat-val">{stats['profit_factor']:.2f}</div>
    <div class="stat-lbl">Profit Factor</div></div>
  <div class="stat"><div class="stat-val">{stats['avg_max_dd']:.1f}%</div>
    <div class="stat-lbl">Avg Max Drawdown</div></div>
  <div class="stat"><div class="stat-val">{stats['total_trades']}</div>
    <div class="stat-lbl">Total OOS Trades</div></div>
  <div class="stat"><div class="stat-val">{stats['consistency']:.0f}</div>
    <div class="stat-lbl">Profit Std Dev</div></div>
</div>

<h2>Walk-Forward Assessment</h2>
<table>
  <tr><th>Metric</th><th>Value</th><th>Status</th></tr>
  <tr><td>Profit Factor</td><td>{stats['profit_factor']:.2f}</td>
      <td>{badge(stats['profit_factor'], 1.5, 1.1)}</td></tr>
  <tr><td>Win Windows %</td><td>{stats['win_windows']/stats['n_windows']*100:.0f}%</td>
      <td>{badge(stats['win_windows']/stats['n_windows'], 0.60, 0.40)}</td></tr>
  <tr><td>Avg Max DD</td><td>{stats['avg_max_dd']:.1f}%</td>
      <td>{badge(stats['avg_max_dd'], 10, 20, higher_is_better=False)}</td></tr>
  <tr><td>Consistency (lower StdDev=better)</td><td>{stats['consistency']:.0f}</td>
      <td>{badge(stats['consistency'], 500, 1500, higher_is_better=False)}</td></tr>
</table>

<h2>Per-Window Results</h2>
<table>
  <tr><th>Window</th><th>In-Sample</th><th>Out-of-Sample</th>
      <th>OOS Profit</th><th>Max DD</th><th>Trades</th><th>Source</th></tr>
  {rows}
</table>

<h2>Charts</h2>
{chart_html}

<h2>Interpretation Guide</h2>
<ul>
  <li><strong>Profit Factor &gt; 1.5 in all windows</strong> → strategy is robust across regimes</li>
  <li><strong>Any loss window</strong> → check if it correlates with high-volatility or ranging regime</li>
  <li><strong>StdDev &gt; 1500</strong> → inconsistent behavior, may need regime filter adjustment</li>
  <li><strong>Mock source</strong> → MT5 not available; run on Windows with MT5 installed for real results</li>
</ul>

<hr>
<p style="color:#7a7974;font-size:13px">Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M')} UTC
&mdash; PASR EA &copy; 2026 &mdash; walkforward_harness.py</p>
</body></html>
"""
    report_path = os.path.join(out_dir, "wf_report.html")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[WF] HTML report -> {report_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="PASR Walk-Forward Harness")
    parser.add_argument("--mt5",       default=DEFAULT_MT5)
    parser.add_argument("--ea",        default=DEFAULT_EA)
    parser.add_argument("--symbol",    default=DEFAULT_SYMBOL)
    parser.add_argument("--tf",        default=DEFAULT_TF)
    parser.add_argument("--start",     default=DEFAULT_START)
    parser.add_argument("--end",       default=DEFAULT_END)
    parser.add_argument("--windows",   type=int,   default=DEFAULT_WINDOWS)
    parser.add_argument("--is-ratio",  type=float, default=DEFAULT_IS_RATIO, dest="is_ratio")
    parser.add_argument("--out",       default="wf_output")
    parser.add_argument("--deposit",   type=int,   default=DEFAULT_DEPOSIT)
    parser.add_argument("--currency",  default=DEFAULT_CURRENCY)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    start_d = parse_date(args.start)
    end_d   = parse_date(args.end)

    windows = split_windows(start_d, end_d, args.windows, args.is_ratio)
    print(f"[WF] {len(windows)} windows | EA={args.ea} {args.symbol}/{args.tf}")
    for i, (is_s, is_e, oos_s, oos_e) in enumerate(windows):
        print(f"  W{i+1}: IS {is_s}→{is_e}  OOS {oos_s}→{oos_e}")

    results = []
    for i, (is_s, is_e, oos_s, oos_e) in enumerate(windows):
        print(f"\n[WF] Running window {i+1}/{len(windows)} OOS: {oos_s} → {oos_e}")
        ini = os.path.join(args.out, f"tester_w{i+1}.ini")
        write_tester_ini(ini, args.ea, args.symbol, args.tf,
                         oos_s, oos_e, args.deposit, args.currency)
        result = run_backtest(args.mt5, ini, args.out, i+1)
        results.append(result)
        print(f"  Profit={result['net_profit']:+.2f}  DD={result['max_dd']:.1f}%  "
              f"Trades={result['trades']}")

    stats = compute_wf_stats(results, windows)
    print(f"\n[WF] Summary: PF={stats['profit_factor']:.2f}  "
          f"WinW={stats['win_windows']}/{stats['n_windows']}  "
          f"TotalProfit={stats['total_profit']:+.2f}")

    generate_wf_html(windows, results, stats, args, args.out)

    # Export JSON summary
    json_path = os.path.join(args.out, "wf_summary.json")
    with open(json_path, "w") as f:
        json.dump({"stats": stats, "windows": [
            {"is_start": str(w[0]), "is_end": str(w[1]),
             "oos_start": str(w[2]), "oos_end": str(w[3]),
             "result": r}
            for w, r in zip(windows, results)
        ]}, f, indent=2)
    print(f"[WF] JSON summary  -> {json_path}")
    print("[WF] === DONE ===")


if __name__ == "__main__":
    main()
