#!/usr/bin/env bash
set -euo pipefail

#
# @file run_call_profiling.sh
# @authors Davide Perico (davide.perico@polimi.it), Pietro Califano (petercalifano.gs@gmail.com)
# @brief Script to profile function calls and generate call graph analysis via valgrind callgrind
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano . All rights reserved .
#

# Source common parser
source "$(dirname "$0")/common_parser.sh"

# Script-specific defaults
function usage() {
    usage_parser
    echo "C++ Call Profiling Tool"
    echo ""
    echo "Runs valgrind --tool=callgrind on the target executable and generates"
    echo "annotated reports via callgrind_annotate."
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

echo -e "\033[1;34m[INFO] Starting C++ call profiling tool...\033[0m"

# Print information about the profiling run
echo -e "\033[1;36m[INFO] Profiling Configuration:\033[0m"
echo -e "\033[1;36m[INFO] - Target folder: '$OUTPUT_FOLDER'\033[0m"
echo -e "\033[1;36m[INFO] - Number of trials: $TRIALS_NUM\033[0m"
echo -e "\033[1;36m[INFO] - Starting index: $CURRENT_INDEX\033[0m"
echo -e "\033[1;36m[INFO] - Execution command: '${EXEC_CMD_ARRAY[*]}'\033[0m"

# Run the profiling tool
for ((j=CURRENT_INDEX; j<CURRENT_INDEX+TRIALS_NUM; j++)); do
    echo -e "\033[1;33m[INFO] Running profiling iteration $((j-CURRENT_INDEX+1)) of $TRIALS_NUM...\033[0m"
    "${_sudo[@]}" valgrind --tool=callgrind \
            --collect-systime=msec \
            --callgrind-out-file="$OUTPUT_FOLDER/callgrind.out.$j" \
            -v \
            --log-file="$OUTPUT_FOLDER/valg_call_out.$j.txt" \
            "${EXEC_CMD_ARRAY[@]}"

    echo -e "\033[1;32m[INFO] Generating callgrind report for iteration $((j-CURRENT_INDEX+1))...\033[0m"
    callgrind_annotate --auto=yes "$OUTPUT_FOLDER/callgrind.out.$j" > "$OUTPUT_FOLDER/callgrind_report.$j.txt"
done

echo -e "\033[1;34m[INFO] C++ call profiling tool completed.\033[0m"
