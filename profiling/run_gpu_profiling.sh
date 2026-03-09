#!/usr/bin/env bash
set -euo pipefail

#
# @file run_gpu_profiling.sh
# @authors Pietro Califano (petercalifano.gs@gmail.com)
# @brief NVIDIA GPU profiling via Nsight Systems (nsys), Nsight Compute (ncu), or nvprof.
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano. All rights reserved.
#
# Tool selection (auto-detected or forced via --mode):
#   nsys   - Nsight Systems: system-level CPU+GPU timeline, API traces, memory transfers.
#             Output: .nsys-rep  --> open with: nsys-ui / open_nvidia_profile.sh
#   ncu    - Nsight Compute: per-kernel metrics (occupancy, memory BW, warp efficiency).
#             Output: .ncu-rep   --> open with: ncu-ui / open_nvidia_profile.sh
#   nvprof - Legacy profiler (deprecated in CUDA 12+, kept for backwards compatibility).
#             Output: .nvvp      --> open with: nvvp
#
# Install Nsight tools: https://developer.nvidia.com/nsight-systems
#                       https://developer.nvidia.com/nsight-compute
#

# Source common parser
source "$(dirname "$0")/common_parser.sh"

# Script-specific defaults
GPU_PROFILING_MODE="auto"          # auto | nsys | ncu | nvprof
AUTO_OPEN=false

# Nsight Systems (nsys) options
NSYS_TRACE="cuda,osrt,nvtx"        # APIs to trace
NSYS_SAMPLE="process-tree"         # CPU sampling: process-tree | none | lbr
NSYS_DELAY=0                       # Delay before start in seconds (0 = no delay)
NSYS_DURATION=0                    # Profile duration in seconds (0 = unlimited)
NSYS_CAPTURE_RANGE="none"          # none | cudaProfilerApi | nvtx

# Nsight Compute (ncu) options
NCU_SET="full"                     # Metric set: full | basic | source
NCU_KERNEL=""                      # Kernel name regex filter (empty = all kernels)
NCU_LAUNCH_COUNT=0                 # Launches to profile per kernel (0 = all)
NCU_LAUNCH_SKIP=0                  # Launches to skip before profiling (0 = none)
NCU_TARGET_PROCESSES="application-only"  # application-only | all

# nvprof (legacy) options
NVPROF_METRICS=""                  # Comma-separated additional metrics (empty = defaults)

function usage() {
    usage_parser
    echo "CUDA GPU Profiling Tool"
    echo ""
    echo "Profiles CUDA executables using NVIDIA Nsight Systems, Nsight Compute, or nvprof."
    echo "Tool is auto-detected (nsys > ncu > nvprof) unless --mode is specified."
    echo ""
    echo "Script-specific options:"
    echo "  --mode <mode>                  Tool: auto, nsys, ncu, nvprof (default: auto)"
    echo "  --open                         Open result in viewer after profiling"
    echo ""
    echo "Nsight Systems (nsys) options:"
    echo "  --nsys-trace <apis>            APIs to trace (default: cuda,osrt,nvtx)"
    echo "                                 Common extras: cudnn, cublas, opengl, mpi, onnxruntime"
    echo "  --nsys-sample <method>         CPU sampling: process-tree, none, lbr (default: process-tree)"
    echo "  --nsys-delay <secs>            Delay before profiling starts (integer secs, default: 0)"
    echo "  --nsys-duration <secs>         Profile duration in secs (integer, default: 0=unlimited)"
    echo "  --nsys-capture-range <range>   Capture range: none, cudaProfilerApi, nvtx (default: none)"
    echo "                                 cudaProfilerApi: profile only between cudaProfilerStart/Stop"
    echo ""
    echo "Nsight Compute (ncu) options:"
    echo "  --ncu-set <set>                Metric set: full, basic, source (default: full)"
    echo "  --ncu-kernel <regex>           Kernel name filter regex (default: all kernels)"
    echo "  --ncu-launch-count <N>         Launches to profile per kernel (default: 0=all)"
    echo "  --ncu-launch-skip <N>          Launches to skip before profiling (default: 0)"
    echo "  --ncu-target-processes <mode>  Process scope: application-only, all (default: application-only)"
    echo ""
    echo "nvprof (legacy) options:"
    echo "  --nvprof-metrics <list>        Comma-separated extra metrics (default: standard set)"
    echo ""
    echo "Output files (per trial index N):"
    echo "  nsys:   nsys_profile.N.nsys-rep   --> open with: nsys-ui / open_nvidia_profile.sh"
    echo "          nsys_report.N.txt          (text stats)"
    echo "  ncu:    ncu_profile.N.ncu-rep      --> open with: ncu-ui / open_nvidia_profile.sh"
    echo "          ncu_report.N.txt            (text metrics)"
    echo "  nvprof: nvprof_profile.N.nvvp      --> open with: nvvp"
    echo "          nvprof_report.N.txt         (text summary)"
    echo ""
}

