#!/usr/bin/env bash
# Build helper for CMake-based C++ projects (Linux)
# - Created Jan 2024; updated Aug 2025
# - Uses GNU getopt for long options
# - Generator-agnostic build via `cmake --build`

set -Eeuo pipefail
IFS=$'\n\t' # Narrows word splitting to newlines and tabs (safe with spaces)

# --- Defaults ---
buildpath="build"

jobs="${JOBS:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"
jobs=$(( jobs < 6 ? jobs : 6 ))

rebuild_only=false
build_type="relwithdebinfo"   # debug|release|relwithdebinfo|minsizerel
run_tests=true
CXX_FLAGS=""
python_wrap=false
matlab_wrap=false
install=false
use_ninja=false
no_optim=false
clean_first=false
profiling=false
toolchain_file=""
gtwrap_root=""
wrap_update=true
wrap_branch="master"
cmake_defines=()

detect_project_name() {
  local _cmakelists="CMakeLists.txt"
  local _name=""
  if [[ -f "$_cmakelists" ]]; then
    _name="$(sed -nE 's/^[[:space:]]*set[[:space:]]*[(][[:space:]]*project_name[[:space:]]+"?([^" )]+)"?.*/\1/p' "$_cmakelists" | head -n1)"
  fi
  if [[ -z "$_name" && -f "$_cmakelists" ]]; then
    _name="$(sed -nE 's/^[[:space:]]*project[[:space:]]*[(][[:space:]]*([A-Za-z0-9_+.-]+).*/\1/p' "$_cmakelists" | head -n1)"
  fi
  [[ -n "$_name" ]] && printf '%s\n' "$_name"
}

detect_wrap_root() {
  local _candidate
  for _candidate in "./wrap" "./lib/wrap" "../wrap"; do
    if [[ -f "${_candidate}/cmake/PybindWrap.cmake" ]]; then
      (cd "${_candidate}" && pwd -P)
      return 0
    fi
  done
  return 1
}

init_wrap_submodule_if_needed() {
  local _project_root="$1"
  local _wrap_rel=""

  if [[ ! -f "${_project_root}/.gitmodules" ]]; then
    return 0
  fi
  if ! git -C "${_project_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  if grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*lib/wrap[[:space:]]*$' "${_project_root}/.gitmodules"; then
    _wrap_rel="lib/wrap"
  elif grep -Eq '^[[:space:]]*path[[:space:]]*=[[:space:]]*wrap[[:space:]]*$' "${_project_root}/.gitmodules"; then
    _wrap_rel="wrap"
  fi

  if [[ -z "${_wrap_rel}" ]]; then
    return 0
  fi
  if [[ -f "${_project_root}/${_wrap_rel}/cmake/PybindWrap.cmake" ]]; then
    return 0
  fi

  info "Initializing wrap submodule (${_wrap_rel})..."
  git -C "${_project_root}" submodule sync --recursive
  git -C "${_project_root}" submodule update --init --recursive "${_wrap_rel}"
}

update_wrap_checkout() {
  local _root="$1"
  local _branch="$2"

  if [[ ! -d "${_root}/.git" ]]; then
    warn "wrap root '${_root}' is not a git checkout; skipping master update"
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    warn "git not found; skipping wrap checkout update"
    return 0
  fi

  info "Updating wrap checkout '${_root}' to latest origin/${_branch}"
  if ! git -C "${_root}" remote get-url origin >/dev/null 2>&1; then
    warn "wrap checkout '${_root}' has no 'origin' remote; skipping update"
    return 0
  fi

  if ! git -C "${_root}" fetch origin "${_branch}"; then
    warn "failed to fetch origin/${_branch} for wrap checkout '${_root}'; continuing with local state"
    return 0
  fi
  if ! git -C "${_root}" show-ref --verify --quiet "refs/remotes/origin/${_branch}"; then
    warn "origin/${_branch} not found in wrap checkout '${_root}'; continuing with local state"
    return 0
  fi

  if git -C "${_root}" show-ref --verify --quiet "refs/heads/${_branch}"; then
    if ! git -C "${_root}" checkout "${_branch}"; then
      warn "failed to checkout wrap branch '${_branch}'; continuing with local state"
      return 0
    fi
  else
    # Handle detached HEAD/tag clones by creating local branch from origin.
    if ! git -C "${_root}" checkout -B "${_branch}" "origin/${_branch}"; then
      warn "failed to create local wrap branch '${_branch}'; continuing with local state"
      return 0
    fi
  fi

  if ! git -C "${_root}" pull --ff-only origin "${_branch}"; then
    warn "failed to fast-forward wrap branch '${_branch}'; continuing with local state"
    return 0
  fi
}

# Helper function to print instructions
usage() {
  cat <<'USAGE'
Usage: build_lib.sh [OPTIONS]

Options:
  -B, --buildpath <dir>       Build directory (default: ./build)
  -j, --jobs <N>              Parallel build jobs (default: $(nproc or 4))
  -r, --rebuild-only          Skip CMake configure; build existing tree only
  -t, --type|--type-build <t> Build type: debug|release|relwithdebinfo|minsizerel
  -c, --checks                Run tests (on by default). Alias of --run-tests
      --skip-tests            Do not run tests
  -f, --flagsCXX <flags>      Extra C++ flags (quoted). Appends warnings for
                              Debug/RelWithDebInfo/Release
  -D, --define <var[=val]>    Extra CMake cache definitions (repeatable)
  -p, --python-wrap           Enable Python wrapper defaults (-DGTWRAP_BUILD_PYTHON_DEFAULT=ON)
  -m, --matlab-wrap           Enable MATLAB wrapper defaults (-DGTWRAP_BUILD_MATLAB_DEFAULT=ON)
      --gtwrap-root <dir>     Path to wrap checkout root for gtwrap
                              (maps to -D<project>_GTWRAP_ROOT_DIR=<dir>)
      --no-wrap-update        Disable auto-update of local wrap checkout to latest master
  -i, --install               Run "install" target after tests
  -N, --ninja-build           Use Ninja generator (requires `ninja`)
  -n, --no-optim              Set -DNO_OPTIMIZATION=ON in the CMake cache
      --profile               Enable profiling build (-DENABLE_PROFILING=ON)
      --toolchain <file>      Pass CMake toolchain file (-DCMAKE_TOOLCHAIN_FILE=<file>)
      --clean                 Delete build dir before configuring
  -h, --help                  Show this help and exit

Examples:
  # Configure + build (RelWithDebInfo) into ./build
  ./build_lib.sh

  # Debug build with warnings, 8 jobs, and Ninja
  ./build_lib.sh -t debug -j 8 -N

  # Custom build dir and flags, run tests then install
  ./build_lib.sh -B out/release -t release -f "-march=native" -i
./build_lib.sh -DOPENCV_DIR=/opt/opencv -DENABLE_SOMETHING=ON

Notes:
  * Short options with arguments use a separate value: "-B build", "-j 8".
    For CMake defines, use "-DVAR=ON" or "-D VAR=ON".
  * This script requires GNU getopt (standard on Debian/Ubuntu).
USAGE
}

# Auxiliary functions
die()  { echo -e "\e[31mError:\e[0m $*" >&2; echo; usage; exit 2; } # Stop execution due to error
info() { echo -e "\e[34m[INFO]\e[0m $*"; } # Print info
warn() { echo -e "\e[33m[WARN]\e[0m $*"; } # Print warning
trap 'echo -e "\e[31mBuild failed (line $LINENO).\e[0m"' ERR # Exit condition

# --- argument parsing (GNU getopt) ---
if ! command -v getopt > /dev/null 2>&1; then
  die "GNU getopt is required. On macOS: brew install gnu-getopt and adjust PATH."
fi

OPTIONS=B:j:rt:c:f:D:pmhNni
LONGOPTIONS=buildpath:,jobs:,rebuild-only,type:,type-build:,checks,flagsCXX:,define:,python-wrap,matlab-wrap,gtwrap-root:,no-wrap-update,help,ninja-build,no-optim,skip-tests,clean,install,profile,toolchain:
PARSED=$(getopt -o "$OPTIONS" -l "$LONGOPTIONS" -- "$@") || { usage; exit 2; }
eval set -- "$PARSED"

while true; do
  case "$1" in
    -B|--buildpath)       buildpath="$2"; shift 2 ;;
    -j|--jobs)            jobs="$2";     shift 2 ;;
    -r|--rebuild-only)    rebuild_only=true; shift ;;
    -t|--type|--type-build) build_type="$2"; shift 2 ;;
    -c|--checks)          run_tests=true;  shift ;;
        --skip-tests|--no-checks) run_tests=false; shift ;;
    -f|--flagsCXX)        CXX_FLAGS="$2"; shift 2 ;;
    -D|--define)          cmake_defines+=( "-D$2" ); shift 2 ;;
    -p|--python-wrap)     python_wrap=true; shift ;;
    -m|--matlab-wrap)     matlab_wrap=true; shift ;;
        --gtwrap-root)    gtwrap_root="$2"; shift 2 ;;
        --no-wrap-update) wrap_update=false; shift ;;
    -i|--install)         install=true;    shift ;;
    -N|--ninja-build)     use_ninja=true;  shift ;;
    -n|--no-optim)        no_optim=true;   shift ;;
        --profile)        profiling=true;  shift ;;
        --toolchain)      toolchain_file="$2"; shift 2 ;;
        --clean)          clean_first=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    --) shift; break ;;
     *) die "Unknown option: $1" ;;
  esac
