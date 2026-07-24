#!/usr/bin/env bash
# Build the optional ROS 2 core/interfaces overlay independently of the normal
# header-only library workflow.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
WORKSPACE_DIR="${ROOT_DIR}/ros2"
ROS_DISTRO_NAME="${ROS_DISTRO:-jazzy}"

build_type="RelWithDebInfo"
clean=false
skip_tests=false
enable_cuda=false
metadata_sync=true
packages_select=()
cmake_args=()
colcon_args=()

info() { printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./build_ros2.sh [options]

Purpose:
  Build the optional ROS 2 shim and interface packages in ros2/. The normal
  header-only C++ library remains ROS-free and builds with ./build_lib.sh.

Options:
  --clean                    Remove ros2/build, ros2/install, and ros2/log.
  --skip-tests               Skip colcon test and test-result.
  --debug                    Use CMAKE_BUILD_TYPE=Debug.
  --release                  Use CMAKE_BUILD_TYPE=Release.
  --cuda                     Enable optional CUDA in the core shim.
  --no-version-sync          Keep existing package.xml metadata unchanged.
  --packages-select <name>   Build/test one package (repeatable).
  --cmake-arg <arg>          Append one colcon CMake argument (repeatable).
  --colcon-arg <arg>         Append one colcon build argument (repeatable).
  -h, --help                 Show this help.
EOF
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --clean)
        clean=true
        shift
        ;;
      --skip-tests)
        skip_tests=true
        shift
        ;;
      --debug)
        build_type="Debug"
        shift
        ;;
      --release)
        build_type="Release"
        shift
        ;;
      --cuda)
        enable_cuda=true
        shift
        ;;
      --no-version-sync)
        metadata_sync=false
        shift
        ;;
      --packages-select)
        (($# >= 2)) || die "--packages-select requires a package name"
        packages_select+=("$2")
        shift 2
        ;;
      --cmake-arg)
        (($# >= 2)) || die "--cmake-arg requires a value"
        cmake_args+=("$2")
        shift 2
        ;;
      --colcon-arg)
        (($# >= 2)) || die "--colcon-arg requires a value"
        colcon_args+=("$2")
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

source_ros_environment() {
  local setup_file_="/opt/ros/${ROS_DISTRO_NAME}/setup.bash"
  [[ -f "${setup_file_}" ]] ||
    die "ROS setup file not found: ${setup_file_}. Install ROS 2 ${ROS_DISTRO_NAME} or set ROS_DISTRO. The core library itself needs no ROS."

  # ROS setup scripts commonly read optional unset environment variables.
  set +u
  # shellcheck disable=SC1090
  source "${setup_file_}"
  set -u

  command -v colcon >/dev/null 2>&1 ||
    die "colcon was not found after sourcing ${setup_file_}"
}

clean_workspace() {
  [[ "${WORKSPACE_DIR}" == "${ROOT_DIR}/ros2" ]] ||
    die "Refusing to clean unexpected workspace path: ${WORKSPACE_DIR}"
  command -v cmake >/dev/null 2>&1 ||
    die "cmake is required to clean the ROS workspace"

  cmake -E remove_directory "${WORKSPACE_DIR}/build"
  cmake -E remove_directory "${WORKSPACE_DIR}/install"
  cmake -E remove_directory "${WORKSPACE_DIR}/log"
}

sync_package_metadata() {
  [[ "${metadata_sync}" == true ]] || return 0
  [[ -x "${ROOT_DIR}/generate_version.sh" ]] ||
    die "generate_version.sh is missing or not executable"
  grep -q -- "ROS2_PROJECT_METADATA_SYNC=1" \
    "${ROOT_DIR}/generate_version.sh" ||
    die "generate_version.sh does not support complete ROS metadata sync"

  "${ROOT_DIR}/generate_version.sh" --sync-ros2
}

run_colcon() {
  local cuda_flag_="OFF"
  local package_
  local build_command_=(
    colcon build
    --symlink-install
  )
  [[ "${enable_cuda}" == true ]] && cuda_flag_="ON"

  if((${#packages_select[@]} > 0)); then
    build_command_+=(--packages-select "${packages_select[@]}")
  fi
  if((${#colcon_args[@]} > 0)); then
    build_command_+=("${colcon_args[@]}")
  fi
  build_command_+=(
    --cmake-args
    "-DCMAKE_BUILD_TYPE=${build_type}"
    "-DSLAM_PRIMITIVES_ENABLE_CUDA=${cuda_flag_}"
    "${cmake_args[@]}"
  )

  info "Workspace : ${WORKSPACE_DIR}"
  info "ROS distro: ${ROS_DISTRO_NAME}"
  info "Build type: ${build_type}"
  info "CUDA      : ${cuda_flag_}"

  (
    cd "${WORKSPACE_DIR}"
    "${build_command_[@]}"
  )

  [[ "${skip_tests}" == false ]] || return 0

  local test_command_=(colcon test --event-handlers console_direct+)
  if((${#packages_select[@]} > 0)); then
    test_command_+=(--packages-select "${packages_select[@]}")
  fi

  (
    cd "${WORKSPACE_DIR}"
    "${test_command_[@]}"
    if((${#packages_select[@]} > 0)); then
      for package_ in "${packages_select[@]}"; do
        colcon test-result \
          --test-result-base "build/${package_}" --verbose
      done
    else
      colcon test-result --verbose
    fi
  )
}

main() {
  parse_args "$@"
  [[ -d "${WORKSPACE_DIR}" ]] ||
    die "ROS 2 workspace directory not found: ${WORKSPACE_DIR}"

  source_ros_environment
  [[ "${clean}" == false ]] || clean_workspace
  sync_package_metadata
  run_colcon
}

main "$@"
