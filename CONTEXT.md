# Current Implementation Context

User request: implement the staged cpp_cuda_template import plan, remove OptiX support, keep slam-primitives tailoring, add docs/CI, improve tests, then perform a final review.

Completed:
- Stage 0 baseline: clean configure/build/ctest passed 65/65 before edits.
- Stage 1 core CMake/version/compiler sync: build-tree VERSION install, source VERSION opt-in only, central compiler flags helper, examples/program options, spdlog off by default.
- Stage 2 dependency/profiling tailoring: profiling defaults off, gperftools/tcmalloc opt-in only, Catch2 handling no longer disables all tests when missing.
- Stage 3 tests/examples/consumer build: consumer example no longer auto-builds parent repo; installed package consumer path validated.
- Stage 4 documentation setup: Doxygen helper, doc target, XML option, tailored main page, clean docs build.
- Stage 5 optional Python wrapper: default OFF; package/import name `slam_primitives`; renamed interface `src/slam_primitives/wrapped/slam_primitives_wrapper.i`; header-only facades for feature tracks, bundles, and covisibility; no checked-in generated wrapper `.cpp`.
- Stage 6 CI: Linux build/test/install/consumer/docs workflow, manual self-hosted CUDA workflow, docs artifact workflow. Stale `.templ*` workflow fragments removed.
- Stage 7 cleanup: stale template wrapper paths and removed backend strings cleaned; unused imported ZeroMQ/profiling scaffold removed.
- Stage 8 tests: direct float equality assertions replaced with `Catch::Approx`; redundant feature-track length tests folded into primary test; added coverage for capacity no-op, bundle slot reuse containment, covisibility missing-frame no-op, and wrapper facade flows.

Validation already run:
- Baseline configure/build/ctest passed 65/65.
- Stage 1 configure passed and no source VERSION was generated.
- Stage 2 configure passed with Eigen-only target dependencies and gperftools/tcmalloc OFF.
- Consumer red/green check verified missing install prefix now fails clearly without auto-building the parent.
- Stage 3 configure/build/ctest/install/consumer build passed; tests passed 65/65.
- Final main verification passed: configure/build, 67/67 CTest tests, install, downstream consumer build, docs target, no source `VERSION`, and default `import slam_primitives` with `HAS_WRAPPER=False`.
- Wrapper-enabled verification passed: configured with `/home/peterc/devDir/dev-tools/wrap`, built `slam-primitives_py`, and CTest `slam-primitives_python_import` passed with concrete Python feature-track/bundle/covisibility flows.
- Docs clean check passed: clean docs configure/build produced HTML/XML and no Doxygen warning/error lines in captured build log.
- Workflow YAML parse passed for `.github/workflows/build_linux.yml`, `build_linux_cuda.yml`, and `docs.yml`.
- Forbidden-surface scan passed for removed backend/template placeholders.

Remaining:
- Current follow-up pass is syncing the missing cpp_cuda_template_project
  v1.10.3 container/devcontainer improvements into the config staging group.
- Imported/tailored: `.devcontainer/Dockerfile`, `.devcontainer/devcontainer.json`,
  `.devcontainer/custom-setup.sh`, `.devcontainer/ros-setup.sh`,
  `.devcontainer/update_devcontainer_json.py`, new `.devcontainer/cuda-setup.sh`,
  updated `configure_devcontainer.sh`, and new `run_in_container.sh`.
- Tailoring preserved: no OptiX/PTX strings in the synced config surface;
  runner examples use slam-primitives build/test commands.
- Fresh validation passed for shell syntax, Python syntax, checked-in JSON,
  updater CUDA-off output, updater CUDA-on/Podman/ROS2-Jazzy output, and a
  temporary `configure_devcontainer.sh --cuda --cuda-version 12.9
  --gpu-runtime podman --base ubuntu-24.04 --ros2 jazzy --ros-profile desktop
  --non-interactive` run.
- Follow-up user request: GPU must not be required by default. The checked-in
  `.devcontainer/devcontainer.json` is now CPU-only, and `run_in_container.sh`
  defaults to CPU-only with explicit `--gpu` opt-in for GPU access and CUDA
  toolkit installation.
- Current staged group: optional Python wrapper only. Staged files are
  `python/.gitignore`, `python/pyproject.toml.in`, `python/setup.py.in`,
  `python/slam_primitives/__init__.py`, deletion of
  `python/template_project/__init__.py`, wrapper facade/interface files under
  `src/slam_primitives/wrapped/`, wrapper tests under `tests/test_wrapped/`,
  and only the `add_subdirectory(wrapped)` / `add_subdirectory(test_wrapped)`
  CMake hookup lines.
