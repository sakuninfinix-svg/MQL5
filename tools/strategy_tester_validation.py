#!/usr/bin/env python3
"""
PASR Strategy Tester validation helper.

Creates an MT5 tester config for PASR_MODULAR, optionally runs terminal64.exe,
then inspects generated reports/logs/journals for business-logic validation gates.
No third-party Python dependencies are required.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path


DEFAULT_MT5 = Path(r"C:\Program Files\MetaTrader 5\terminal64.exe")
DEFAULT_MQL5 = Path(__file__).resolve().parents[1]


@dataclass
class ValidationResult:
    name: str
    passed: bool
    detail: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PASR Strategy Tester validation runner")
    parser.add_argument("--mql5-root", default=str(DEFAULT_MQL5), help="MQL5 root directory")
    parser.add_argument("--terminal", default=str(DEFAULT_MT5), help="Path to terminal64.exe")
    parser.add_argument("--symbol", default="EURUSD")
    parser.add_argument("--period", default="H1")
    parser.add_argument("--from-date", default="2024.01.01")
    parser.add_argument("--to-date", default="2024.03.31")
    parser.add_argument("--deposit", default="10000")
    parser.add_argument("--currency", default="USD")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--run", action="store_true", help="Run MT5 terminal after generating files")
    parser.add_argument("--out", default="", help="Output directory; defaults to Files/PASR_Validation/run_TIMESTAMP")
    return parser.parse_args()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def tester_ini(mql5_root: Path, out_dir: Path, args: argparse.Namespace) -> str:
    preset = mql5_root / "Presets" / "PASR_BusinessLogicValidation.set"
    report = out_dir / "PASR_MODULAR_validation_report"
    return f"""[Tester]
