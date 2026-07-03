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
wrap_submodule_init=true
wrap_branch="master"
default_wrapper_interface="src/slam_primitives/wrapped/slam_primitives_wrapper.i"
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

has_wrapper_interface_override() {
  local _define=""
  for _define in "${cmake_defines[@]}"; do
    case "$_define" in
      -D*_WRAPPER_INTERFACE_FILES=*)
        return 0
        ;;
      -D*_WRAPPER_AUTODISCOVER_INTERFACE_FILES=ON|-D*_WRAPPER_AUTODISCOVER_INTERFACE_FILES=TRUE|-D*_WRAPPER_AUTODISCOVER_INTERFACE_FILES=1|-D*_WRAPPER_AUTODISCOVER_INTERFACE_FILES=on|-D*_WRAPPER_AUTODISCOVER_INTERFACE_FILES=true)
        return 0
        ;;
    esac
  done
  return 1
}

cache_get_value() {
  local _cache_file="$1"
  local _cache_key="$2"
  [[ -f "$_cache_file" ]] || return 1
  awk -v key="${_cache_key}:" 'index($0, key) == 1 { sub(/^[^=]*=/, "", $0); print; exit }' "$_cache_file"
}

warn_python_wrapper_absent() {
  local _cache_file="$1"
  local _python_target="$2"
  local _wrapper_option=""
  local _disable_reason=""
  local _interface_files=""

  warn "Python wrapper requested but target '${_python_target}' is not defined in '${buildpath}'."

  if [[ "$rebuild_only" == true ]]; then
    warn "--rebuild-only reused the existing CMake cache. Re-run without -r if this build directory was not configured with Python wrapping."
  fi

  if [[ -f "$_cache_file" && -n "$project_name" ]]; then
    _wrapper_option="$(cache_get_value "$_cache_file" "${project_name}_BUILD_PYTHON_WRAPPER" || true)"
    _disable_reason="$(cache_get_value "$_cache_file" "${project_name}_WRAPPER_DISABLE_REASON" || true)"
    _interface_files="$(cache_get_value "$_cache_file" "${project_name}_WRAPPER_INTERFACE_FILES_EFFECTIVE" || true)"

    if [[ "$_wrapper_option" == "OFF" ]]; then
      warn "CMake cache shows '${project_name}_BUILD_PYTHON_WRAPPER=OFF'."
    fi

    if [[ "$_disable_reason" == "missing_or_invalid_interface_files" ]]; then
      if [[ -n "$_interface_files" ]]; then
        warn "CMake auto-disabled wrappers because no valid interface files were configured. Current configured value: '${_interface_files}'."
      else
        warn "CMake auto-disabled wrappers because no valid interface files were configured."
      fi
    fi
  fi

  if [[ -n "$project_name" ]]; then
    warn "Check '${default_wrapper_interface}' or pass -D${project_name}_WRAPPER_INTERFACE_FILES=<file> / -D${project_name}_WRAPPER_AUTODISCOVER_INTERFACE_FILES=ON, then re-run configure without -r."
  else
    warn "Check '${default_wrapper_interface}' or pass the project-specific *_WRAPPER_INTERFACE_FILES / *_WRAPPER_AUTODISCOVER_INTERFACE_FILES CMake option, then re-run configure without -r."
  fi
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
      --no-wrap-submodule-init
                              Disable wrap submodule initialization fallback
  -i, --install               Run "install" target after tests
  -N, --ninja-build           Use Ninja generator (requires `ninja`)
  -n, --no-optim              Set -DNO_OPTIMIZATION=ON in the CMake cache
      --profile               Enable profiling build (-DENABLE_PROFILING=ON)
      --toolchain <file>      Pass CMake toolchain file (-DCMAKE_TOOLCHAIN_FILE=<file>)
      --clean                 Delete build dir before configuring
                              (recommended for cross-machine/cache portability checks)
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
  * Wrapper rebuilds with "-r -p" or "-r -m" only work if the existing build
    directory was already configured with those wrappers enabled.
  * The default wrapper interface file is "src/slam_primitives/wrapped/slam_primitives_wrapper.i". If it is
    missing, wrapper generation is auto-disabled unless you pass a valid
    *_WRAPPER_INTERFACE_FILES or *_WRAPPER_AUTODISCOVER_INTERFACE_FILES option.
  * If no local wrap checkout is found, CMake tries find_package(gtwrap)
    before optionally initializing a declared wrap submodule.
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
LONGOPTIONS=buildpath:,jobs:,rebuild-only,type:,type-build:,checks,flagsCXX:,define:,python-wrap,matlab-wrap,gtwrap-root:,no-wrap-update,no-wrap-submodule-init,help,ninja-build,no-optim,skip-tests,clean,install,profile,toolchain:
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
        --no-wrap-submodule-init) wrap_submodule_init=false; shift ;;
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
wrapper_interface_override=false
prepare_wrap_checkout=false