- Wrapper validation:
  - `git diff --cached --check` passed.
  - `python3 -m py_compile python/slam_primitives/__init__.py` passed.
  - `PYTHONPATH=python import slam_primitives` reports `HAS_WRAPPER=False`.
  - In an isolated `HEAD + staged patch` temp tree, configured CMake, built
    `test_CSlamPrimitivesPythonWrapper`, and 3 wrapper CTest cases passed.
  - Wrapper-enabled import gate passed using
    `/home/peterc/devDir/dev-tools/wrap_dev` with `GTWRAP_SYNC_TO_MASTER=OFF`:
    built `slam-primitives_py` and passed `slam-primitives_python_import`.
  - `/home/peterc/devDir/dev-tools/wrap` is currently conflicted, so do not use
    it for wrapper validation unless the user resolves that external checkout.
- Follow-up user request added wrapper documentation/comments to the same staged
  group: Python import-contract docstring/comments, Doxygen comments in
  `src/slam_primitives/wrapped/slam_primitives_wrapper_interfaces.h`,
  source-interface comments in `src/slam_primitives/wrapped/slam_primitives.i`,
  and `src/slam_primitives/wrapped/README.md`.
- Wrapper naming was revised so the shared facade is not Python-specific:
  `slam_primitives_wrapper_interfaces.h` for concrete C++ facade classes and
  `slam_primitives.i` for the gtwrap source interface.
- Re-ran validation after the naming/doc changes:
  - `slam_primitives.i` was accepted by gtwrap using `wrap_dev` with sync off,
    generated `python/slam_primitives.cpp`, built `slam-primitives_py`, and
    passed `slam-primitives_python_import`.
  - C++ wrapper target `test_slam_primitives_wrapper_interfaces` built and the
    three wrapper CTest cases passed.
  - Header-only default was verified with wrappers/examples/tests off: configure
    reported `slam-primitives` as an `INTERFACE` library, install exported
    `slam-primitives::slam-primitives INTERFACE IMPORTED`, and a downstream
    consumer compiled/ran against the installed headers.
- Latest wrapper follow-up:
  - Renamed ambiguous covisibility `cleanup` API to
    `clearInactiveFeatures` in `CCovisibilityGraph`,
    `CCovisibilityGraphWrapper`, `slam_primitives.i`, and focused tests.
  - Added wrapper notes documenting the MATLAB caveat: gtwrap can parse and
    generate MATLAB code for the `std::vector` signatures, but the generated
    MATLAB API currently uses `std.vector...` handle classes rather than plain
    MATLAB numeric arrays.
  - Focused validation passed: configured `build-rename-check`, built
    `test_CCovisibilityGraph` and `test_slam_primitives_wrapper_interfaces`,
    ran 17 matching CTest cases, configured/built `slam-primitives_py` with
    `/home/peterc/devDir/dev-tools/wrap_dev`, passed
    `slam-primitives_python_import`, and direct MATLAB wrapper generation
    produced `clearInactiveFeatures` bindings when run with explicit empty
    `--ignore`.
- Wrapper and examples/consumer groups have since been handled by the user.
- Current staged group: CI, documentation configuration, README/docs, and
  agent guidance. Staged files are `.github/workflows/build_linux.yml`,
  `.github/workflows/build_linux_cuda.yml`, `.github/workflows/docs.yml`,
  deletion of stale workflow `.templ0`/`.templ1` fragments, `AGENTS.md`,
  `CLAUDE.md`, `README.md`, `cmake/HandleDoxygenDocs.cmake`,
  `doc/CMakeLists.txt`, `doc/Doxyfile.in`, `doc/build_script_doc.md`, and
  `doc/main_page.md`.
- Container/devcontainer config sync is already in `HEAD` at commit
  `0007208 Sync build config with cpp_cuda_template v1.10.3`; it is not part of
  the current staged group.
- Current CI/docs/agent validation:
  - `git diff --cached --check` passed.
  - Workflow YAML parsed for `build_linux.yml`, `build_linux_cuda.yml`, and
    `docs.yml`.
  - Stale template / removed OptiX backend scan passed over active repo
    surfaces.
  - Default Python package import gate passed after removing ignored generated
    `python/slam_primitives/_wrapper_build.py` metadata left by the earlier
    wrapper build; this was a local build artifact, not a tracked change.
  - Fresh temporary docs build passed with
    `-DENABLE_TESTS=OFF -DENABLE_CUDA=OFF -DENABLE_OPENGL=OFF
    -DBUILD_DOC_XML=ON -DCPU_ENABLE_NATIVE_TUNING=OFF`; generated
    `doc/html/index.html` and `doc/xml`.
- Current unstaged group remains implementation/test cleanup:
  `src/slam_primitives/CMakeLists.txt`, `tests/CMakeLists.txt`,
  `tests/test_bundle/test_CFeatureSetBundle.cpp`,
  `tests/test_covisibility/test_CCovisibilityGraph.cpp`,
  `tests/test_feature_sets/test_CFeatureSet.cpp`,
  `tests/test_feature_sets/test_CFeatureTrack.cpp`, and
  `tests/test_types/test_concepts_and_policies.cpp`.
- Do not commit unless the user asks.
