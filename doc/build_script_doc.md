# build_lib.sh - Detailed changes & option reference

## 1) Shell safety & ergonomics

**`set -Eeuo pipefail`**

* **`-E`**: ensures ERR traps propagate through functions and subshells.
* **`-e`**: exit on unhandled non‑zero status (fail fast).
* **`-u`**: treat unset variables as errors (catches typos/undefined vars).
* **`-o pipefail`**: a pipeline fails if any command fails, not just the last.

**`IFS` restricted to newline and tab**

* Narrows the word-splitting delimiters to newline/tab (safer for paths with spaces).

**`trap 'echo -e "\e[31mBuild failed (line $LINENO).\e[0m"' ERR`**

* Prints a concise, visible message on any error path with the line number where it occurred.

**Helper functions**

* `die()`: prints an error (with red color), shows `usage()`, exits 2.
* `info()`: blue, prefixed status prints for consistent logs.

**JOBS default**

* `jobs` uses `$JOBS` if exported; otherwise falls back to `nproc` or 4. This lets CI override parallelism without touching the script.

---

## 2) Argument parsing (GNU getopt)

The script now uses **GNU `getopt`** to support:

* **Long options** (`--buildpath`, `--python-wrap`, etc.).
* **Short options with separate arguments**, e.g. `-B build`, `-j 8`.
* Grouping aliases: `--type` and `--type-build` both map to the same setting.

> Note: We intentionally **avoid optional arguments** for short flags (like `-B[=dir]`) because they are ambiguous and error‑prone. The convention is now **space‑separated values** for short options.

**Preflight**: the script checks `command -v getopt` to ensure GNU `getopt` is available; prints a clear message if not.

---

## 3) Options - full reference

### Build layout & performance

* **`-B, --buildpath <dir>`**
  Where to generate the build tree. Default: `./build`.
  *Example*: `-B out/debug`

* **`-j, --jobs <N>`**
  Parallel build/test jobs. Default: `$JOBS` env, else `nproc`, else 4.
  *Example*: `-j 12`

* **`-N, --ninja-build`**
  Use the Ninja generator (`-G Ninja`). Requires `ninja` in PATH.
  Benefits: faster incremental builds and better parallelism.

* **`--clean`**
  If present and we are configuring (i.e., not `--rebuild-only`), delete the build directory before running CMake. Useful to reset a dirty cache.

### Configure/build control

* **`-r, --rebuild-only`**
  Skip CMake configure; just build an already-configured tree.
  Useful when you’ve only changed sources and not CMake options.
  Wrapper requests passed together with `-r` only work if that build directory was already configured with wrappers enabled.

* **`-t, --type <t> | --type-build <t>`**
  Set CMake build type (`Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`). Input is case-insensitive.
  Defaults to `relwithdebinfo`.
  For `Debug`, `RelWithDebInfo`, and `Release`, the script **appends** `-Wall -Wextra -Wpedantic` to `CMAKE_CXX_FLAGS` unless you override them completely.

* **`-f, --flagsCXX "<flags>"`**
  Extra flags to append to both `CMAKE_CXX_FLAGS` and `CMAKE_C_FLAGS`.
  Example: `-f "-march=native"`.
  These are added **before** the auto-appended warnings, so you can still override with `-Wno-...` if needed.

* **`-D, --define <VAR=VAL>`**
  Pass extra CMake cache definitions (repeatable).
  Example:
  `-D ENABLE_CUDA=ON -D CUDA_ENABLE_FMAD=ON -D ENABLE_TBB=ON`.

* **`-n, --no-optim`**
  Sets `-DNO_OPTIMIZATION=ON` in the CMake cache. Your toolchain/CMakeLists can use this to toggle optimizer knobs (e.g., turn off vectorization or special CPU flags independent of `CMAKE_BUILD_TYPE`).

* **`--toolchain <file>`**
  Pass a CMake toolchain file: `-DCMAKE_TOOLCHAIN_FILE=<file>`.
  Example: `--toolchain cmake/toolchains/clang.cmake`.

* **`-p, --python-wrap`**
  Enables Python wrappers by setting:
  `-DGTWRAP_BUILD_PYTHON_DEFAULT=ON` and `-Dslam-primitives_BUILD_PYTHON_WRAPPER=ON`.
  After the standard build, it also ensures the resolved Python wrapper target is built explicitly when that target exists in the configured cache.
  If `src/slam_primitives/wrapped/slam_primitives.i` is missing, or if the configured `*_WRAPPER_INTERFACE_FILES` list is invalid, CMake auto-disables wrappers and the script emits a warning instead of failing the whole build.

* **`-m, --matlab-wrap`**
  Enables MATLAB wrappers by setting:
  `-DGTWRAP_BUILD_MATLAB_DEFAULT=ON` and `-Dslam-primitives_BUILD_MATLAB_WRAPPER=ON`.

