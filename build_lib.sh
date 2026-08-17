#!/usr/bin/env bash
# Build helper for CMake-based C++ projects (Linux)
# - Created Jan 2024; updated Jul 2026
# - Uses GNU getopt for long options
# - Generator-agnostic build via `cmake --build`

set -Eeuo pipefail
IFS=$'\n\t' # Narrows word splitting to newlines and tabs (safe with spaces)

# --- Defaults ---
script_path="$(realpath -- "${BASH_SOURCE[0]}")"
project_root="$(dirname "${script_path}")"
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
wrap_update=false
wrap_submodule_init=false
wrap_branch="master"
default_wrapper_interface="src/slam_primitives/wrapped/slam_primitives.i"
python_test_conda_env=""
python_test_conda_prefix=""
python_test_executable=""
ctest_extra_args=""
cmake_defines=()

detect_project_name() {
  local _cmakelists="${project_root}/CMakeLists.txt"
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
  for _candidate in "${project_root}/wrap" "${project_root}/lib/wrap" "${project_root}/../wrap"; do
    if [[ -f "${_candidate}/cmake/PybindWrap.cmake" ]]; then
      (cd "${_candidate}" && pwd -P)
      return 0
    fi
  done
  return 1
}

# Helper function to print instructions
usage() {
  cat <<'USAGE'
Usage: build_lib.sh [OPTIONS]

Options:
  -B, --buildpath <dir>       Build directory (default: <checkout>/build)
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
      --wrap-update           Explicitly update a local wrap checkout to latest master
      --no-wrap-update        Keep the local wrap checkout unchanged (default)
      --wrap-submodule-init   Explicitly initialize a declared wrap submodule fallback
      --no-wrap-submodule-init
                              Do not initialize a wrap submodule (default)
  -i, --install               Run "install" target after tests
  -N, --ninja-build           Use Ninja generator (requires `ninja`)
  -n, --no-optim              Set -DNO_OPTIMIZATION=ON in the CMake cache
      --profile               Enable profiling build (-DENABLE_PROFILING=ON)
      --toolchain <file>      Pass CMake toolchain file (-DCMAKE_TOOLCHAIN_FILE=<file>)
      --python-test-conda-env <name>
                              Run registered test*.py CTest entries with "conda run -n <name>"
      --python-test-conda-prefix <dir>
                              Run registered test*.py CTest entries with "conda run -p <dir>"
      --python-test-executable <path>
                              Python executable for test*.py CTest entries when conda is not selected
      --ctest-extra-args <args>
                              Simple whitespace-split arguments appended to ctest
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
  * "--clean" is ignored with "--rebuild-only". Otherwise it accepts only
    conventional in-repository paths owned by this checkout's CMake cache.
  * Relative build paths resolve against the checkout containing this script,
    even when the script is invoked from another working directory.
  * The default wrapper interface file is "src/slam_primitives/wrapped/slam_primitives.i". If it is
    missing, wrapper generation is auto-disabled unless you pass a valid
    *_WRAPPER_INTERFACE_FILES or *_WRAPPER_AUTODISCOVER_INTERFACE_FILES option.
  * If no local wrap checkout is found, CMake tries find_package(gtwrap)
    before optionally initializing a declared wrap submodule.
  * Wrapper checkout updates and submodule initialization are opt-in operations.
  * This script requires GNU getopt (standard on Debian/Ubuntu).
USAGE
}

# Auxiliary functions
die()  { echo -e "\e[31mError:\e[0m $*" >&2; echo; usage; exit 2; } # Stop execution due to error
info() { echo -e "\e[34m[INFO]\e[0m $*"; } # Print info
warn() { echo -e "\e[33m[WARN]\e[0m $*"; } # Print warning
trap 'echo -e "\e[31mBuild failed (line $LINENO).\e[0m"' ERR # Exit condition