function parse_specific_args() {
    parse_common_args "$@"
    set -- "${_remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --mode requires an argument (auto|nsys|ncu|nvprof).\033[0m" >&2; exit 1; }
                GPU_PROFILING_MODE="$2"; shift 2 ;;
            --open)
                AUTO_OPEN=true; shift ;;

            # nsys options
            --nsys-trace)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nsys-trace requires an argument.\033[0m" >&2; exit 1; }
                NSYS_TRACE="$2"; shift 2 ;;
            --nsys-sample)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nsys-sample requires an argument.\033[0m" >&2; exit 1; }
                NSYS_SAMPLE="$2"; shift 2 ;;
            --nsys-delay)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nsys-delay requires an integer argument.\033[0m" >&2; exit 1; }
                NSYS_DELAY="$2"; shift 2 ;;
            --nsys-duration)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nsys-duration requires an integer argument.\033[0m" >&2; exit 1; }
                NSYS_DURATION="$2"; shift 2 ;;
            --nsys-capture-range)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nsys-capture-range requires an argument.\033[0m" >&2; exit 1; }
                NSYS_CAPTURE_RANGE="$2"; shift 2 ;;

            # ncu options
            --ncu-set)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --ncu-set requires an argument (full|basic|source).\033[0m" >&2; exit 1; }
                NCU_SET="$2"; shift 2 ;;
            --ncu-kernel)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --ncu-kernel requires a regex argument.\033[0m" >&2; exit 1; }
                NCU_KERNEL="$2"; shift 2 ;;
            --ncu-launch-count)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --ncu-launch-count requires an integer argument.\033[0m" >&2; exit 1; }
                NCU_LAUNCH_COUNT="$2"; shift 2 ;;
            --ncu-launch-skip)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --ncu-launch-skip requires an integer argument.\033[0m" >&2; exit 1; }
                NCU_LAUNCH_SKIP="$2"; shift 2 ;;
            --ncu-target-processes)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --ncu-target-processes requires an argument.\033[0m" >&2; exit 1; }
                NCU_TARGET_PROCESSES="$2"; shift 2 ;;

            # nvprof options
            --nvprof-metrics)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --nvprof-metrics requires an argument.\033[0m" >&2; exit 1; }
                NVPROF_METRICS="$2"; shift 2 ;;

            *)
                echo -e "\033[38;5;208mParsing failure: not a valid option: $1\033[0m" >&2
                usage
                exit 1 ;;
        esac
    done
}

# Detect the best available GPU profiling tool
function detect_gpu_tool() {
    local mode="$1"
    case "$mode" in
        auto)
            if   command -v nsys   >/dev/null 2>&1; then echo "nsys"
            elif command -v ncu    >/dev/null 2>&1; then echo "ncu"
            elif command -v nvprof >/dev/null 2>&1; then echo "nvprof"
            else echo ""
            fi
            ;;
        nsys|ncu|nvprof)
            command -v "$mode" >/dev/null 2>&1 && echo "$mode" || echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

### Parse and validate arguments
parse_specific_args "$@"
validate_common_args
create_target_folder
build_execution_command

# Validate mode value
case "$GPU_PROFILING_MODE" in
    auto|nsys|ncu|nvprof) ;;
    *) echo -e "\033[0;31mERROR: Invalid --mode '$GPU_PROFILING_MODE'. Use: auto, nsys, ncu, nvprof.\033[0m" >&2; exit 1 ;;
esac

ACTIVE_TOOL="$(detect_gpu_tool "$GPU_PROFILING_MODE")"
if [[ -z "$ACTIVE_TOOL" ]]; then
    echo -e "\033[0;31mERROR: No GPU profiling tool found for mode '${GPU_PROFILING_MODE}'.\033[0m" >&2
    echo -e "\033[0;31m       Install Nsight Systems (nsys) or Nsight Compute (ncu) from:\033[0m" >&2
    echo -e "\033[0;31m       https://developer.nvidia.com/nsight-systems\033[0m" >&2
    exit 1
fi

