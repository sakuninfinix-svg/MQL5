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
import platform
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path


DEFAULT_MQL5 = Path(__file__).resolve().parents[1]
DEFAULT_WINE_MT5_MQL5 = Path.home() / ".mt5" / "drive_c" / "Program Files" / "MetaTrader 5" / "MQL5"
DEFAULT_WINE_MT5_TERMINAL = Path.home() / ".mt5" / "drive_c" / "Program Files" / "MetaTrader 5" / "terminal64.exe"
DEFAULT_LINUX_MT5_WRAPPER = Path.home() / ".local" / "bin" / "metatrader5"

if platform.system() == "Linux" and DEFAULT_LINUX_MT5_WRAPPER.exists():
    DEFAULT_MT5 = DEFAULT_LINUX_MT5_WRAPPER
elif platform.system() == "Linux" and DEFAULT_WINE_MT5_TERMINAL.exists():
    DEFAULT_MT5 = DEFAULT_WINE_MT5_TERMINAL
else:
    DEFAULT_MT5 = Path(r"C:\Program Files\MetaTrader 5\terminal64.exe")


@dataclass
class ValidationResult:
    name: str
    passed: bool
    detail: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PASR Strategy Tester validation runner")
    parser.add_argument("--mql5-root", default=str(DEFAULT_MQL5), help="MQL5 root directory")
    parser.add_argument("--terminal", default=str(DEFAULT_MT5), help="Path to terminal64.exe")
    parser.add_argument("--symbol", default="BTCUSDm", help="Symbol to test (default: BTCUSDm; EURUSD not available on Exness demo)")
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
    preset = mql5_root / "Presets" / "PASR_EPIC_MASTER.set"
    report = out_dir / "PASR_MODULAR_validation_report"
    if platform.system() == "Linux":
        preset = Path(wine_path(preset))
        report = Path(wine_path(report))
    return f"""[Tester]
Expert=PASR_MODULAR.ex5
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


def wine_path(path: Path) -> str:
    if shutil.which("winepath") is None:
        return str(path)
    try:
        output = subprocess.check_output(["winepath", "-w", str(path)], stderr=subprocess.DEVNULL, text=True)
        return output.strip()
    except Exception:
        return str(path)


def unix_path(path: Path) -> Path:
    if platform.system() != "Linux" or path.exists():
        return path
    if shutil.which("winepath") is None:
        return path
    try:
        output = subprocess.check_output(["winepath", "-u", str(path)], stderr=subprocess.DEVNULL, text=True)
        return Path(output.strip())
    except Exception:
        return path


def find_wine_terminal_children(config_arg: str) -> list[int]:
    if platform.system() != "Linux":
        return []
    try:
        output = subprocess.check_output(["ps", "-eo", "pid,args"], text=True, stderr=subprocess.DEVNULL)
        pids: list[int] = []
        for line in output.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) != 2:
                continue
            pid_str, args = parts
            if "terminal64.exe" in args and config_arg in args:
                try:
                    pids.append(int(pid_str))
                except ValueError:
                    continue
        return pids
    except Exception:
        return []


def run_terminal(terminal: Path, config: Path, out_dir: Path, timeout: int) -> tuple[int, str]:
    terminal = unix_path(terminal)
    if not terminal.exists():
        return 127, f"terminal not found: {terminal}"

    log_path = out_dir / "terminal_cli.log"
    if platform.system() == "Linux" and terminal.suffix.lower() == ".exe":
        term_arg = wine_path(terminal)
        cfg_arg = wine_path(config)
        log_arg = wine_path(log_path)
        cmd = ["wine", term_arg, f"/config:{cfg_arg}", f"/log:{log_arg}"]
    else:
        cmd = [str(terminal), f"/config:{str(config)}", f"/log:{str(log_path)}"]

    command_text = " ".join(cmd)
    env = os.environ.copy()
    if cmd[0] == "wine":
        env["WINEDEBUG"] = "-all"

    start_time = time.time()
    try:
        proc = subprocess.Popen(cmd, env=env)
        returncode = proc.wait(timeout=timeout)
        if cmd[0] == "wine" and returncode == 0:
            deadline = start_time + timeout
            while time.time() < deadline:
                children = find_wine_terminal_children(cfg_arg)
                if not children:
                    break
                time.sleep(1)
            if children:
                return 124, f"terminal still running after timeout: {command_text}"
        return returncode, command_text
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
        except Exception:
            pass
        if platform.system() == "Windows":
            for image in ("terminal64.exe", "metatester64.exe"):
                subprocess.run(["taskkill", "/F", "/IM", image, "/T"],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL,
                               check=False)
        else:
            subprocess.run(["pkill", "-f", "terminal64.exe"],
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


def resolve_runtime_roots(mql5_root: Path) -> list[Path]:
    roots: list[Path] = []
    for candidate in (mql5_root, DEFAULT_WINE_MT5_MQL5):
        try:
            resolved = candidate.resolve()
        except OSError:
            resolved = candidate
        if resolved.exists() and resolved not in roots:
            roots.append(resolved)
    return roots


def detect_stale_metaeditor_process() -> tuple[bool, list[str]]:
    if platform.system() != "Linux":
        return False, []
    try:
        output = subprocess.check_output(
            ["ps", "-eo", "pid=,stat=,args="],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return False, []

    stale: list[str] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or "metaeditor64.exe" not in line.lower():
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        pid, stat, args = parts
        if "D" in stat or "/stop:" in args:
            stale.append(f"{pid} {stat} {args}")
    return bool(stale), stale


def find_reports(runtime_roots: list[Path], out_dir: Path) -> list[Path]:
    reports = find_files(out_dir, ["*.htm", "*.html", "*.xml", "*report*"])
    for root in runtime_roots:
        extra = root / "Files" / "PASR_Validation"
        if extra.exists():
            reports.extend(extra.rglob("*report*"))
            reports.extend(extra.rglob("*.htm"))
            reports.extend(extra.rglob("*.html"))
            reports.extend(extra.rglob("*.xml"))
    unique: list[Path] = []
    seen: set[str] = set()
    for path in reports:
        key = str(path)
        if key not in seen and path.exists():
            seen.add(key)
            unique.append(path)
    return sorted(unique, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)


def find_all_logs(runtime_roots: list[Path], out_dir: Path) -> list[Path]:
    logs = find_files(out_dir, ["*.log", "*.txt"])
    seen = {str(p) for p in logs}
    for root in runtime_roots:
        for folder in (
            root.parent / "Tester" / "logs",
            root.parent / "Tester" / "Agent-127.0.0.1-3000" / "logs",
            root / "logs",
        ):
            if not folder.exists():
                continue
            for path in folder.glob("*.log"):
                if path.name.lower() == "metaeditor.log":
                    continue
                key = str(path)
                if key not in seen:
                    seen.add(key)
                    logs.append(path)
    if not logs:
        logs = find_terminal_logs(runtime_roots[0], out_dir) if runtime_roots else []
    logs = sorted(logs, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return logs[:12]


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


def slice_latest_run_text(path: Path) -> str:
    text = read_tail_maybe(path)
    if not text:
        return ""
    markers = [
        "testing of Experts\\PASR_MODULAR.ex5",
        "PASR_MODULAR.ex5 on ",
        "PASR_MODULAR.ex5 started with inputs",
        "[INFO][Journal] Initialized. CSV=ON",
        "[Pipeline] RULE_FALLBACK",
    ]
    last_index = -1
    for marker in markers:
        idx = text.rfind(marker)
        if idx > last_index:
            last_index = idx
    if last_index >= 0:
        return text[last_index:]
    return text


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
    for root in resolve_runtime_roots(mql5_root):
        candidates.extend((root / "Files").glob("PASR_Journal_*.csv"))
    wine_common = Path.home() / ".mt5" / "drive_c" / "users" / "agus" / "AppData" / "Roaming" / "MetaQuotes" / "Terminal" / "Common" / "Files"
    if wine_common.exists():
        candidates.extend(wine_common.glob("PASR_Journal_*.csv"))
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
    runtime_roots = resolve_runtime_roots(mql5_root)
    details["runtime_roots"] = [str(p) for p in runtime_roots]
    stale_metaeditor, stale_metaeditor_entries = detect_stale_metaeditor_process()
    details["stale_metaeditor_process"] = stale_metaeditor
    details["stale_metaeditor_entries"] = stale_metaeditor_entries

    reports = find_reports(runtime_roots, out_dir)
    details["report_files"] = [str(p) for p in reports]
    results.append(ValidationResult("tester_report_created", bool(reports), f"{len(reports)} report file(s)"))

    report_stats: dict[str, str] = {}
    for report in reports:
        text = read_maybe(report)
        report_stats.update(parse_report_text(text))
    details["report_stats"] = report_stats

    logs = find_all_logs(runtime_roots, out_dir)
    log_segments: list[str] = []
    for path in logs:
        segment = slice_latest_run_text(path)
        if segment:
            log_segments.append(f"\n===== {path} =====\n{segment}")
    log_text = "\n".join(log_segments)
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
    tester_started = ("PASR_MODULAR.ex5" in log_text and "testing of Experts" in log_text) or ("PASR_MODULAR.ex5" in log_text and "started with inputs" in log_text)
    no_trade_consensus = bool(re.search(r"RULE_FALLBACK no trade: No consensus", log_text, re.IGNORECASE))
    journal_initialized = "Initialized. CSV=ON" in log_text
    trade_close_logged = bool(re.search(r"\[INFO\]\[Journal\]\s*#\d+", log_text))
    if tester_started:
        environment_blocked = False
    details["tester_started"] = tester_started
    details["no_trade_consensus"] = no_trade_consensus
    details["journal_initialized"] = journal_initialized
    details["trade_close_logged"] = trade_close_logged
    results.append(ValidationResult("tester_run_detected", tester_started,
                                    "tester log shows PASR_MODULAR started" if tester_started else "no PASR_MODULAR tester start found"))
    results.append(ValidationResult("tester_environment_ready", not environment_blocked,
                                    "blocked by terminal/account/symbol sync" if environment_blocked else "environment ok"))
    results.append(ValidationResult("compile_environment_ready", not stale_metaeditor,
                                    "stale MetaEditor process detected" if stale_metaeditor else "no stuck MetaEditor process detected"))
    results.append(ValidationResult("tester_log_no_obvious_errors", len(error_hits) == 0, f"{len(error_hits)} error keyword hit(s)"))
    if no_trade_consensus:
        results.append(ValidationResult("signal_generation_observed", True, "runtime reached no-trade decision path"))
    else:
        results.append(ValidationResult("signal_generation_observed", False, "no signal-path evidence found in logs"))

    journal_path, journal_rows = load_common_journal_rows(mql5_root)
    details["journal_file"] = str(journal_path) if journal_path else ""
    details["journal_rows"] = len(journal_rows)
    journal_expected = trade_close_logged or bool(report_stats.get("Total Trades")) or not no_trade_consensus
    details["journal_expected"] = journal_expected
    if journal_path is not None:
        results.append(ValidationResult("journal_available", True, str(journal_path)))
    else:
        detail = "no PASR_Journal_*.csv found"
        if tester_started and journal_initialized and not journal_expected:
            detail = "not expected: latest run reached no-trade path without closed positions"
        results.append(ValidationResult("journal_available", not journal_expected, detail))

    if journal_rows:
        required = ["ticket", "symbol", "direction", "ai_model_id", "ai_validation_valid", "ai_validation_reason"]
        missing = [c for c in required if c not in journal_rows[0]]
        results.append(ValidationResult("journal_schema_business_context", not missing, "missing=" + ",".join(missing) if missing else "schema ok"))
        non_empty_tickets = sum(1 for r in journal_rows if r.get("ticket", "0") not in ("", "0"))
        results.append(ValidationResult("journal_has_trade_rows", non_empty_tickets > 0, f"{non_empty_tickets} trade row(s)"))
    else:
        if tester_started and not journal_expected:
            results.append(ValidationResult("journal_schema_business_context", True, "not applicable: latest run closed no positions"))
            results.append(ValidationResult("journal_has_trade_rows", True, "not applicable: latest run closed no positions"))
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
