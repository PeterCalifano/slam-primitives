#!/usr/bin/env bash
#
# @file common_parser.sh
# @authors Davide Perico (davide.perico@polimi.it), Pietro Califano (petercalifano.gs@gmail.com)
# @brief Common argument parser sourced by all profiling scripts
# @date 2025-07-24
#
# @copyright Copyright (C) 2021 DART Lab - Politecnico di Milano . All rights reserved .
#

# Determine if sudo is needed (skip if already running as root)
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    _sudo=()
else
    _sudo=(sudo)
fi

# Default values
OUTPUT_FOLDER="prof_results"
EXECUTABLE_TARGET=""
ARGS=""
TRIALS_NUM=1
CURRENT_INDEX=1

# Global array for remaining args after common parsing
_remaining_args=()

# Global array for the execution command (populated by build_execution_command)
EXEC_CMD_ARRAY=()

# Parse common arguments
function parse_common_args() {
    _remaining_args=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    echo -e "\033[0;31mERROR: Option $1 requires an argument.\033[0m" >&2
                    exit 1
                fi
                OUTPUT_FOLDER="$2"
                shift 2
                ;;
            -e|--executable-target|--executable)
                if [[ -z "${2:-}" ]]; then
                    echo -e "\033[0;31mERROR: Option $1 requires an argument.\033[0m" >&2
                    exit 1
                fi
                EXECUTABLE_TARGET="$2"
                shift 2
                ;;
            -a|--args)
                if [[ -z "${2:-}" ]]; then
                    echo -e "\033[0;31mERROR: Option $1 requires an argument.\033[0m" >&2
                    exit 1
                fi
                ARGS="$2"
                shift 2
                ;;
            -t|--trials)
                if [[ -z "${2:-}" ]]; then
                    echo -e "\033[0;31mERROR: Option $1 requires an argument.\033[0m" >&2
                    exit 1
                fi
                TRIALS_NUM="$2"
                shift 2
                ;;
            -i|--index)
                if [[ -z "${2:-}" ]]; then
                    echo -e "\033[0;31mERROR: Option $1 requires an argument.\033[0m" >&2
                    exit 1
                fi
                CURRENT_INDEX="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                _remaining_args=("$@")
                return
                ;;
            *)
                # Store remaining args for script-specific parsing
                _remaining_args=("$@")
                return
                ;;
        esac
    done
}

# Validate required arguments
function validate_common_args() {
    if [[ -z "$EXECUTABLE_TARGET" ]]; then
        echo -e "\033[0;31mERROR: executable-target not specified. Use -e or --executable-target to specify.\033[0m" >&2
        if declare -f usage > /dev/null; then
            usage
        else
            echo "No usage function defined for this script. Printing common parser usage:"
            usage_parser
        fi
        exit 1
    fi
}

# Create target folder
function create_target_folder() {
    mkdir -p "$OUTPUT_FOLDER"
}

# Build the execution command into the global EXEC_CMD_ARRAY.
# Use "${EXEC_CMD_ARRAY[@]}" at call sites to preserve word boundaries.
function build_execution_command() {
    EXEC_CMD_ARRAY=("$EXECUTABLE_TARGET")
    if [[ -n "$ARGS" ]]; then
        read -ra _args_split <<< "$ARGS"
        EXEC_CMD_ARRAY+=("${_args_split[@]}")
    fi
}

function usage_parser() {
    echo "Common parser usage: [options]"
    echo ""
    echo "Options:"
    echo "  -o, --output            Output folder (default: './prof_results/')"
    echo "  -e, --executable        Executable target (required)"
    echo "  -a, --args              Arguments for the executable (quote if multiple)"
    echo "  -t, --trials            Number of trials (default: 1)"
    echo "  -i, --index             Starting index for output files (default: 1)"
    echo "  -h, --help              Show this help message"
    echo ""
}
