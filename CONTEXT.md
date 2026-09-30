# Current Implementation Context

## Active 2026-09-28 consolidation checkpoint

- User authorized retrospective local version tags and review/staging of the next migration batch. No commit, push, PR, consumer staging, or dependency-pin update is authorized.
- HEAD is `1bb80dee38a2eb7f08fa46c29e8fd8811321afdd` on `feature/extend-visual-features-support`; the header-path batch is now committed. Index initially empty. Remaining task scope is 41 files (27 tracked task paths plus 14 untracked headers/tests/plans); keep this context file unstaged.
- Active checkbox tracking is the September 28 appendix in `doc/developments/2026-09-18_feature_track_rework_and_consumer_migration_plan.md`. Proposed signed local tags: `v0.3.0` at `5e54f81a202b2163317dfe7472804ae2544c25e0`, `v0.4.0` at HEAD. Both tags are now created and SSH signatures verified; neither was pushed.
- Review/stage the independent set/track and typed-ID migration together with Prototype-A, bindings/ROS, tests, examples, and docs. Index contains the 41 task paths. Fresh exported-index checks passed 124/124 CTests (122 native, 2 Python), all 22 installed public headers independently with warnings as errors, and an installed data-core consumer. Jazzy built two packages with zero registered tests; a generated-message maximum-width probe passed. Logs/source/install are under `/tmp/slam-primitives-next-batch-20260928-lo4c0bh3`. Final index tree is `ea8c79d10fc15f75b40444ca3fc692967a95444d`; every tested input matches the exported tree `84df46a3f39170d69f1c2e7f544c767e98380a0f`, with only plan evidence differing. Final whitespace/allowlist checks passed; this file is the sole unstaged path and consumer staged path lists are unchanged.
- Concurrent consumers: main nav-frontend-cpp, pyramidal KLT, loop closures, and the previously approved native GTSAM/backend worktrees. The backend nested GTSAM remains restored and needs integration; its historic 71/71 root test result was from temporary integration. Preserve other repositories' dirty work and indexes.

## Active 2026-09-18 feature-track and consumer migration checkpoint

The current goal is tracked in `doc/developments/2026-09-18_feature_track_rework_and_consumer_migration_plan.md`. This section supersedes the historical task checkpoints below for active work. Preserve unrelated changes and do not commit, push, change pins, or stage unrelated paths.

- Stage 0 baselines were recorded before edits. Slam-primitives passed 116/116 native tests; nav-frontend-cpp 35/35 native and 5/5 ROS tests against legacy slam-primitives; pyramidal KLT 130/130 native and 16/16 ROS tests against legacy slam-primitives; loop closures 126/126 native and 9/9 ROS tests against the candidate install. The two approved GTSAM copies passed 114/114 and 251/251 registered tests, but their untracked benchmark lacked a slam-primitives dependency. Backend had unresolved unregistered triangulation symbols.
- Slam-primitives now has independent `CFeatureSet` and `CFeatureTrack` storage and IDs, a neutral bundle concept, covariance validation, and reverse-index fixes. Its fresh native suite passed 122/122, 15 public headers compiled independently with warnings as errors, an installed consumer ran, generated Python binding CTests passed 2/2, and the final Jazzy overlay built two packages with no registered tests.
- Nav-frontend-cpp native track/frame code and facade/binding vector signatures are migrated; its final native suite passed 36/36, Jazzy passed 5/5, and its generated Python import and exact high-ID/frame round trip passed.
- Pyramidal KLT native tracker/facade/binding paths and ROS messages/conversions now use exact `uint64` track IDs and presence-bearing `uint32` frames. Final native CTest passed 130/130, Jazzy passed 17/17, and its generated Python import and exact high-ID/frame round trip passed.
- Stage 4 GTSAM/backend integration and final regression review are complete. The backend nested GTSAM copy was restored to exact pretask content, preserving its pre-existing 22 untracked files. No staging, commit, push, or pin change was made.
- Stage 3 is now green: nav-frontend-cpp 36/36 native and 5/5 Jazzy; pyramidal KLT 130/130 native and 17/17 Jazzy; loop closures 126/126 native and 9/9 Jazzy. Generated Python modules in both frontends import and round-trip exact `uint64` IDs above `2^53` plus `uint32` max frames. Direct MATLAB wrapper generation succeeded for all three changed interfaces; MATLAB MEX/runtime was not run.
- The backend nested GTSAM geometry integration built completely and passed 137/137 CTests. The backend root built and passed 71/71 after a transient correction of its nested `RelativePositionFactor`, which lagged the already-correct dedicated native worktree. The nested copy has now been restored exactly: all 22 original untracked files match its saved pretask manifest hash, its factor header matches its saved hash, and no tracked nested GTSAM paths are dirty. Backend root build artifacts reflect the transient integrated state, while its restored source requires later integration of the native GTSAM worktree.
- The dedicated native-triangulation GTSAM worktree has the semantic CFrameID and CMake integration while preserving its local untracked geometry/benchmark differences. Its complete build and CTest passed 274/274, including 20 focused geometry tests. DLT/LOST/LOSTU synthetic accepted counts and numeric RMSE match the temporarily integrated backend copy. The detailed plan has all implementation checkboxes complete; seven indexes remain untouched. MATLAB wrapper generation passed, but MEX/runtime did not run.

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

