# Repository Guidelines

## Project Structure & Module Organization

`slam-primitives` is a header-only C++20 library for visual-SLAM primitives. Public headers live under `src/slam_primitives/`, grouped by domain: `types/`, `containers/`, `feature_sets/`, `bundle/`, `covisibility/`, and optional `wrapped/` gtwrap bindings. Tests mirror those groups under `tests/test_*`. Examples live in `examples/`; Doxygen assets live in `doc/`; CMake helpers live in `cmake/`. The Python package surface is generated from `python/*.in` and imports as `slam_primitives`.

## Build, Test, and Development Commands

- `./build_lib.sh`: configure, build, and run the default Catch2 suite in `build/`.
- `./build_lib.sh -N -i`: build with Ninja and install.
- `cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo && cmake --build build --parallel`: manual build path.
- `ctest --test-dir build --output-on-failure`: run all registered tests.
- `cmake --build build --target doc`: build Doxygen docs when configured.
- Add `-DCPU_ENABLE_NATIVE_TUNING=OFF` for portable CI or redistributable binaries.

## Coding Style & Naming Conventions

Use `gtsam_spaceNav` as the local C++ reference. Apply Jason Turner's modern C++ practices as a bias adapted to this codebase, not as a wholesale style replacement: clear ownership, RAII, const-correct APIs, compile-time checks where useful, no avoidable raw owning pointers, no macro metaprogramming when templates or concepts work, and warnings treated as design feedback. Use C++20 for new code; prefer concepts over SFINAE. Keep the library header-only unless a build-boundary reason exists.

Make APIs explicit about invariants and lifetime. Prefer value types and references for required inputs, pointers only when null is meaningful, and `std::span`/views for non-owning ranges. Distinguish expected absence, recoverable invalid input, and internal invariant failures: use `std::optional`/typed results for absence, standard exceptions for invalid public input, and side-effect-free assertions only for internal invariants. Follow the Rule of Zero where practical and mark single-argument constructors `explicit`. Mark value-returning query APIs `[[nodiscard]]` when ignoring the result is probably a bug. Use `constexpr`, `noexcept`, and `static_assert` when they express a real contract, not as decoration. Keep headers self-contained and avoid hidden global state, surprising allocation, public macros, and `using namespace` directives in headers.

Match existing names: classes use `C...` (`CFeatureTrack`), plain data structs use `S...`, enums use `E...`, and methods use lower camel case (`getTrackLength`). Keep APIs small and explicit. Python code requires Python >= 3.12, complete type hints, dataclasses over ad-hoc dicts, and enums over multi-value literals.

## Testing Guidelines

Use Catch2 for C++ tests. Add tests next to the affected module, naming files `test_<TypeOrFeature>.cpp`, and use descriptive `TEST_CASE` names with tags such as `[feature_sets]`. Every new or changed public header must compile when included by itself, without relying on transitive includes. For wrapper changes, include the relevant CTest target and import-level validation. Prefer focused regression tests before broad integration tests.

Review new code against the same standard: check ownership/lifetime clarity, invariant enforcement, warning cleanliness, header self-sufficiency, wrapper impact, and whether tests cover boundary conditions as well as nominal behavior.

## Commit & Pull Request Guidelines

Follow the existing short imperative commit style, optionally with scoped markers such as `[MAJOR]`. Keep commits behaviorally coherent: library API, build system, wrapper, docs, and tests should be separable when practical. Pull requests should describe the behavioral change, list validation commands, note any CMake options touched, and mention wrapper/docs impacts.

## Agent-Specific Instructions

Before context compaction, write the active task state to `CONTEXT.md`. After compaction, reread `AGENTS.md` and `CONTEXT.md` before continuing. Do not overwrite unrelated local changes; this repository often has active work in progress. Do not commit unless explicitly asked.
