#!/usr/bin/env python3
"""Print a small, tool-version-tolerant baseline vs optimized PPA report."""

from __future__ import annotations

import json
import sys
from pathlib import Path


KEYS = (
    "design__die__area",
    "design__core__area",
    "design__instance__area",
    "timing__setup__ws",
    "timing__setup__tns",
    "power__total",
    "power__internal",
    "power__switching",
    "power__leakage",
)


def load(path: str) -> dict:
    with Path(path).open() as handle:
        data = json.load(handle)
    return data.get("metrics", data)


def fmt(value: object) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.6g}"
    return str(value)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {Path(sys.argv[0]).name} BASELINE_METRICS OPTIMIZED_METRICS", file=sys.stderr)
        return 2

    baseline = load(sys.argv[1])
    optimized = load(sys.argv[2])
    print("metric | baseline | optimized | delta (optimized - baseline)")
    print("--- | ---: | ---: | ---:")
    for key in KEYS:
        left = baseline.get(key)
        right = optimized.get(key)
        if isinstance(left, (int, float)) and isinstance(right, (int, float)):
            delta = right - left
            delta_text = fmt(delta)
        else:
            delta_text = "-"
        print(f"{key} | {fmt(left)} | {fmt(right)} | {delta_text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