Nav-backend Prototype-A A2.1 checkpoint as of 2026-07-31:

- This repository supplies the shared C++ data core for nav-backend triangulation. Work started from clean base
  `05a9c72be25692c965cf688511ac45107bfd382f` on `feature/update-cmake-ros2-to-v1.11.3`; nothing is staged or committed.
- Added public header-only value types `CFrameId`, `CFeatureTrackId`, `CPinholeCameraCalibration`, `CCameraView`,
  `CImagePointObservation`, and `CFeatureTrackBatch`. Added focused Catch2 files
  `test_StrongIds.cpp`, `test_CameraGeometryTypes.cpp`, and `test_ObservationBatch.cpp`.
- The design deliberately stays direct: explicit checked legacy-ID boundaries, immutable validated camera/calibration
  values, finite symmetric PSD observation uncertainty, and a sorted contiguous owning track batch. No generic
  strong-ID template, covariance framework, or compatibility alias was added.
- TDD evidence: focused suites pass 3/3, 6/6, and 10/10; the full suite passes 98/98; all six public headers compile
  independently under C++20 with `-Wall -Wextra -Wconversion -Werror`.
- Reconfiguring before install correctly installs all six headers into
  `/tmp/slam-primitives-a2-install.cN1CSz`. The first reused configure omitted headers created after configure because
  the existing install glob is evaluated at configure time. Do not add recursive product tests for this; complete a
  disposable installed-package consumer configure/build/run instead.
- The refreshed install and external `find_package(slam-primitives REQUIRED CONFIG)` consumer both pass. The complete
  readability, whitespace, and machine-path scans pass. Source/test manifest SHA-256 is
  `b05aa272a54b32108963c9d2afecd115037be40cfbea0ea032eb7a1ceeeb637e`.
- The review also resolved overflow-prone symmetry validation for finite high-magnitude 2x2/3x3 covariance matrices;
  four red regression cases now pass without adding a shared validation framework.
- Remaining A2.1 handoff is the user-reviewed upstream commit and immutable revision pin, followed by repeating the
  install/consumer gate. Preserve the uncommitted patch and do not commit unless the user asks.

ID-domain and frame-ID migration checkpoint as of 2026-09-17:

- Active goal: keep generic `SetID` and strong `CFeatureTrackID` distinct, move native frame APIs to `CFrameID`, and update binding/ROS widths. The checkbox plan is `doc/developments/2026-09-17_id_domains_and_frame_id_migration_plan.md`; its stages are complete and its supersession note preserves the separate cleanup performance goal.
- The reviewed 32-file migration patch is staged without a commit. `CONTEXT.md` remains unstaged. Six pre-existing Prototype-A camera/observation/batch headers and tests remain untracked and unstaged.
- Review follow-up closed two important gaps: direct `CFrameID` construction now checks negative and overflowing integers, and assignment through a bundle reference cannot change an assigned `CFeatureSet`/track ID. The ID concept also rejects custom strong IDs implicitly convertible from `SetID`. New regression tests failed before each fix and passed afterward.
- Final validation: current ROS-free CTest 115/115; clean staged-only worktree CTest 98/98; generated Python binding import and high-ID/frame CTests 2/2 in both the current and staged-only trees; ten changed public headers compile individually with C++20 and warnings as errors in both trees; Jazzy overlay builds two packages and has zero registered tests; staged-only installed consumer builds and runs with generic and track IDs. Both staged and unstaged whitespace checks pass. MATLAB wrapper generation passed, but MEX/runtime was not tested.
- The temporary staged-only validation worktree was removed after its checks. No commit, tag, or push was made.

Prototype-A data-core consolidation checkpoint as of 2026-09-17:

- The user clarified that the six previously untracked Prototype-A camera, observation, batch, and test files belong with the ID migration. The active checkbox plan is `doc/developments/2026-09-17_prototype_a_data_core_consolidation_plan.md`; the earlier migration-only plan is preserved as a historical checkpoint with a supersession note.
- The combined 39-file patch is staged. `CONTEXT.md` remains modified and unstaged; no untracked files remain. No commit, tag, or push was made.
- A focused calibration regression first failed because a large focal value relaxed the homogeneous-row tolerance. A fixed structural tolerance passed the new case and retained acceptance of roundoff-sized residuals. The batch documentation now states that returned spans borrow storage and invalidate on destruction, move, or assignment.
- Validation on a fresh checkout containing only the staged patch: ROS-free build and CTest 116/116; 14 public headers compile independently under C++20 with warnings as errors; installed package includes all four Prototype-A headers; a separate `find_package` consumer builds/runs with generic set ID, track ID `2^40`, frame ID `2^32-1`, calibration, camera view, image observation, flat batch, and track bundle; generated Python binding CTests 2/2; Jazzy overlay builds two packages and registers zero tests; Doxygen builds without warning/error lines. MATLAB MEX/runtime was not run.
- The disposable staged-only worktree was removed after validation; build, install, and consumer artifacts remain under `/tmp`.

## Shared covisibility runtime window (2026-09-30)

- Current user authorization comes from pyramidal-klt consolidation: implement the graph-owned runtime window here, without a new graph type, mode flag or third template parameter. Earlier task records above are historical; this work started clean on feature/extend-visual-features-support at a3292c41bbaac67733e4793cf6c97757b947f4eb.
- CCircularBuffer now provides pop_front with empty rejection, removed-slot resource release, wraparound/order preservation and subsequent insertion. CCovisibilityGraph retains its two template parameters and defaults to MAX_FRAMES; explicit constructor, setWindowSize and windowSize support1..capacity. Invalid sizes/live duplicate frame IDs reject before mutation/eviction. Shrinking drops oldest frames and rebuilds reverse slots once; growth restores no history. Existing binding facade forwards the API.
- Ten implementation/test/doc/example files changed: buffer/graph headers, facade/gtwrap declarations, native buffer/graph/facade tests, Python roundtrip test, main_page documentation and new example_graph_window.cpp. Everything remains unstaged, including this context update; no commit or push authorized or made. KLT removed its downstream graph subclass and refreshed only its previously authorized Stage1 index.
- Fresh artifact root /tmp/klt-shared-window-xpa3agdj: shared132/132 tests (130Catch2+2Python), installed example/consumer,3 standalone public headers with C++20 warnings as errors and Doxygen pass. MATLAB generation includes constructor/setter/query with uint32; MEX/runtime unrun. Dependent KLT Stage1 index-only121/121 and full Stage1–2 ROS31/31 pass; installed KLT consumer/header and Doxygen pass.
- slam-source.diff and slam-source-manifest.json identify the uncommitted ten-file source patch (context excluded), baselinea3292c4, package0.5.0. Full shared/native/binding/example diff reviewed for correctness, public contracts, lifetimes, comments and simplification; both whitespace checks pass. No Superpowers/subagents used. KLT Stage3–5 remain unstarted; no dataset streaming claim.

## Review and staging follow-up (active, 2026-09-30)

- User now authorizes review and staging in both repositories, including all KLT Stage 1–2 changes. No commit, push, new goal, or Stage 3 implementation is authorized. Read both repositories' AGENTS and KLT CONTRIBUTING; sibling has no CONTRIBUTING. No Superpowers or subagents.
- Concurrent user edits renamed the graph getter to getWindowSize and staged eight shared paths, including CONTEXT.md. Preserve that rename and pre-existing staging. Fixed the remaining Python callers and KLT plan API spelling; native tests/example/docs were already renamed by the user. Keep KLT's ignored CONTEXT outside its index.
- Review corrected file-level C++ test/source documentation, Python class/module documentation, missing direct includes, Allman method bodies and long conversion expressions. No functional defect identified in the graph/buffer, typed result/reference, calibration/profile or ROS schema changes. Camera-profile tests validate sensible settings and dynamic overrides; numerical conversion uses an independent fixture.
- Current staged scope: shared 11 files (ten implementation/test/doc/example files plus user-staged context); KLT 46 files (Stages 1–2 plus full plan/status). Exact path allowlists used. Entire shared index read and KLT functional/source/test/config changes reviewed; complete final index checks still required. No other working source changes remain.
- Fresh index exports/build evidence: /tmp/slam-klt-staged-review-wkw07cwl, slam-source and klt-source. Staged diffs and tree IDs saved. Shared configure/build/install, 132 tests (130 Catch2 plus two generated Python binding checks), Doxygen and example pass. Current native/Python build session65068 and ROS build session77972 running. Need native/Python/ROS tests, installed consumers, standalone headers, MATLAB generation, final records and hash/index integrity.
- Relevant memory used for staging/review scope only: MEMORY.md1068–1070 and rollout_summaries/2026-07-22T13-12-00-BaNz-hyper2_evaluation_functional_staging_and_template_audit.md16–18; rollout ID019f89f4-5a23-7b20-88e1-2cbf211d8a51. Final response must append the prescribed memory citation block. No memory edits.