if [[ "$rebuild_only" == false && ( "$python_wrap" == true || "$matlab_wrap" == true ) ]]; then
  if has_wrapper_interface_override; then
    wrapper_interface_override=true
    prepare_wrap_checkout=true
  elif [[ -f "${default_wrapper_interface}" ]]; then
    prepare_wrap_checkout=true
  else
    if [[ -n "$project_name" ]]; then
      warn "Default wrapper interface file '${default_wrapper_interface}' is missing. Wrappers will be auto-disabled unless you pass -D${project_name}_WRAPPER_INTERFACE_FILES=<file> or -D${project_name}_WRAPPER_AUTODISCOVER_INTERFACE_FILES=ON."
    else
      warn "Default wrapper interface file '${default_wrapper_interface}' is missing. Wrappers will be auto-disabled unless you pass the project-specific *_WRAPPER_INTERFACE_FILES or *_WRAPPER_AUTODISCOVER_INTERFACE_FILES CMake option."
    fi
  fi
fi

if [[ "$rebuild_only" == false && "$prepare_wrap_checkout" == true ]]; then
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
cmake_version_line="$(cmake --version | head -n1)"
cmake_version="${cmake_version_line#cmake version }"

# Print info
info "CMake version      : ${cmake_version}"
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
info "GTWRAP submodule   : $wrap_submodule_init"
info "Generator          : $([[ "$use_ninja" == true ]] && echo Ninja || echo 'Unix Makefiles')"
info "Profiling build    : $profiling"
info "Toolchain file     : ${toolchain_file:-<none>}"
info "Run tests          : $run_tests"
info "Install after build: $install"

if [[ "$rebuild_only" == false && -d "$buildpath" && "$clean_first" == false ]]; then
  warn "Reusing existing build dir '$buildpath'. Use --clean for cross-machine/config portability checks."
fi

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
    "-DEXTRA_CXX_FLAGS=$CXX_FLAGS"
    "-DEXTRA_C_FLAGS=$CXX_FLAGS"
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
    if [[ -n "$project_name" ]]; then
      cmake_args+=( "-D${project_name}_GTWRAP_ROOT_DIR=$gtwrap_root" )
    else
      cmake_args+=( "-DGTWRAP_ROOT_DIR=$gtwrap_root" )
    fi
  fi
  if [[ "$prepare_wrap_checkout" == true ]]; then
    if [[ "$wrap_update" == true ]]; then
      cmake_args+=( "-DGTWRAP_BRANCH=$wrap_branch" -DGTWRAP_SYNC_TO_MASTER=ON )
    else
      cmake_args+=( -DGTWRAP_SYNC_TO_MASTER=OFF )
    fi
    if [[ "$wrap_submodule_init" == true ]]; then
      cmake_args+=( -DGTWRAP_INIT_SUBMODULE_IF_MISSING=ON )
    else
      cmake_args+=( -DGTWRAP_INIT_SUBMODULE_IF_MISSING=OFF )
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
  cache_file="${buildpath}/CMakeCache.txt"
  python_target="$(cache_get_value "$cache_file" "${project_name}_PYTHON_WRAPPER_TARGET" || true)"
  [[ -z "$python_target" ]] && python_target="${project_name}_py"
  target_help_output="$(cmake --build "$buildpath" --target help 2>/dev/null || true)"
  if awk -v target="${python_target}" '$1 == "..." && $2 == target { found=1; exit } END { exit(found ? 0 : 1) }' <<<"${target_help_output}"; then
    info "Ensuring Python wrapper target '${python_target}' is built..."
    cmake --build "$buildpath" --parallel "$jobs" --target "${python_target}"
  else
    warn_python_wrapper_absent "$cache_file" "${python_target}"
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
