#!/usr/bin/env bash
set -euo pipefail

#
# @file open_kcachegrind.sh
# @authors Pietro Califano (petercalifano.gs@gmail.com)
# @brief Convenience launcher: find and open the latest callgrind output with KCachegrind.
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano. All rights reserved.
#
# Supported input files (searched in ORDER):
#   callgrind.out.*           (from run_call_profiling.sh)
#   gperf_cpu_callgrind.*.out (from run_gperf_profiling.sh --mode cpu)
#   gperf_heap_callgrind.*.out(from run_gperf_profiling.sh --mode heap)
#

SEARCH_DIR="${1:-prof_results}"
EXPLICIT_FILE="${2:-}"

die()  { echo -e "\033[0;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[34m[INFO]\033[0m $*"; }

if ! command -v kcachegrind >/dev/null 2>&1; then
    die "kcachegrind not found. Install with: sudo apt install kcachegrind"
fi

if [[ -n "$EXPLICIT_FILE" ]]; then
    [[ -f "$EXPLICIT_FILE" ]] || die "File not found: $EXPLICIT_FILE"
    info "Opening: $EXPLICIT_FILE"
    kcachegrind "$EXPLICIT_FILE"
    exit 0
fi

[[ -d "$SEARCH_DIR" ]] || die "Directory not found: $SEARCH_DIR"

# Find the most recently modified callgrind-compatible file
TARGET_FILE=$(find "$SEARCH_DIR" \
    \( -name "callgrind.out.*" \
    -o -name "gperf_cpu_callgrind.*.out" \
    -o -name "gperf_heap_callgrind.*.out" \) \
    -type f \
    | sort -t'.' -k2 -V \
    | tail -1)

if [[ -z "$TARGET_FILE" ]]; then
    die "No callgrind output files found in '$SEARCH_DIR'."
fi

info "Opening: $TARGET_FILE"
kcachegrind "$TARGET_FILE"