done

# --- normalize & validate build type ---
bt="${build_type,,}"
case "$bt" in
  debug)          cmake_bt="Debug" ;;
  release)        cmake_bt="Release" ;;
  relwithdebinfo) cmake_bt="RelWithDebInfo" ;;
  minsizerel)     cmake_bt="MinSizeRel" ;;
  *) die "Invalid build type: $build_type" ;;
esac

# For common types, enforce warnings unless user already provided them
if [[ "$bt" =~ ^(debug|relwithdebinfo|release)$ ]]; then
  CXX_FLAGS="${CXX_FLAGS:+$CXX_FLAGS }-Wall -Wextra -Wpedantic"
fi

# Enforce tests for Release
if [[ "$cmake_bt" == "Release" ]]; then
  run_tests=true
fi

# Validate toolchain file if provided
if [[ -n "$toolchain_file" && ! -f "$toolchain_file" ]]; then
  die "Toolchain file not found: $toolchain_file"
fi
if [[ -n "$gtwrap_root" && ! -d "$gtwrap_root" ]]; then
  die "GTWRAP root directory not found: $gtwrap_root"
fi

project_name="$(detect_project_name || true)"

if [[ "$python_wrap" == true || "$matlab_wrap" == true ]]; then
  init_wrap_submodule_if_needed "$PWD"
  if [[ -z "$gtwrap_root" ]]; then
    gtwrap_root="$(detect_wrap_root || true)"
  fi
  if [[ -n "$gtwrap_root" && "$wrap_update" == true ]]; then
    update_wrap_checkout "$gtwrap_root" "$wrap_branch"
  fi