echo -e "\033[1;34m[INFO] Starting GPU profiling tool...\033[0m"
echo -e "\033[1;36m[INFO] Profiling Configuration:\033[0m"
echo -e "\033[1;36m[INFO] - Target folder:     '$OUTPUT_FOLDER'\033[0m"
echo -e "\033[1;36m[INFO] - Number of trials:  $TRIALS_NUM\033[0m"
echo -e "\033[1;36m[INFO] - Starting index:    $CURRENT_INDEX\033[0m"
echo -e "\033[1;36m[INFO] - Execution command: '${EXEC_CMD_ARRAY[*]}'\033[0m"
echo -e "\033[1;36m[INFO] - Active GPU tool:   $ACTIVE_TOOL\033[0m"
case "$ACTIVE_TOOL" in
    nsys)
        echo -e "\033[1;36m[INFO] - nsys trace:        $NSYS_TRACE\033[0m"
        echo -e "\033[1;36m[INFO] - nsys sample:       $NSYS_SAMPLE\033[0m"
        echo -e "\033[1;36m[INFO] - nsys capture:      $NSYS_CAPTURE_RANGE\033[0m"
        [[ "$NSYS_DELAY"    -gt 0 ]] && echo -e "\033[1;36m[INFO] - nsys delay:        ${NSYS_DELAY}s\033[0m"
        [[ "$NSYS_DURATION" -gt 0 ]] && echo -e "\033[1;36m[INFO] - nsys duration:     ${NSYS_DURATION}s\033[0m"
        ;;
    ncu)
        echo -e "\033[1;36m[INFO] - ncu metric set:    $NCU_SET\033[0m"
        echo -e "\033[1;36m[INFO] - ncu target procs:  $NCU_TARGET_PROCESSES\033[0m"
        [[ -n "$NCU_KERNEL" ]]          && echo -e "\033[1;36m[INFO] - ncu kernel filter: $NCU_KERNEL\033[0m"
        [[ "$NCU_LAUNCH_SKIP"  -gt 0 ]] && echo -e "\033[1;36m[INFO] - ncu launch skip:   $NCU_LAUNCH_SKIP\033[0m"
        [[ "$NCU_LAUNCH_COUNT" -gt 0 ]] && echo -e "\033[1;36m[INFO] - ncu launch count:  $NCU_LAUNCH_COUNT\033[0m"
        ;;
    nvprof)
        [[ -n "$NVPROF_METRICS" ]] && echo -e "\033[1;36m[INFO] - nvprof metrics:    $NVPROF_METRICS\033[0m"
        ;;
esac

for ((j=CURRENT_INDEX; j<CURRENT_INDEX+TRIALS_NUM; j++)); do
    echo -e "\033[1;33m[INFO] Running GPU profiling iteration $((j-CURRENT_INDEX+1)) of $TRIALS_NUM...\033[0m"

    case "$ACTIVE_TOOL" in
        nsys)
            OUTPUT_BASE="$OUTPUT_FOLDER/nsys_profile.$j"

            # Build nsys args array (only append optional flags when non-default)
            _nsys_args=(
                "--output=${OUTPUT_BASE}"
                "--trace=${NSYS_TRACE}"
                "--sample=${NSYS_SAMPLE}"
                "--capture-range=${NSYS_CAPTURE_RANGE}"
                "--stats=true"
                "--force-overwrite=true"
            )
            [[ "$NSYS_DELAY"    -gt 0 ]] && _nsys_args+=( "--delay=${NSYS_DELAY}" )
            [[ "$NSYS_DURATION" -gt 0 ]] && _nsys_args+=( "--duration=${NSYS_DURATION}" )

            "${_sudo[@]}" nsys profile \
                "${_nsys_args[@]}" \
                "${EXEC_CMD_ARRAY[@]}"

            echo -e "\033[1;32m[INFO] Generating nsys text report...\033[0m"
            if   [[ -f "${OUTPUT_BASE}.nsys-rep" ]]; then
                nsys stats "${OUTPUT_BASE}.nsys-rep" > "$OUTPUT_FOLDER/nsys_report.$j.txt" 2>&1 || true
            elif [[ -f "${OUTPUT_BASE}.qdrep" ]]; then
                nsys stats "${OUTPUT_BASE}.qdrep"    > "$OUTPUT_FOLDER/nsys_report.$j.txt" 2>&1 || true
            fi
            ;;

        ncu)
            OUTPUT_BASE="$OUTPUT_FOLDER/ncu_profile.$j"

            # Build ncu args array
            _ncu_args=(
                "--set"              "${NCU_SET}"
                "--target-processes" "${NCU_TARGET_PROCESSES}"
                "--output"           "${OUTPUT_BASE}"
                "--force-overwrite"
            )
            [[ -n "$NCU_KERNEL" ]]          && _ncu_args+=( "--kernel-name"  "${NCU_KERNEL}" )
            [[ "$NCU_LAUNCH_COUNT" -gt 0 ]] && _ncu_args+=( "--launch-count" "${NCU_LAUNCH_COUNT}" )
            [[ "$NCU_LAUNCH_SKIP"  -gt 0 ]] && _ncu_args+=( "--launch-skip"  "${NCU_LAUNCH_SKIP}" )

            "${_sudo[@]}" ncu \
                "${_ncu_args[@]}" \
                "${EXEC_CMD_ARRAY[@]}"

            echo -e "\033[1;32m[INFO] Generating ncu text report...\033[0m"
            ncu --import "${OUTPUT_BASE}.ncu-rep" > "$OUTPUT_FOLDER/ncu_report.$j.txt" 2>&1 || true
            ;;

        nvprof)
            _nvprof_args=(
                "--log-file"       "$OUTPUT_FOLDER/nvprof_report.$j.txt"
                "--output-profile" "$OUTPUT_FOLDER/nvprof_profile.$j.nvvp"
            )
            [[ -n "$NVPROF_METRICS" ]] && _nvprof_args+=( "--metrics" "$NVPROF_METRICS" )

            "${_sudo[@]}" nvprof \
                "${_nvprof_args[@]}" \
                "${EXEC_CMD_ARRAY[@]}"
            ;;
    esac