Expert=PASR_MODULAR
ExpertParameters={preset}
Symbol={args.symbol}
Period={args.period}
Login=0
Model=1
ExecutionMode=0
Optimization=0
OptimizationCriterion=0
FromDate={args.from_date}
ToDate={args.to_date}
ForwardMode=0
Deposit={args.deposit}
Currency={args.currency}
Leverage=100
Report={report}
ReplaceReport=1
ShutdownTerminal=1
Visual=0
UseLocal=1
UseRemote=0
UseCloud=0
"""


def run_terminal(terminal: Path, config: Path, out_dir: Path, timeout: int) -> tuple[int, str]:
    if not terminal.exists():
        return 127, f"terminal not found: {terminal}"

    log_path = out_dir / "terminal_cli.log"
    cmd = [str(terminal), f"/config:{str(config)}", f"/log:{str(log_path)}"]
    command_text = " ".join(cmd)
    try:
        proc = subprocess.Popen(cmd)
        return proc.wait(timeout=timeout), command_text
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except Exception:
            pass
        for image in ("terminal64.exe", "metatester64.exe"):
            subprocess.run(["taskkill", "/F", "/IM", image, "/T"],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL,
                           check=False)
        return 124, f"timeout after {timeout}s: {command_text}"
    except Exception as exc:
        return 1, f"terminal run failed: {exc}"


def find_files(out_dir: Path, patterns: list[str]) -> list[Path]:
    found: list[Path] = []
    for pattern in patterns:
        found.extend(out_dir.glob(pattern))
    return sorted(set(found))


def find_terminal_logs(mql5_root: Path, out_dir: Path) -> list[Path]:
    candidates: list[Path] = []
    parent = mql5_root.parent
    run_stamp = ""
    match = re.search(r"run_(\d{8})_", out_dir.name)
    if match:
        run_stamp = match.group(1)
    try:
        run_started = out_dir.stat().st_mtime
    except OSError:
        run_started = 0.0

    for folder in (mql5_root / "Logs", parent / "Logs", parent / "Tester" / "logs"):
        if folder.exists():
            for path in folder.glob("*.log"):
                if path.name.lower() == "metaeditor.log":
                    continue
                try:
                    mtime = path.stat().st_mtime
                except OSError:
                    mtime = 0.0
                if run_stamp and path.stem == run_stamp:
                    candidates.append(path)
                elif run_started > 0 and mtime >= run_started:
                    candidates.append(path)
    return sorted(candidates, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)[:10]


def read_maybe(path: Path) -> str:
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8", errors="ignore").replace("\x00", "")
    except Exception:
        return path.read_text(errors="ignore").replace("\x00", "")


def read_tail_maybe(path: Path, max_bytes: int = 256_000) -> str:
    if not path.exists():
        return ""
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
            data = handle.read()
        return data.decode("utf-8", errors="ignore").replace("\x00", "")
    except Exception:
        return read_maybe(path)[-max_bytes:]


def parse_report_text(text: str) -> dict[str, str]:
    stats: dict[str, str] = {}
    cleaned = re.sub(r"<[^>]+>", " ", text)
    cleaned = re.sub(r"\s+", " ", cleaned)
    keys = [
        "Total Net Profit",
        "Gross Profit",
        "Gross Loss",
        "Profit Factor",
        "Expected Payoff",
        "Balance Drawdown Maximal",
        "Equity Drawdown Maximal",
        "Total Trades",
    ]
    for key in keys:
        match = re.search(re.escape(key) + r"\s+([-+()0-9.,% ]+)", cleaned, re.IGNORECASE)
        if match:
            stats[key] = match.group(1).strip()
    return stats


def load_common_journal_rows(mql5_root: Path) -> tuple[Path | None, list[dict[str, str]]]:
    common_appdata = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    candidates = []
    if common_appdata.exists():
        candidates.extend(common_appdata.glob("PASR_Journal_*.csv"))
    candidates.extend((mql5_root / "Files").glob("PASR_Journal_*.csv"))
    candidates = sorted(candidates, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    if not candidates:
        return None, []
    latest = candidates[0]
    rows: list[dict[str, str]] = []
    try:
        with latest.open("r", encoding="utf-8", errors="ignore", newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                rows.append(dict(row))
    except Exception:
        return latest, []
    return latest, rows


def analyze(mql5_root: Path, out_dir: Path) -> tuple[list[ValidationResult], dict[str, object]]:
    results: list[ValidationResult] = []
    details: dict[str, object] = {}

    reports = find_files(out_dir, ["*.htm", "*.html", "*.xml", "*report*"])
    details["report_files"] = [str(p) for p in reports]
    results.append(ValidationResult("tester_report_created", bool(reports), f"{len(reports)} report file(s)"))

    report_stats: dict[str, str] = {}
    for report in reports:
        text = read_maybe(report)
        report_stats.update(parse_report_text(text))
    details["report_stats"] = report_stats

    logs = find_files(out_dir, ["*.log", "*.txt"])
    if not logs:
        logs = find_terminal_logs(mql5_root, out_dir)
    log_text = "\n".join(read_tail_maybe(p) for p in logs)
    details["log_files"] = [str(p) for p in logs]
    error_patterns = [
        r"\berror\b",
        r"\bcritical\b",
        r"\bfailed\b",
        r"\binvalid\b",
        r"\bexception\b",
        r"not synchronized",
        r"tester didn.t start",
        r"invalid account",
        r"authorization .* failed",
        r"cannot select symbol",
    ]
    error_hits: list[str] = []
    for pattern in error_patterns:
        error_hits.extend(re.findall(pattern, log_text, re.IGNORECASE))
    log_lower = log_text.lower()
    blocker_terms = [
        "not synchronized",
        "invalid account",
        "tester didn't start",
        "cannot select symbol",
        "authorization on",
        "failed (invalid account)",
    ]
    environment_blocked = any(term in log_lower for term in blocker_terms)
    details["environment_blocked"] = environment_blocked
    details["log_excerpt_tail"] = log_text[-2000:]
    results.append(ValidationResult("tester_environment_ready", not environment_blocked,
                                    "blocked by terminal/account/symbol sync" if environment_blocked else "environment ok"))
    results.append(ValidationResult("tester_log_no_obvious_errors", len(error_hits) == 0, f"{len(error_hits)} error keyword hit(s)"))

    journal_path, journal_rows = load_common_journal_rows(mql5_root)
    details["journal_file"] = str(journal_path) if journal_path else ""
    details["journal_rows"] = len(journal_rows)
    results.append(ValidationResult("journal_available", journal_path is not None, str(journal_path) if journal_path else "no PASR_Journal_*.csv found"))

    if journal_rows:
        required = ["ticket", "symbol", "direction", "ai_model_id", "ai_validation_valid", "ai_validation_reason"]
        missing = [c for c in required if c not in journal_rows[0]]
        results.append(ValidationResult("journal_schema_business_context", not missing, "missing=" + ",".join(missing) if missing else "schema ok"))
        non_empty_tickets = sum(1 for r in journal_rows if r.get("ticket", "0") not in ("", "0"))
        results.append(ValidationResult("journal_has_trade_rows", non_empty_tickets > 0, f"{non_empty_tickets} trade row(s)"))
    else:
        results.append(ValidationResult("journal_schema_business_context", False, "no journal rows"))
        results.append(ValidationResult("journal_has_trade_rows", False, "no journal rows"))

    return results, details


def main() -> int:
    args = parse_args()
    mql5_root = Path(args.mql5_root).resolve()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(args.out).resolve() if args.out else mql5_root / "Files" / "PASR_Validation" / f"run_{timestamp}"
    ensure_dir(out_dir)

    config_path = out_dir / "tester_pasr_validation.ini"
    write_text(config_path, tester_ini(mql5_root, out_dir, args))

    run_info = {"ran": False, "returncode": None, "command": ""}
    if args.run:
        code, command = run_terminal(Path(args.terminal), config_path, out_dir, args.timeout)
        run_info = {"ran": True, "returncode": code, "command": command}

    results, details = analyze(mql5_root, out_dir)
    summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "mql5_root": str(mql5_root),
        "out_dir": str(out_dir),
        "config": str(config_path),
        "run": run_info,
        "results": [asdict(r) for r in results],
        "details": details,
    }
    write_text(out_dir / "validation_summary.json", json.dumps(summary, indent=2))

    print(f"[PASR Validation] config: {config_path}")
    print(f"[PASR Validation] output: {out_dir}")
    if args.run:
        print(f"[PASR Validation] terminal returncode: {run_info['returncode']}")
    for item in results:
        status = "PASS" if item.passed else "FAIL"
        print(f"[{status}] {item.name}: {item.detail}")
    print(f"[PASR Validation] summary: {out_dir / 'validation_summary.json'}")

    return 0 if all(r.passed for r in results if r.name != "journal_has_trade_rows") else 2


if __name__ == "__main__":
    sys.exit(main())