fi

# Pre-build checks
command -v cmake >/dev/null 2>&1 || die "cmake not found"
if [[ "$use_ninja" == true ]]; then
  command -v ninja >/dev/null 2>&1 || die "Requested Ninja but 'ninja' not found"
fi

# Print info
info "Buildpath          : $buildpath"
info "Jobs               : $jobs"
info "Build Type         : $cmake_bt"
info "Extra CXX flags    : ${CXX_FLAGS:-<none>}"
info "Extra CMake defines: ${cmake_defines[*]:-<none>}"
info "Python wrapper     : $python_wrap"
info "MATLAB wrapper     : $matlab_wrap"
info "Detected project   : ${project_name:-<unknown>}"
info "GTWRAP root        : ${gtwrap_root:-<auto>}"
info "GTWRAP auto-update : $wrap_update (branch: $wrap_branch)"
info "Generator          : $([[ "$use_ninja" == true ]] && echo Ninja || echo 'Unix Makefiles')"
info "Profiling build    : $profiling"
info "Toolchain file     : ${toolchain_file:-<none>}"
info "Run tests          : $run_tests"
info "Install after build: $install"

sleep 0.2

# --- Configure ---
if [[ "$rebuild_only" == false ]]; then
  if [[ "$clean_first" == true && -d "$buildpath" ]]; then
    info "Removing existing build dir '$buildpath'"
    rm -rf -- "$buildpath"
  fi

  cmake_args=(
    -S .
    -B "$buildpath"
    "-DCMAKE_BUILD_TYPE=$cmake_bt"
    "-DCMAKE_CXX_FLAGS=$CXX_FLAGS"
    "-DCMAKE_C_FLAGS=$CXX_FLAGS"
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  )
  [[ "$use_ninja"  == true ]] && cmake_args+=( -G Ninja )
  if [[ "$python_wrap" == true ]]; then
    if [[ -n "$project_name" ]]; then
      cmake_args+=( "-D${project_name}_BUILD_PYTHON_WRAPPER=ON" )
    else
      cmake_args+=( -DGTWRAP_BUILD_PYTHON_DEFAULT=ON )
    fi
  fi
  if [[ "$matlab_wrap" == true ]]; then
    if [[ -n "$project_name" ]]; then
      cmake_args+=( "-D${project_name}_BUILD_MATLAB_WRAPPER=ON" )
    else
      cmake_args+=( -DGTWRAP_BUILD_MATLAB_DEFAULT=ON )
    fi
  fi
  if [[ -n "$gtwrap_root" ]]; then
    cmake_args+=( "-DGTWRAP_ROOT_DIR=$gtwrap_root" )
    [[ -n "$project_name" ]] && cmake_args+=( "-D${project_name}_GTWRAP_ROOT_DIR=$gtwrap_root" )
  fi
  if [[ "$python_wrap" == true || "$matlab_wrap" == true ]]; then
    cmake_args+=( "-DGTWRAP_BRANCH=$wrap_branch" )
    if [[ "$wrap_update" == true ]]; then
      cmake_args+=( -DGTWRAP_SYNC_TO_MASTER=ON )
    else
      cmake_args+=( -DGTWRAP_SYNC_TO_MASTER=OFF )
    fi
  fi
  [[ "$no_optim"   == true ]] && cmake_args+=( -DNO_OPTIMIZATION=ON )
  [[ "$profiling"  == true ]] && cmake_args+=( -DENABLE_PROFILING=ON )
  [[ -n "$toolchain_file" ]] && cmake_args+=( "-DCMAKE_TOOLCHAIN_FILE=$toolchain_file" )
  [[ ${#cmake_defines[@]} -gt 0 ]] && cmake_args+=( "${cmake_defines[@]}" )

  info "Configuring with CMake...\n"
  cmake "${cmake_args[@]}"
elif [[ -n "$toolchain_file" ]]; then
  info "Toolchain file provided, but --rebuild-only skips configure."
fi

# --- Build ---
info "\nBuilding..."
cmake --build "$buildpath" --parallel "$jobs"

if [[ "$python_wrap" == true && -n "$project_name" ]]; then
  python_target="${project_name}_py"
  if cmake --build "$buildpath" --target help 2>/dev/null | rg -q --fixed-strings "${python_target}"; then
    info "Ensuring Python wrapper target '${python_target}' is built..."
    cmake --build "$buildpath" --parallel "$jobs" --target "${python_target}"
  else
    warn "Python wrapper requested but target '${python_target}' is not defined in '${buildpath}'."
    warn "Likely causes: configured with --rebuild-only on a cache without wrappers, wrapper auto-disabled, or missing python package metadata."
    warn "Re-run configure (without -r) and verify python/${project_name}/ plus python/pyproject.toml.in exist."
  fi
fi

# --- Test ---
if [[ "$run_tests" == true || "$install" == true ]]; then
  info "\nRunning tests..."
  ctest --test-dir "$buildpath" --output-on-failure -j "$jobs"
fi

# --- Install ---
if [[ "$install" == true ]]; then
  info "Installing..."
  cmake --build "$buildpath" --parallel "$jobs" --target install
fi

info "Done."
