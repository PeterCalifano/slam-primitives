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

## Optional ROS 2 Overlay

Read `doc/ros2_overlay.md` before changing the optional ROS 2 integration.
`./build_lib.sh` remains the ROS-free C++ library entry point;
`./build_ros2.sh` is the explicit colcon build and test entry point. Keep ROS
changes confined to `ros2/` and the documented root helpers, metadata tests,
isolation markers, documentation, and ROS overlay workflow.

## CMake Acceptance Policy

Do not keep recursive CMake verifier scripts in the ordinary project test
suite. CTest is for target-owned Catch2 behavior, plus explicitly enabled
Python tests. Validate metadata-only configuration, option matrices,
installation, source packaging, and external consumers through fresh
out-of-tree commands in CI or during the relevant review.

Use disposable consumer projects outside the normal test build when nested or
installed consumption must be proven. Do not import donor
`VerifyTemplateProject*` tests or rename template-conformance tests to make them
look target-owned.

## Template Synchronization

Treat template upgrades as three-way semantic ports: determine the previous
donor state, review the donor delta, and apply only its relevant intent to the
current target. The result is the current `slam-primitives` behavior plus
applicable donor improvements, never a copy of the new donor tree.

The authority order is the current user request, this repository's guidance and
architecture, its public API/tests/packaging contracts, the approved local
upgrade plan, and finally the donor implementation. Preserve target identity,
namespaces, header-only architecture, option defaults, dependency providers,
wrapper APIs, ROS messages, workflow policy, and intentional absences such as
OptiX/PTX. A donor path absent from this repository remains absent unless local
evidence or the user explicitly restores it.

Classify donor changes as adopt, adapt, skip, upstream-first, or blocked.
Record why adapted and skipped functionality differs. Do not replace tailored
files wholesale when a semantic change is possible, and do not copy donor
campaign reports, cleanup utilities, workflow templates, or conformance tests
into this derived repository.

## Coding Style & Naming Conventions

Use `gtsam_spaceNav` as the local C++ reference. Apply Jason Turner's modern C++ practices as a bias adapted to this codebase, not as a wholesale style replacement: clear ownership, RAII, const-correct APIs, compile-time checks where useful, no avoidable raw owning pointers, no macro metaprogramming when templates or concepts work, and warnings treated as design feedback. Use C++20 for new code; prefer concepts over SFINAE. Keep the library header-only unless a build-boundary reason exists.

Make APIs explicit about invariants and lifetime. Prefer value types and references for required inputs, pointers only when null is meaningful, and `std::span`/views for non-owning ranges. Distinguish expected absence, recoverable invalid input, and internal invariant failures: use `std::optional`/typed results for absence, standard exceptions for invalid public input, and side-effect-free assertions only for internal invariants. Follow the Rule of Zero where practical and mark single-argument constructors `explicit`. Mark value-returning query APIs `[[nodiscard]]` when ignoring the result is probably a bug. Use `constexpr`, `noexcept`, and `static_assert` when they express a real contract, not as decoration. Keep headers self-contained and avoid hidden global state, surprising allocation, public macros, and `using namespace` directives in headers.

Match existing names: classes use `C...` (`CFeatureTrack`), plain data structs use `S...`, enums use `E...`, and methods use lower camel case (`getTrackLength`). Keep APIs small and explicit. New or substantially changed C++/CUDA source files require Doxygen file-level documentation and Doxygen on public APIs.

Python code requires Python >= 3.12, complete type hints, dataclasses over ad-hoc dicts, and enums over multi-value literals. Use Google-style module, class, method, and function docstrings for new or substantially changed Python code. Include runnable examples when they materially clarify a public API.

## Testing Guidelines

Use Catch2 for C++ tests. Add tests next to the affected module, naming files `test_<TypeOrFeature>.cpp`, and use descriptive `TEST_CASE` names with tags such as `[feature_sets]`. Every new or changed public header must compile when included by itself, without relying on transitive includes. For wrapper changes, include the relevant CTest target and import-level validation. Prefer focused regression tests before broad integration tests.

Review new code against the same standard: check ownership/lifetime clarity, invariant enforcement, warning cleanliness, header self-sufficiency, wrapper impact, and whether tests cover boundary conditions as well as nominal behavior.

## Portability & Repository Hygiene

Do not add machine-local absolute paths, SDK locations, workspace paths, or
generated artifacts to tracked configuration. Express external tools through
documented CMake variables, environment variables, and package discovery.
Preserve executable file modes, parse XML/JSON/YAML/TOML with format-aware
tools, and keep build/install trees, caches, bytecode, generated wrappers,
generated documentation, ROS output, and IDE state out of source packages and
upgrade comparisons.

Before staging, run `git diff --check`, scan added lines for machine-local
paths, conflict markers, stale donor identifiers, and intentionally removed
features, and distinguish staged from unstaged changes explicitly.

## Commit & Pull Request Guidelines

Follow the existing short imperative commit style, optionally with scoped markers such as `[MAJOR]`. Keep commits behaviorally coherent: library API, build system, wrapper, docs, and tests should be separable when practical. Pull requests should describe the behavioral change, list validation commands, note any CMake options touched, and mention wrapper/docs impacts.

Before handing staged changes to the user, inspect the complete index with
`git diff --cached`. New or substantially changed source files require both
file/module-level documentation and public callable documentation. Organize
non-obvious implementation blocks by immediate purpose, using concise
contract-oriented comments rather than line-by-line narration. Review the
staged result as the reader will receive it and summarize any documentation or
readability cleanup performed. This review does not authorize staging or
committing unrelated work.

## Agent-Specific Instructions

Before context compaction, write the active task state to `CONTEXT.md`. After compaction, reread `AGENTS.md` and `CONTEXT.md` before continuing. Do not overwrite unrelated local changes; this repository often has active work in progress. Do not commit unless explicitly asked.