* **`--gtwrap-root <dir>`**
  Pins wrapper generation to a local wrap checkout.
  The script forwards this as:
  `-Dslam-primitives_GTWRAP_ROOT_DIR=<dir>` when the project name is detected, otherwise `-DGTWRAP_ROOT_DIR=<dir>`.

* **`--no-wrap-update`**
  Disables automatic update of local wrap checkout. By default, wrapper builds
  first resolve an explicit `--gtwrap-root` or auto-detect `./wrap`,
  `./lib/wrap`, and `../wrap`, then update the resolved local checkout to latest
  `origin/master` (including detached/tag checkouts).

* **`--no-wrap-submodule-init`**
  Disables the final fallback that initializes a declared `wrap`/`lib/wrap`
  git submodule.
  By default, wrapper resolution order is:
  1. explicit or auto-detected local checkout;
  2. installed `gtwrap` via `find_package(gtwrap)`;
  3. declared git submodule initialization.

* **`-i, --install`**
  After a successful build (and tests), runs the `install` target.
  Implement your install rules in CMake; we call:
  `cmake --build <buildpath> --target install --parallel <jobs>`.

### Tests

* **`-c, --checks`**
  Enable tests (default is already **on**). Left for backward compatibility.

* **`--skip-tests`** (alias `--no-checks`)
  Disable tests.
  **Note**: For **Release**, tests are **forced on** regardless (safer CI default).

### Help

* **`-h, --help`**
  Shows the `usage()` with examples and exits.

---

## 4) CMake invocation strategy

**Generator‑agnostic build**

* **Configure**: `cmake -S . -B <dir> [args...]`
  Uses arrays and proper quoting to avoid word splitting.
* **Build**: `cmake --build <dir> --parallel <jobs>`
  Works with both Makefiles and Ninja.
* **Test**: `ctest --test-dir <dir> --output-on-failure -j <jobs>`
  Uses CTest directly (generator‑independent).
* **Install**: `cmake --build <dir> --target install --parallel <jobs>`

**Compile commands**

* Exports `compile_commands.json` by default: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.
  Handy for clangd, code intel, and static analysis.

**Flags routing**

* Both `CMAKE_CXX_FLAGS` and `CMAKE_C_FLAGS` receive the `-f/--flagsCXX` content so C and C++ units see consistent warnings/opts. If you only have C++ you can ignore the C side.

---

## 5) Behavioral changes vs your previous script

1. **Fixed `-B build`**: short options now **require a separate argument**; this is the POSIX convention and avoids ambiguous optional short args. Long options accept `--buildpath=dir` or `--buildpath dir`.
2. **Removed duplicate `make`**: your script invoked `make` twice in a row; that’s gone.
3. **Unified build interface**: replaced direct `make` with `cmake --build` and `ctest`, so switching generators is seamless.
4. **Test policy**: tests are on by default; **Release** hard‑enables them. You can override in CI by using non‑Release or `--skip-tests` (except in Release).
5. **`--clean`**: quick way to delete the build dir before configure. You can still manually `rm -rf build` if you prefer.
6. **Robust quoting & arrays**: all user‑provided flags/paths are quoted and passed as array elements to prevent word splitting and globbing bugs.
7. **Safer shell**: `set -Eeuo pipefail`, narrowed `IFS`, and an `ERR` trap make failures noisier and earlier.
8. **Clear logging**: consistent `[INFO]` lines and a compact error banner improve CI readability.
9. **Initialized booleans**: `no_optim` and others are explicitly initialized; avoids `-u` errors.
10. **Case‑insensitive build types**: `debug`, `Debug`, `DEBUG` all map to `Debug`.
11. **Automatic warnings**: `-Wall -Wextra -Wpedantic` are appended for common build types. If you pass your own `-W...` flags, they’ll be respected.
12. **Environment override for jobs**: set `JOBS=64` in CI to change default parallelism without touching scripts.
13. **Pipefail-safe wrapper probe**: the post-build Python wrapper target check no longer uses a `cmake --build ... --target help | rg -q ...` pipeline, so `-p` does not emit a false missing-target warning after a successful wrapper build.
14. **Cache-aware wrapper diagnostics**: when Python wrappers are requested but absent, the script now reports whether `--rebuild-only` reused a non-wrapper cache, whether CMake ended up with `slam-primitives_BUILD_PYTHON_WRAPPER=OFF`, and whether wrappers were auto-disabled because interface files were missing or invalid.

---

## 6) New CMake usage patterns (optimization, CUDA, TBB)

These are configured through `-D/--define` and live in CMake (not dedicated `build_lib.sh` flags).

### CPU optimization toggles

* `CPU_ENABLE_NATIVE_TUNING=ON` (default):
  adds `-march=native -mtune=native` for optimized builds.
* `CPU_ENABLE_SIMD=ON` + `CPU_SIMD_LEVEL=<native|sse4.2|avx|avx2|avx512f>`:
  adds explicit SIMD ISA flags.
* `CPU_ENABLE_FMA=ON`:
  adds `-mfma`.
