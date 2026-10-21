#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
openlane_bin="${OPENLANE_BIN:-openlane}"
run_dir="${1:-$root_dir/build/openlane}"

if ! command -v "$openlane_bin" >/dev/null 2>&1; then
  echo "OpenLane 2 is not installed; install it and Sky130 before running PPA." >&2
  exit 2
fi

mkdir -p "$run_dir"
echo "Running baseline OpenLane flow..."
"$openlane_bin" "$root_dir/openlane/config-baseline.json" -o "$run_dir/baseline"
echo "Running optimized OpenLane flow..."
"$openlane_bin" "$root_dir/openlane/config.json" -o "$run_dir/optimized"
echo "Runs complete. Compare the generated metrics.json files with:"
echo "  python3 $root_dir/scripts/compare_openlane_metrics.py \\\n+    $run_dir/baseline/metrics.json $run_dir/optimized/metrics.json"

