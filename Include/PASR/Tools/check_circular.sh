#!/bin/bash
# Relocated from Include/PASR/check_circular.sh → Tools/check_circular.sh
# Phase 4 cleanup - shell scripts belong in Tools/

echo "Checking for circular #include dependencies in PASR..."

FIND_DIR="${1:-Include/PASR}"

grep -r "#include" "$FIND_DIR" --include="*.mqh" -h \
  | sed 's/.*<\(.*\)>/\1/' \
  | sed 's/.*"\(.*\)"/\1/' \
  | sort | uniq -d \
  | while read dep; do
      echo "  Possible circular: $dep"
    done

echo "Done."
