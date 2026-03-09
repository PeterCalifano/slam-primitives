#!/usr/bin/env bash
set -euo pipefail

#
# @file open_nvidia_profile.sh
# @authors Pietro Califano (petercalifano.gs@gmail.com)
# @brief Convenience launcher: find and open the latest NVIDIA profile output.
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano. All rights reserved.
#
# Supported file formats (searched in order of preference):
#   *.nsys-rep, *.qdrep  --> nsys-ui   (Nsight Systems)
#   *.ncu-rep             --> ncu-ui    (Nsight Compute)
#   *.nvvp                --> nvvp      (NVIDIA Visual Profiler, legacy)
#
# Usage:
#   ./open_nvidia_profile.sh [dir]          Find and open latest profile file in dir
#   ./open_nvidia_profile.sh [dir] [file]   Open a specific file
#

SEARCH_DIR="${1:-prof_results}"
EXPLICIT_FILE="${2:-}"

die()  { echo -e "\033[0;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[34m[INFO]\033[0m $*"; }

# Determine the tool format from a file's extension.
# Outputs one of: nsys | ncu | nvvp | (empty)
function fmt_for_file() {
    case "$1" in
        *.nsys-rep|*.qdrep) echo "nsys" ;;
        *.ncu-rep)          echo "ncu"  ;;
        *.nvvp)             echo "nvvp" ;;
        *)                  echo ""     ;;
    esac
}

# Find the viewer executable for a given format.
# Checks PATH first, then common NVIDIA install prefixes under /opt/nvidia.
function find_viewer() {
    local fmt="$1"
    local candidates=()
    case "$fmt" in
        nsys)  candidates=("nsys-ui" "nsight-sys") ;;
        ncu)   candidates=("ncu-ui" "nsight-compute") ;;
        nvvp)  candidates=("nvvp") ;;
        *)     return ;;
    esac

    # Check PATH
    for cmd in "${candidates[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 && { echo "$cmd"; return; }
    done

    # Search common NVIDIA install directories
    for cmd in "${candidates[@]}"; do
        local found
        found=$(find /opt/nvidia /usr/local/cuda* /opt/cuda 2>/dev/null \
            -name "$cmd" -type f -executable \
            | sort -V | tail -1) || true
        [[ -n "$found" ]] && { echo "$found"; return; }
    done

    echo ""
}

# Open a profile file with the appropriate viewer (launched in background).
function open_file() {
    local file="$1"
    local fmt
    fmt="$(fmt_for_file "$file")"

    if [[ -z "$fmt" ]]; then
        local ext="${file##*.}"
        die "Unrecognized profile format: .${ext}  (supported: .nsys-rep, .qdrep, .ncu-rep, .nvvp)"
    fi

    local viewer
    viewer="$(find_viewer "$fmt")"

    if [[ -z "$viewer" ]]; then
        case "$fmt" in
            nsys) die "No Nsight Systems viewer found (tried: nsys-ui, nsight-sys).
       Install: https://developer.nvidia.com/nsight-systems" ;;
            ncu)  die "No Nsight Compute viewer found (tried: ncu-ui, nsight-compute).
       Install: https://developer.nvidia.com/nsight-compute" ;;
            nvvp) die "nvvp not found.
       Install CUDA Toolkit: https://developer.nvidia.com/cuda-downloads
       Note: nvvp is deprecated in CUDA 12+; use nsys-ui instead." ;;
        esac
    fi

    info "Opening: $file"
    info "Viewer:  $viewer"
    "$viewer" "$file" &
}

# --- Handle explicit file path ---
if [[ -n "$EXPLICIT_FILE" ]]; then
    [[ -f "$EXPLICIT_FILE" ]] || die "File not found: $EXPLICIT_FILE"
    open_file "$EXPLICIT_FILE"
    exit 0
fi

# --- Auto-detect: search directory for latest profile, prefer nsys > ncu > nvvp ---
[[ -d "$SEARCH_DIR" ]] || die "Directory not found: $SEARCH_DIR"

TARGET_FILE=""
for pattern in "*.nsys-rep" "*.qdrep" "*.ncu-rep" "*.nvvp"; do
    FILE=$(find "$SEARCH_DIR" -name "$pattern" -type f | sort -V | tail -1) || true
    if [[ -n "$FILE" ]]; then
        TARGET_FILE="$FILE"
        break
    fi
done

if [[ -z "$TARGET_FILE" ]]; then
    die "No NVIDIA profile files found in '$SEARCH_DIR'.
     Run run_gpu_profiling.sh first to generate a profile."
fi

open_file "$TARGET_FILE"