# Prove that an existing recursive-removal target is a conventional CMake build
# owned by the checkout containing this script.
validate_clean_build_path() {
  local relative_buildpath_
  local build_cache_
  local cached_source_dir_

  # Constrain recursive removal to one CMake build owned by this checkout.
  buildpath="$(realpath -m "$buildpath")"
  relative_buildpath_="${buildpath#"${project_root}/"}"
  if [[ "$relative_buildpath_" == "$buildpath" ]]; then
    die "--clean requires a build directory inside '${project_root}'"
  fi
  case "$relative_buildpath_" in
    build|build/*|build[^/]*|out/*) ;;
    *)
      die "--clean requires a conventional build path (build, build*, or out/*)"
      ;;
  esac

  if [[ -e "$buildpath" ]]; then
    build_cache_="${buildpath}/CMakeCache.txt"
    [[ -f "$build_cache_" ]] ||
      die "Refusing to clean a directory without a CMake cache: $buildpath"
    cached_source_dir_="$(
      sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$build_cache_" |
        tail -n 1
    )"
    [[ -n "$cached_source_dir_" ]] ||
      die "CMake source marker is missing from '$build_cache_'"
    cached_source_dir_="$(realpath -m "$cached_source_dir_")"
    [[ "$cached_source_dir_" == "$project_root" ]] ||
      die "Refusing to clean a build owned by '$cached_source_dir_'"
  fi
}

# --- argument parsing (GNU getopt) ---
if ! command -v getopt > /dev/null 2>&1; then
  die "GNU getopt is required. On macOS: brew install gnu-getopt and adjust PATH."
fi

OPTIONS=B:j:rt:c:f:D:pmhNni
LONGOPTIONS=buildpath:,jobs:,rebuild-only,type:,type-build:,checks,flagsCXX:,define:,python-wrap,matlab-wrap,gtwrap-root:,wrap-update,no-wrap-update,wrap-submodule-init,no-wrap-submodule-init,help,ninja-build,no-optim,skip-tests,clean,install,profile,toolchain:,python-test-conda-env:,python-test-conda-prefix:,python-test-executable:,ctest-extra-args:
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
        --wrap-update)    wrap_update=true; shift ;;
        --no-wrap-update) wrap_update=false; shift ;;
        --wrap-submodule-init) wrap_submodule_init=true; shift ;;
        --no-wrap-submodule-init) wrap_submodule_init=false; shift ;;
    -i|--install)         install=true;    shift ;;
    -N|--ninja-build)     use_ninja=true;  shift ;;
    -n|--no-optim)        no_optim=true;   shift ;;
        --profile)        profiling=true;  shift ;;
        --toolchain)      toolchain_file="$2"; shift 2 ;;
        --python-test-conda-env) python_test_conda_env="$2"; shift 2 ;;
        --python-test-conda-prefix) python_test_conda_prefix="$2"; shift 2 ;;
        --python-test-executable) python_test_executable="$2"; shift 2 ;;
        --ctest-extra-args) ctest_extra_args="$2"; shift 2 ;;
        --clean)          clean_first=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    --) shift; break ;;
     *) die "Unknown option: $1" ;;
  esac
done

# Resolve every relative build location against the helper's checkout before
# any validation, configuration, build, test, or install operation consumes it.
if [[ "$buildpath" == /* ]]; then
  buildpath="$(realpath -m -- "$buildpath")"
else
  buildpath="$(realpath -m -- "${project_root}/${buildpath}")"
fi

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
if [[ -n "$python_test_conda_env" && -n "$python_test_conda_prefix" ]]; then
  die "Use only one of --python-test-conda-env or --python-test-conda-prefix"
fi
if [[ -n "$python_test_conda_prefix" && ! -d "$python_test_conda_prefix" ]]; then
  die "Python test conda prefix not found: $python_test_conda_prefix"
fi
if [[ -n "$python_test_executable" && ! -x "$python_test_executable" ]]; then
  die "Python test executable is not executable: $python_test_executable"
fi

if [[ "$clean_first" == true && "$rebuild_only" == false ]]; then
  validate_clean_build_path
fi

project_name="$(detect_project_name || true)"
prepare_wrap_checkout=false

if [[ "$rebuild_only" == false && ( "$python_wrap" == true || "$matlab_wrap" == true ) ]]; then
  if has_wrapper_interface_override; then
    prepare_wrap_checkout=true
  elif [[ -f "${project_root}/${default_wrapper_interface}" ]]; then
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
info "Extra CTest args   : ${ctest_extra_args:-<none>}"
info "Python wrapper     : $python_wrap"
info "MATLAB wrapper     : $matlab_wrap"
info "Detected project   : ${project_name:-<unknown>}"
info "GTWRAP root        : ${gtwrap_root:-<auto>}"
info "GTWRAP update      : $wrap_update (branch: $wrap_branch)"
info "GTWRAP submodule   : $wrap_submodule_init"
info "Generator          : $([[ "$use_ninja" == true ]] && echo Ninja || echo 'Unix Makefiles')"
info "Profiling build    : $profiling"
info "Toolchain file     : ${toolchain_file:-<none>}"
info "Python test conda  : ${python_test_conda_env:-${python_test_conda_prefix:-<none>}}"
info "Python test exe    : ${python_test_executable:-<auto>}"
info "Run tests          : $run_tests"
info "Install after build: $install"

if [[ "$rebuild_only" == false && -d "$buildpath" && "$clean_first" == false ]]; then
  warn "Reusing existing build dir '$buildpath'. Use --clean for cross-machine/config portability checks."
fi

sleep 0.2

# --- Configure ---
if [[ "$rebuild_only" == false ]]; then
  if [[ "$clean_first" == true ]]; then
    # Revalidate at the destructive boundary in case the path or cache changed
    # while wrapper prerequisites were being prepared.
    validate_clean_build_path
    if [[ -d "$buildpath" ]]; then
      info "Removing existing build dir '$buildpath'"
      rm -rf -- "$buildpath"
    fi
  fi

  cmake_args=(
    -S "$project_root"
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
      cmake_args+=(
        "-DGTWRAP_BRANCH=$wrap_branch"
        -DGTWRAP_MAINTENANCE_UPDATE=ON
        -DGTWRAP_SYNC_TO_MASTER=ON
      )
    fi
    if [[ "$wrap_submodule_init" == true ]]; then
      cmake_args+=( -DGTWRAP_INIT_SUBMODULE_IF_MISSING=ON )
    fi
  fi
  [[ "$no_optim"   == true ]] && cmake_args+=( -DNO_OPTIMIZATION=ON )
  [[ "$profiling"  == true ]] && cmake_args+=( -DENABLE_PROFILING=ON )
  [[ -n "$toolchain_file" ]] && cmake_args+=( "-DCMAKE_TOOLCHAIN_FILE=$toolchain_file" )
  [[ -n "$python_test_conda_env" ]] && cmake_args+=( "-DPYTHON_TEST_CONDA_ENV=$python_test_conda_env" )
  [[ -n "$python_test_conda_prefix" ]] && cmake_args+=( "-DPYTHON_TEST_CONDA_PREFIX=$python_test_conda_prefix" )
  [[ -n "$python_test_executable" ]] && cmake_args+=( "-DPYTHON_TEST_EXECUTABLE=$python_test_executable" )
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
  ctest_args=(--test-dir "$buildpath" --output-on-failure -j "$jobs")
  if [[ -n "$ctest_extra_args" ]]; then
    IFS=' ' read -r -a parsed_ctest_extra_args <<< "$ctest_extra_args"
    ctest_args+=("${parsed_ctest_extra_args[@]}")
  fi
  ctest "${ctest_args[@]}"
fi

# --- Install ---
if [[ "$install" == true ]]; then
  info "Installing..."
  cmake --build "$buildpath" --parallel "$jobs" --target install
fi

info "Done."