done

echo -e "\033[1;34m[INFO] GPU profiling completed.\033[0m"
echo -e "\033[1;36m[INFO] Results written to: $OUTPUT_FOLDER/\033[0m"
case "$ACTIVE_TOOL" in
    nsys)   echo -e "\033[1;36m[INFO] Open .nsys-rep with: $(dirname "$0")/open_nvidia_profile.sh $OUTPUT_FOLDER\033[0m" ;;
    ncu)    echo -e "\033[1;36m[INFO] Open .ncu-rep  with: $(dirname "$0")/open_nvidia_profile.sh $OUTPUT_FOLDER\033[0m" ;;
    nvprof) echo -e "\033[1;36m[INFO] Open .nvvp     with: nvvp $OUTPUT_FOLDER/nvprof_profile.${CURRENT_INDEX}.nvvp\033[0m" ;;
esac

# Auto-open viewer if requested
if [[ "$AUTO_OPEN" == true ]]; then
    OPEN_SCRIPT="$(dirname "$0")/open_nvidia_profile.sh"
    if [[ -x "$OPEN_SCRIPT" ]]; then
        echo -e "\033[1;34m[INFO] Auto-opening profile viewer...\033[0m"
        # Point directly at the first trial's output when possible
        FIRST_FILE=""
        case "$ACTIVE_TOOL" in
            nsys)
                if   [[ -f "$OUTPUT_FOLDER/nsys_profile.${CURRENT_INDEX}.nsys-rep" ]]; then
                    FIRST_FILE="$OUTPUT_FOLDER/nsys_profile.${CURRENT_INDEX}.nsys-rep"
                elif [[ -f "$OUTPUT_FOLDER/nsys_profile.${CURRENT_INDEX}.qdrep" ]]; then
                    FIRST_FILE="$OUTPUT_FOLDER/nsys_profile.${CURRENT_INDEX}.qdrep"
                fi ;;
            ncu)
                [[ -f "$OUTPUT_FOLDER/ncu_profile.${CURRENT_INDEX}.ncu-rep" ]] && \
                    FIRST_FILE="$OUTPUT_FOLDER/ncu_profile.${CURRENT_INDEX}.ncu-rep" ;;
            nvprof)
                [[ -f "$OUTPUT_FOLDER/nvprof_profile.${CURRENT_INDEX}.nvvp" ]] && \
                    FIRST_FILE="$OUTPUT_FOLDER/nvprof_profile.${CURRENT_INDEX}.nvvp" ;;
        esac

        if [[ -n "$FIRST_FILE" ]]; then
            "$OPEN_SCRIPT" "$OUTPUT_FOLDER" "$FIRST_FILE"
        else
            "$OPEN_SCRIPT" "$OUTPUT_FOLDER"
        fi
    else
        echo -e "\033[38;5;208m[WARN] open_nvidia_profile.sh not found - open the result manually.\033[0m" >&2
    fi
fi
