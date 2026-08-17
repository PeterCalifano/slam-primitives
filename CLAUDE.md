# CLAUDE.md

This file provides guidance to Claude Code when working in `slam-primitives`.
Use `AGENTS.md` as the concise contributor guide; this file adds agent-facing implementation context.

## Agent Operating Rules

Before context compaction, write the active task state, decisions, blockers, and verification status to `CONTEXT.md`. After compaction, reread `AGENTS.md` and `CONTEXT.md` before continuing. Do not overwrite unrelated local or staged changes. This repository often has active work in progress.

Use `/home/peterc/devDir/SLAM-repos/gtsam_spaceNav` as the local C++ reference for style and development quality. Apply Jason Turner's modern C++ practices as a bias adapted to the existing APIs, not as a wholesale style replacement: clear ownership, RAII, const-correct APIs, compile-time checks, no avoidable raw owning pointers, no macro metaprogramming when templates or concepts work, and warnings treated as design feedback.

## Project Overview

`slam-primitives` is a header-only C++20 library for Visual-SLAM frontend primitives. It provides fixed-capacity keypoint storage, temporal feature tracks, bundle allocation, circular buffers, and sliding-window covisibility analysis. Eigen3 is required. CUDA 12+, OpenGL, oneTBB, OpenMP, Doxygen, and gtwrap/Python bindings are optional build surfaces.

## Build and Test Commands

```bash
./build_lib.sh
./build_lib.sh -t debug -j 8
./build_lib.sh -N -i
./build_lib.sh --clean
./build_lib.sh -D ENABLE_CUDA=ON
```

Manual CMake flow:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Build docs when configured:

```bash
cmake --build build --target doc
```

Use `-DCPU_ENABLE_NATIVE_TUNING=OFF` for portable CI or redistributable binaries.

## Architecture

Public headers live under `src/slam_primitives/`:

- `types/`: type aliases, concepts, labeling policies, `SFeatureLocation2D`, `ESetType`, LiDAR metadata.
- `containers/`: fixed-capacity `CCircularBuffer`.
- `feature_sets/`: `CFeatureSet` and `CFeatureTrack`.
- `bundle/`: `CFeatureSetBundle` pool allocation and SetID lookup.
- `covisibility/`: `CCovisibilityGraph` sliding-window graph utilities.
- `wrapped/`: optional gtwrap/Python facade and interface files.

The library target is an INTERFACE CMake target. Keep new core code header-only unless a real build-boundary reason exists. Examples and downstream consumer checks live in `examples/`. Doxygen sources live in `doc/`. Python package templates live in `python/` and import as `slam_primitives`.

## Coding Conventions

Use C++20 for new code. Prefer concepts over SFINAE, explicit APIs over clever inference, and compile-time capacity templates where that matches existing containers. Match existing names: classes use `C...`, plain data types use `S...`, enums use `E...`, and methods use lower camel case such as `getTrackLength`.

The C++ quality bar is concrete:

- Make ownership and lifetimes obvious at the call site. Prefer value semantics and references for required inputs, pointers only when null is meaningful, and `std::span` or other views for non-owning ranges. Do not introduce raw owning pointers.
- Follow the Rule of Zero where practical. If a type owns a resource, make copy and move behavior explicit; mark single-argument constructors `explicit`.
- Express invariants in the type system when practical. Use concepts, `static_assert`, constrained templates, fixed-capacity types, and strongly typed IDs instead of comments or sentinel values.
- Distinguish expected absence, recoverable invalid input, and internal invariant failures. Use optional or typed results for absence, standard exceptions for invalid public input, and assertions only for side-effect-free internal checks that may disappear in release builds.
- Keep public headers self-contained, deterministic, and low-surprise. Avoid hidden global state, public macros, `using namespace` directives, non-local side effects, and unnecessary dynamic allocation.
- Use `[[nodiscard]]` for value-returning queries where ignoring the result is likely a bug. Use `constexpr` and `noexcept` when they document and enforce a real contract.
- Prefer standard algorithms, ranges, and small named functions over clever loops or duplicated logic, while keeping direct loops when they are clearer for fixed-capacity or numeric code. Optimize only with evidence and keep performance assumptions documented.
- Treat warnings, sanitizer findings, and static-analysis feedback as design signals. Fix the contract when possible instead of suppressing the symptom. Static analysis remains an optional recommendation unless the repository configures it as a gate.

Python code requires Python >= 3.12, complete type hints, dataclasses instead of ad-hoc dicts, and enums instead of multi-value literals. New public classes or functions should include a runnable example with expected output when practical.

## Testing Guidance

Tests use Catch2 and mirror module layout under `tests/test_*`. Add focused tests near the affected component, naming files `test_<TypeOrFeature>.cpp`. Use descriptive `TEST_CASE` names and tags such as `[feature_sets]`. For wrapper changes, include CTest coverage plus import-level validation. Prefer a narrow regression test before broad integration coverage.

For C++ API changes, cover nominal behavior, boundary capacity, invalid input, ordering/lookup contracts, and compile-time constraints where applicable. Every new or changed public header must also compile in a minimal translation unit that includes that header first and by itself; a wrapper-facing change should additionally prove import-level behavior.

## Review Checklist

When reviewing this repository, lead with bugs or regressions first. Score importance from 1 (optional polish) to 5 (correctness, safety, or ABI blocker). Score confidence as High for reproduced or directly proven findings, Medium for strong static evidence with an unconfirmed runtime path, and Low for hypotheses requiring design clarification. Use this checklist:

- API contract: Are ownership, lifetime, absence, invalid input, and capacity limits explicit?
- Invariants: Are constraints enforced by types, concepts, `static_assert`, or clear runtime checks?
- Header hygiene: Can each public header compile on its own with required includes only?
- Build hygiene: Are warnings enabled and clean for the supported compilers and optional surfaces?
- Test coverage: Do tests include boundary, invalid, and wrapper/import behavior, not only nominal paths?
- Maintainability: Is the implementation small, named, local, and consistent with `gtsam_spaceNav` style?

## Commit and PR Guidance

Do not commit unless explicitly asked. Existing history uses short imperative messages, sometimes with scoped markers such as `[MAJOR]`. Keep proposed commits behaviorally coherent: API/library, build system, wrapper, docs, and tests should be separable when practical. PR summaries should list behavior changes, validation commands, touched CMake options, and wrapper/docs impacts.
