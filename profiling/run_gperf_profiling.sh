#!/usr/bin/env bash
set -euo pipefail

#
# @file run_gperf_profiling.sh
# @authors Pietro Califano (petercalifano.gs@gmail.com)
# @brief Non-invasive CPU and heap profiling via gperftools LD_PRELOAD.
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano. All rights reserved.
#
# Requires: libgoogle-perftools-dev  (sudo apt install libgoogle-perftools-dev)
# Optional: google-perftools         (sudo apt install google-perftools) for pprof
#
# CPU callgrind output is compatible with KCachegrind.
# Open with: kcachegrind prof_results/gperf_cpu_callgrind.1.out
#        or: ./open_kcachegrind.sh prof_results
#

# Source common parser
source "$(dirname "$0")/common_parser.sh"

# Script-specific defaults
GPERF_MODE="cpu"    # cpu | heap | both
AUTO_OPEN=false
CPU_FREQ=0          # CPUPROFILE_FREQUENCY in Hz (0 = use gperftools default of 100 Hz)

function usage() {
    usage_parser
    echo "C++ gperftools Profiling Tool"
    echo ""
    echo "Non-invasive CPU and heap profiling via LD_PRELOAD (no source changes needed)."
    echo "Generates pprof text reports and KCachegrind-compatible callgrind output."
    echo ""
    echo "Script-specific options:"
    echo "  --mode <mode>       Profiling mode: cpu, heap, both (default: cpu)"
    echo "  --open              Open result in KCachegrind after profiling (cpu/both mode)"
    echo "  --cpu-freq <hz>     CPU sampling frequency in Hz (default: 0 = gperftools default 100 Hz)"
    echo "                      Higher values give finer resolution at higher overhead."
    echo ""
    echo "Output files (per trial index N):"
    echo "  cpu:   gperf_cpu_report.N.txt          (pprof text)"
    echo "         gperf_cpu_callgrind.N.out        (KCachegrind-compatible)"
    echo "  heap:  gperf_heap_report.N.txt          (pprof text)"
    echo "         gperf_heap_callgrind.N.out        (KCachegrind-compatible)"
    echo ""
}

function parse_specific_args() {
    parse_common_args "$@"
    set -- "${_remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --mode requires an argument (cpu|heap|both).\033[0m" >&2; exit 1; }
                GPERF_MODE="$2"; shift 2 ;;
            --open)
                AUTO_OPEN=true; shift ;;
            --cpu-freq)
                [[ -n "${2:-}" ]] || { echo -e "\033[0;31mERROR: --cpu-freq requires an integer argument.\033[0m" >&2; exit 1; }
                CPU_FREQ="$2"; shift 2 ;;
            *)
                echo -e "\033[38;5;208mParsing failure: not a valid option: $1\033[0m" >&2
                usage
                exit 1 ;;
        esac
    done
}

# Find libprofiler.so at runtime (no cmake required)
function find_libprofiler() {
    # Try ldconfig first (covers non-standard install paths)
    if command -v ldconfig >/dev/null 2>&1; then
        local path
        path=$(ldconfig -p 2>/dev/null | awk '/libprofiler\.so /{print $NF}' | head -1)
        if [[ -n "$path" ]]; then echo "$path"; return; fi
    fi
    # Common Debian/Ubuntu and generic paths
    local candidates=(
        /usr/lib/x86_64-linux-gnu/libprofiler.so
        /usr/lib/aarch64-linux-gnu/libprofiler.so
        /usr/local/lib/libprofiler.so
        /usr/lib/libprofiler.so
    )
    for p in "${candidates[@]}"; do
        if [[ -f "$p" ]]; then echo "$p"; return; fi
    done
    echo ""
}

### Parse and validate arguments
parse_specific_args "$@"
validate_common_args
create_target_folder
build_execution_command

# Validate mode
case "$GPERF_MODE" in
    cpu|heap|both) ;;
    *) echo -e "\033[0;31mERROR: Invalid --mode '$GPERF_MODE'. Use: cpu, heap, both.\033[0m" >&2; exit 1 ;;
esac

LIBPROFILER="$(find_libprofiler)"
if [[ -z "$LIBPROFILER" ]]; then
    echo -e "\033[0;31mERROR: libprofiler not found.\033[0m" >&2
    echo -e "\033[0;31m       Install with: sudo apt install libgoogle-perftools-dev\033[0m" >&2
    exit 1
fi

HAVE_PPROF=false
if command -v pprof >/dev/null 2>&1; then
    HAVE_PPROF=true
else
    echo -e "\033[38;5;208m[WARN] pprof not found - raw profile files will be written but no reports generated.\033[0m" >&2
    echo -e "\033[38;5;208m       Install with: sudo apt install google-perftools\033[0m" >&2
fi

echo -e "\033[1;34m[INFO] Starting gperftools profiling (mode: ${GPERF_MODE}) via LD_PRELOAD...\033[0m"
echo -e "\033[1;36m[INFO] Profiling Configuration:\033[0m"
echo -e "\033[1;36m[INFO] - Target folder:     '$OUTPUT_FOLDER'\033[0m"
echo -e "\033[1;36m[INFO] - Number of trials:  $TRIALS_NUM\033[0m"
echo -e "\033[1;36m[INFO] - Starting index:    $CURRENT_INDEX\033[0m"
echo -e "\033[1;36m[INFO] - Execution command: '${EXEC_CMD_ARRAY[*]}'\033[0m"
echo -e "\033[1;36m[INFO] - libprofiler:       $LIBPROFILER\033[0m"
[[ "$CPU_FREQ" -gt 0 ]] && echo -e "\033[1;36m[INFO] - CPU frequency:     ${CPU_FREQ} Hz\033[0m"

