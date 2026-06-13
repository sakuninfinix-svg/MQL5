#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MT5_PREFIX="${MQL5_WINEPREFIX:-/home/agus/.mt5}"
METAEDITOR_EXE="$MT5_PREFIX/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe"
WIN_WORKSPACE_ROOT='C:\Program Files\MetaTrader 5\MQL5'

usage() {
   echo "Usage: $0 <path-to-mq5>" >&2
}

to_abs_path() {
   local path="$1"
   if [[ "$path" = /* ]]; then
      printf '%s\n' "$path"
   else
      printf '%s/%s\n' "$WORKSPACE_ROOT" "$path"
   fi
}

to_win_path() {
   local path="$1"
   if [[ "$path" == "$WORKSPACE_ROOT" ]]; then
      printf '%s\n' "$WIN_WORKSPACE_ROOT"
      return 0
   fi

   if [[ "$path" == "$WORKSPACE_ROOT/"* ]]; then
      local rel="${path#"$WORKSPACE_ROOT/"}"
      rel="${rel//\//\\}"
      printf '%s\\%s\n' "$WIN_WORKSPACE_ROOT" "$rel"
      return 0
   fi

   return 1
}

decode_log() {
   local log_file="$1"
   if command -v iconv >/dev/null 2>&1; then
      iconv -f UTF-16LE -t UTF-8 "$log_file" 2>/dev/null || cat "$log_file"
   else
      cat "$log_file"
   fi
}

if [[ $# -lt 1 ]]; then
   usage
   exit 2
fi

SOURCE_FILE="$(to_abs_path "$1")"
SOURCE_BASENAME="$(basename "$SOURCE_FILE")"

if [[ ! -f "$SOURCE_FILE" ]]; then
   echo "Source file not found: $SOURCE_FILE" >&2
   exit 1
fi

if [[ ! -f "$METAEDITOR_EXE" ]]; then
   echo "MetaEditor not found: $METAEDITOR_EXE" >&2
   exit 1
fi

if ! WIN_SOURCE_FILE="$(to_win_path "$SOURCE_FILE")"; then
   echo "Source file is outside the MQL5 workspace root: $SOURCE_FILE" >&2
   exit 1
fi

METAEDITOR_LOG="$MT5_PREFIX/drive_c/Program Files/MetaTrader 5/logs/metaeditor.log"
MARKER_FILE="$(mktemp "${TMPDIR:-/tmp}/mql_compile.XXXXXX")"
trap 'rm -f "$MARKER_FILE"' EXIT
touch "$MARKER_FILE"

echo "[INFO] Compiling: $SOURCE_FILE"
echo "[INFO] Using MetaEditor: $METAEDITOR_EXE"
echo "[INFO] Windows source path: $WIN_SOURCE_FILE"

WINEPREFIX="$MT5_PREFIX" WINEDEBUG=-all wine "$METAEDITOR_EXE" "/compile:$WIN_SOURCE_FILE" >/dev/null 2>&1 || true

for _ in $(seq 1 90); do
   if [[ -f "$METAEDITOR_LOG" && "$METAEDITOR_LOG" -nt "$MARKER_FILE" ]]; then
      break
   fi
   sleep 1
done

if [[ -f "$METAEDITOR_LOG" && "$METAEDITOR_LOG" -nt "$MARKER_FILE" ]]; then
   META_LOG_TEXT="$(decode_log "$METAEDITOR_LOG")"
   RESULT_LINE="$(printf '%s\n' "$META_LOG_TEXT" | grep -F "$SOURCE_BASENAME" | grep -F "Compile" | tail -1)"
   if [[ -n "$RESULT_LINE" ]]; then
      echo "[INFO] MetaEditor result: $RESULT_LINE"
      if printf '%s\n' "$RESULT_LINE" | grep -Eq '[1-9][0-9]* errors'; then
         exit 1
      fi
      exit 0
   fi
fi
echo "[ERROR] Compile result not found in MetaEditor log for: $SOURCE_FILE" >&2
if [[ -f "$METAEDITOR_LOG" ]]; then
   echo "[INFO] Recent MetaEditor log tail:" >&2
   decode_log "$METAEDITOR_LOG" | tail -20 >&2
fi
exit 49
