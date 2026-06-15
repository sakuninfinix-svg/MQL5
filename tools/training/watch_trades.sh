#!/usr/bin/env bash
# ============================================================================
# PASR Auto-Retrain Cron Wrapper
# ============================================================================
# Runs auto_retrain.py every 5 minutes via cron.
#
# Setup:
#   chmod +x training/watch_trades.sh
#   crontab -e
#   # Add this line:
#   */5 * * * * /home/agus/.mt5/drive_c/Program Files/MetaTrader 5/.../tools/training/watch_trades.sh
#
# Or test manually:
#   bash training/watch_trades.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCKFILE="/tmp/pasr_auto_retrain.lock"
PYTHON="${PYTHON:-python3}"
MIN_TRADES="${MIN_TRADES:-200}"

# Prevent concurrent runs
if [ -f "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
    rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Run auto-retrain
cd "$SCRIPT_DIR/.."
"$PYTHON" "$SCRIPT_DIR/auto_retrain.py" --min-trades "$MIN_TRADES" 2>&1
