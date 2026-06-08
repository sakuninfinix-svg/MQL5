#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
import time
import shutil
from pathlib import Path


DEFAULT_WINEPREFIX = Path("/home/agus/.mt5")
DEFAULT_EDITOR = DEFAULT_WINEPREFIX / "drive_c/Program Files/MetaTrader 5/MetaEditor64.exe"
DEFAULT_SOURCE = DEFAULT_WINEPREFIX / "drive_c/Program Files/MetaTrader 5/MQL5/Experts/PASR_MODULAR.mq5"
DEFAULT_HELPER = Path("/home/agus/.vscode/extensions/l-i-v.mql-tools-2.2.0/files/MQL Tools_Compiler.exe")
DEFAULT_LOG = DEFAULT_WINEPREFIX / "drive_c/Program Files/MetaTrader 5/logs/metaeditor.log"


def read_metaeditor_log(path: Path) -> str:
    raw = path.read_bytes()
    return raw.decode("utf-16le", errors="ignore")


def find_last_compile_line(log_text: str, source_name: str) -> str | None:
    lines = [line for line in log_text.splitlines() if source_name in line and "\tCompile\t" in line]
    return lines[-1] if lines else None


def build_command(helper: Path, editor: Path, source: Path) -> list[str]:
    def wine_path(path: Path) -> str:
        if shutil.which("winepath") is None:
            return str(path)
        try:
            output = subprocess.check_output(["winepath", "-w", str(path)], stderr=subprocess.DEVNULL, text=True)
            return output.strip()
        except Exception:
            return str(path)

    return [
        "wine",
        str(helper),
        wine_path(editor),
        "",
        wine_path(source),
        "0",
        "1500",
        "0",
    ]


def compile_source(args: argparse.Namespace) -> int:
    log_path = Path(args.log)
    helper = Path(args.helper)
    editor = Path(args.editor)
    source = Path(args.source)
    wineprefix = Path(args.wineprefix)

    if not helper.exists():
        print(f"helper not found: {helper}", file=sys.stderr)
        return 2
    if not editor.exists():
        print(f"editor not found: {editor}", file=sys.stderr)
        return 2
    if not source.exists():
        print(f"source not found: {source}", file=sys.stderr)
        return 2
    if not log_path.exists():
        print(f"log not found: {log_path}", file=sys.stderr)
        return 2

    before_text = read_metaeditor_log(log_path)
    before_line = find_last_compile_line(before_text, source.name)
    before_mtime = log_path.stat().st_mtime

    env = dict(**subprocess.os.environ, WINEPREFIX=str(wineprefix))
    subprocess.run(["wineserver", "-k"], env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)

    cmd = build_command(helper, editor, source)
    proc = subprocess.Popen(
        cmd,
        cwd=str(helper.parent),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + args.timeout
    latest_line = before_line
    changed = False

    while time.time() < deadline:
        time.sleep(0.5)
        if log_path.exists():
            mtime = log_path.stat().st_mtime
            if mtime > before_mtime:
                text = read_metaeditor_log(log_path)
                latest_line = find_last_compile_line(text, source.name)
                changed = latest_line != before_line
                if changed:
                    break
        if proc.poll() is not None and not changed:
            # Give MetaEditor a short grace period to flush its log.
            time.sleep(1.0)

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

    # MetaEditor may remain open even after the helper exits.
    subprocess.run(["wineserver", "-k"], env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    print("command:", " ".join(cmd))

    if changed and latest_line:
        print("compile:", latest_line)
        return 0 if "\tCompile\t" in latest_line and " - 0 errors" in latest_line else 1

    if latest_line:
        print("last_known_compile:", latest_line)
    else:
        print("no compile line found for source")
    print("compile log did not update within timeout", file=sys.stderr)
    return 3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compile an MT5 source through the MQL Tools Wine helper.")
    parser.add_argument("--wineprefix", default=str(DEFAULT_WINEPREFIX))
    parser.add_argument("--editor", default=str(DEFAULT_EDITOR))
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument("--helper", default=str(DEFAULT_HELPER))
    parser.add_argument("--log", default=str(DEFAULT_LOG))
    parser.add_argument("--timeout", type=int, default=45)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(compile_source(parse_args()))
