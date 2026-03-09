#!/usr/bin/env bash
set -euo pipefail

#
# @file run_ops_profiling.sh
# @authors Davide Perico (davide.perico@polimi.it), Pietro Califano (petercalifano.gs@gmail.com)
# @brief Script to run CPU operations profiling via perf record/report
# @date 2023-03-30
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano . All rights reserved .
#

# Source common parser
source "$(dirname "$0")/common_parser.sh"

function usage() {
    usage_parser
    echo "C++ Operations Profiling Tool"
    echo ""
    echo "Runs perf record on the target executable and generates"
    echo "reports via perf report."
}

# Parse script-specific arguments
function parse_specific_args() {
    parse_common_args "$@"
    set -- "${_remaining_args[@]}"

    while [[ $# -gt 0 ]]; do
        case $1 in
            *)
                echo -e "\033[38;5;208mParsing failure: not a valid option: $1\033[0m" >&2
                usage
                exit 1
                ;;
        esac
    done
}

### Parse and validate arguments
parse_specific_args "$@"
validate_common_args
create_target_folder
build_execution_command

echo -e "\033[1;34m[INFO] Starting C++ operations profiling tool...\033[0m"

# Print information about the profiling run
echo -e "\033[1;36m[INFO] Profiling Configuration:\033[0m"
echo -e "\033[1;36m[INFO] - Target folder: '$OUTPUT_FOLDER'\033[0m"
echo -e "\033[1;36m[INFO] - Number of trials: $TRIALS_NUM\033[0m"
echo -e "\033[1;36m[INFO] - Starting index: $CURRENT_INDEX\033[0m"
echo -e "\033[1;36m[INFO] - Execution command: '${EXEC_CMD_ARRAY[*]}'\033[0m"

# Run the profiling tool
for ((j=CURRENT_INDEX; j<CURRENT_INDEX+TRIALS_NUM; j++)); do
    echo -e "\033[1;33m[INFO] Running profiling iteration $((j-CURRENT_INDEX+1)) of $TRIALS_NUM...\033[0m"

    PERF_DATA="$OUTPUT_FOLDER/perf.data.$j"

    "${_sudo[@]}" perf record \
            -o "$PERF_DATA" \
            -g -e cpu-cycles,cpu-clock,instructions \
            "${EXEC_CMD_ARRAY[@]}"

    echo -e "\033[1;32m[INFO] Generating perf report for iteration $((j-CURRENT_INDEX+1))...\033[0m"
    "${_sudo[@]}" perf report -i "$PERF_DATA" --stdio > "$OUTPUT_FOLDER/perf_report.$j.txt"
done

echo -e "\033[1;34m[INFO] C++ operations profiling tool completed.\033[0m"