for ((j=CURRENT_INDEX; j<CURRENT_INDEX+TRIALS_NUM; j++)); do
    echo -e "\033[1;33m[INFO] Running profiling iteration $((j-CURRENT_INDEX+1)) of $TRIALS_NUM...\033[0m"

    if [[ "$GPERF_MODE" == "cpu" || "$GPERF_MODE" == "both" ]]; then
        CPU_PROF="$OUTPUT_FOLDER/cpu.$j.prof"
        echo -e "\033[1;36m[INFO] CPU profiling --> $CPU_PROF\033[0m"

        # Build env for the profiler run
        _cpu_env=( CPUPROFILE="$CPU_PROF" LD_PRELOAD="$LIBPROFILER" )
        [[ "$CPU_FREQ" -gt 0 ]] && _cpu_env=( CPUPROFILE_FREQUENCY="$CPU_FREQ" "${_cpu_env[@]}" )
        env "${_cpu_env[@]}" "${EXEC_CMD_ARRAY[@]}"

        if [[ "$HAVE_PPROF" == true ]]; then
            echo -e "\033[1;32m[INFO] Generating CPU pprof text report...\033[0m"
            pprof --text     "${EXEC_CMD_ARRAY[0]}" "$CPU_PROF" \
                > "$OUTPUT_FOLDER/gperf_cpu_report.$j.txt" 2>&1 || true

            echo -e "\033[1;32m[INFO] Generating CPU callgrind report (KCachegrind-compatible)...\033[0m"
            pprof --callgrind "${EXEC_CMD_ARRAY[0]}" "$CPU_PROF" \
                > "$OUTPUT_FOLDER/gperf_cpu_callgrind.$j.out" 2>&1 || true
        fi
    fi

    if [[ "$GPERF_MODE" == "heap" || "$GPERF_MODE" == "both" ]]; then
        HEAP_BASE="$OUTPUT_FOLDER/heap.$j"
        echo -e "\033[1;36m[INFO] Heap profiling --> ${HEAP_BASE}.*.heap\033[0m"
        HEAPPROFILE="$HEAP_BASE" LD_PRELOAD="$LIBPROFILER" "${EXEC_CMD_ARRAY[@]}"

        if [[ "$HAVE_PPROF" == true ]]; then
            # pprof accepts a glob; bash expands it
            local_heap_files=( "${HEAP_BASE}."*.heap )
            if [[ ${#local_heap_files[@]} -gt 0 && -f "${local_heap_files[0]}" ]]; then
                echo -e "\033[1;32m[INFO] Generating heap pprof text report...\033[0m"
                pprof --text     "${EXEC_CMD_ARRAY[0]}" "${local_heap_files[@]}" \
                    > "$OUTPUT_FOLDER/gperf_heap_report.$j.txt" 2>&1 || true

                echo -e "\033[1;32m[INFO] Generating heap callgrind report (KCachegrind-compatible)...\033[0m"
                pprof --callgrind "${EXEC_CMD_ARRAY[0]}" "${local_heap_files[@]}" \
                    > "$OUTPUT_FOLDER/gperf_heap_callgrind.$j.out" 2>&1 || true
            else
                echo -e "\033[38;5;208m[WARN] No .heap files found - executable may have exited before heap data was flushed.\033[0m" >&2
            fi
        fi
    fi
done

echo -e "\033[1;34m[INFO] gperftools profiling completed.\033[0m"
if [[ "$HAVE_PPROF" == true ]]; then
    echo -e "\033[1;36m[INFO] Text reports:      $OUTPUT_FOLDER/gperf_*_report.*.txt\033[0m"
    echo -e "\033[1;36m[INFO] Callgrind output:  $OUTPUT_FOLDER/gperf_*_callgrind.*.out\033[0m"
    echo -e "\033[1;36m[INFO] Visualize with:    $(dirname "$0")/open_kcachegrind.sh $OUTPUT_FOLDER\033[0m"
fi

# Auto-open KCachegrind if requested and CPU profiling was done
if [[ "$AUTO_OPEN" == true ]]; then
    if [[ "$GPERF_MODE" == "heap" ]]; then
        echo -e "\033[38;5;208m[WARN] --open is only effective for cpu/both mode (KCachegrind reads CPU callgrind output).\033[0m" >&2
    elif [[ "$HAVE_PPROF" == false ]]; then
        echo -e "\033[38;5;208m[WARN] --open skipped: pprof not available, no callgrind output was generated.\033[0m" >&2
    else
        OPEN_SCRIPT="$(dirname "$0")/open_kcachegrind.sh"
        if [[ -x "$OPEN_SCRIPT" ]]; then
            echo -e "\033[1;34m[INFO] Auto-opening KCachegrind...\033[0m"
            "$OPEN_SCRIPT" "$OUTPUT_FOLDER"
        else
            echo -e "\033[38;5;208m[WARN] open_kcachegrind.sh not found - open manually:\033[0m" >&2
            echo -e "\033[38;5;208m       kcachegrind $OUTPUT_FOLDER/gperf_cpu_callgrind.${CURRENT_INDEX}.out\033[0m" >&2
        fi
    fi
fi