* `CPU_EXTRA_OPT_FLAGS="..."`:
  appends additional CPU optimization flags.

### CUDA optimization toggles

* `CUDA_ENABLE_FMAD=ON|OFF`:
  controls NVCC fused multiply-add contraction (`--fmad=true/false`).
* `CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION=ON|OFF`:
  adds `--extra-device-vectorization`.
* `CUDA_USE_FAST_MATH=ON|OFF`:
  applies `--use_fast_math` to regular CUDA compilation.
* `CUDA_NVCC_EXTRA_FLAGS="..."`:
  appends extra NVCC flags to CUDA compilation.

### CUDA architecture detection

* If `CUDA_ARCHITECTURES` is set, the template uses it directly.
* Else if `CMAKE_CUDA_ARCHITECTURES` is set, the template uses it directly.
* Else on `x86_64`/`amd64`, the template requires a working `nvidia-smi` and fails fast if it is missing, fails, or returns malformed data.
* Else on `aarch64`/`arm64`, the template tries `nvidia-smi` first and then falls back to native Jetson/Tegra markers:
  * Xavier / `tegra194` -> `72`
  * Orin / `tegra234` -> `87`
  * Thor / `tegra264` -> `101`
* If auto-detection is unavailable or ambiguous, configure fails with guidance to set `CUDA_ARCHITECTURES` or `CMAKE_CUDA_ARCHITECTURES` explicitly.

### TBB support

* `ENABLE_TBB=ON`:
  enables oneTBB via `find_package(TBB REQUIRED COMPONENTS tbb)` and links `TBB::tbb`.

---

## 7) Example workflows

* **Default dev build** (RelWithDebInfo):

  ```bash
  ./build_lib.sh
  ```

* **Debug + Ninja + extra flags + 12 jobs**:

  ```bash
  ./build_lib.sh -t debug -N -j 12 -f "-g3"
  ```

* **Portable release build** (disable native tuning):

  ```bash
  ./build_lib.sh -t release -D CPU_ENABLE_NATIVE_TUNING=OFF
  ```

* **Enable AVX2 + FMA + TBB**:

  ```bash
  ./build_lib.sh -D ENABLE_TBB=ON -D CPU_ENABLE_SIMD=ON -D CPU_SIMD_LEVEL=avx2 -D CPU_ENABLE_FMA=ON
  ```

* **CUDA build with explicit NVCC optimization toggles**:

  ```bash
  ./build_lib.sh -D ENABLE_CUDA=ON -D CUDA_ENABLE_FMAD=ON -D CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION=ON
  ```

* **Python + MATLAB wrappers using installed gtwrap**:

  ```bash
  ./build_lib.sh -p -m
  ```

* **Python wrapper with a local wrap checkout**:

  ```bash
  ./build_lib.sh -p --gtwrap-root /path/to/wrap
  ```

* **Rebuild only on a cache that already has Python wrapping enabled**:

  ```bash
  ./build_lib.sh -r -p
  ```

* **Release + tests + install into system prefix**:

  ```bash
  ./build_lib.sh -t release -i
  ```

* **Clean reconfigure to a custom dir**:

  ```bash
  ./build_lib.sh -B out/rel -t relwithdebinfo --clean
  ```

* **Rebuild only** (no reconfigure):

  ```bash
  ./build_lib.sh -r -j 8
  ```

* **Clang toolchain build**:

  ```bash
  ./build_lib.sh --toolchain cmake/toolchains/clang.cmake
  ```

---

## 8) Wrapper packaging notes

* Python package metadata is owned by `python/pyproject.toml.in` and configured into `python/pyproject.toml` when Python wrapping is enabled.
* The optional `python/setup.py.in` augments source-package installation behavior without duplicating package metadata.
* `python/slam_primitives/__init__.py` is the public entrypoint and exports `HAS_WRAPPER`.
* CMake updates `python/slam_primitives/_wrapper_build.py` so the source package can resolve the latest requested wrapper build.
* Missing `python/slam_primitives/__init__.py` or `python/pyproject.toml.in` no longer blocks wrapper builds: CMake generates minimal fallbacks when needed.
* Supported install paths are:

  ```bash
  cd python
  python -m pip install .
  ```

  ```bash
  cmake --build <build_dir> --target python-install
  ```

  In Conda workflows, activate the target env before running `pip install`.

---

## 9) Optional future extensions

* `--preset <name>` --> `cmake --preset <name>` / `cmake --build --preset <name>` / `ctest --preset <name>`.
* Sanitizer toggles for debug: `--asan`, `--ubsan`, `--tsan` that append safe defaults and adjust `LD_PRELOAD`/`ASAN_OPTIONS` for tests.
* Colorized `ctest` output via `--output-on-failure` (already used) and `CTEST_OUTPUT_ON_FAILURE=1` environment.

---

If you want, I can integrate **presets** and **sanitizers** directly into the script next, with sensible defaults and conflict checks.
