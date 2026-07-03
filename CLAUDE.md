# CLAUDE.md

This file provides guidance to Claude Code when working in `slam-primitives`.
Use `AGENTS.md` as the concise contributor guide; this file adds agent-facing implementation context.

## Agent Operating Rules

Before context compaction, write the active task state, decisions, blockers, and verification status to `CONTEXT.md`. After compaction, reread `AGENTS.md` and `CONTEXT.md` before continuing. Do not overwrite unrelated local or staged changes. This repository often has active work in progress.

Use `/home/peterc/devDir/SLAM-repos/gtsam_spaceNav` as the local C++ reference for style and development quality. Prefer modern C++ in the Jason Turner sense: clear ownership, RAII, const-correct APIs, compile-time checks, no avoidable raw owning pointers, no macro metaprogramming when templates or concepts work, and warnings treated as design feedback.

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

Python code requires Python >= 3.12, complete type hints, dataclasses instead of ad-hoc dicts, and enums instead of multi-value literals. New public classes or functions should include a runnable example with expected output when practical.

## Testing Guidance

Tests use Catch2 and mirror module layout under `tests/test_*`. Add focused tests near the affected component, naming files `test_<TypeOrFeature>.cpp`. Use descriptive `TEST_CASE` names and tags such as `[feature_sets]`. For wrapper changes, include CTest coverage plus import-level validation. Prefer a narrow regression test before broad integration coverage.

## Commit and PR Guidance

Do not commit unless explicitly asked. Existing history uses short imperative messages, sometimes with scoped markers such as `[MAJOR]`. Keep proposed commits behaviorally coherent: API/library, build system, wrapper, docs, and tests should be separable when practical. PR summaries should list behavior changes, validation commands, touched CMake options, and wrapper/docs impacts.
