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

Use `gtsam_spaceNav` as the local C++ reference. Prefer modern C++ in the Jason Turner sense: clear ownership, RAII, const-correct APIs, compile-time checks where useful, no avoidable raw owning pointers, no macro metaprogramming when templates or concepts work, and warnings treated as design feedback. Use C++20 for new code; prefer concepts over SFINAE. Keep the library header-only unless a build-boundary reason exists.

Match existing names: classes use `C...` (`CFeatureTrack`), plain data structs use `S...`, enums use `E...`, and methods use lower camel case (`getTrackLength`). Keep APIs small and explicit. Python code requires Python >= 3.12, complete type hints, dataclasses over ad-hoc dicts, and enums over multi-value literals.

## Testing Guidelines

Use Catch2 for C++ tests. Add tests next to the affected module, naming files `test_<TypeOrFeature>.cpp`, and use descriptive `TEST_CASE` names with tags such as `[feature_sets]`. For wrapper changes, include the relevant CTest target and import-level validation. Prefer focused regression tests before broad integration tests.

## Commit & Pull Request Guidelines

Follow the existing short imperative commit style, optionally with scoped markers such as `[MAJOR]`. Keep commits behaviorally coherent: library API, build system, wrapper, docs, and tests should be separable when practical. Pull requests should describe the behavioral change, list validation commands, note any CMake options touched, and mention wrapper/docs impacts.

## Agent-Specific Instructions

Before context compaction, write the active task state to `CONTEXT.md`. After compaction, reread `AGENTS.md` and `CONTEXT.md` before continuing. Do not overwrite unrelated local changes; this repository often has active work in progress.
