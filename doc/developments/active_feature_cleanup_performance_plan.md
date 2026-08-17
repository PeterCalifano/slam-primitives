# Active-Feature Cleanup Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure and improve bulk feature cleanup in `slam-primitives`, then provide efficient
removal-oriented primitives for frontends that already know which feature IDs were retired.

**Architecture:** Keep the library header-only and preserve the current keep-list APIs for source
compatibility. Establish allocation and runtime baselines first, optimize their internals second,
then add removal-oriented APIs whose work is proportional to the retired features and their
visibility entries. Validate the result in this repository before any downstream KLT migration.

**Tech Stack:** C++20, Catch2, CMake, ASan/UBSan, Release-mode benchmark probes.

## Global Constraints

- [ ] Make all implementation and behavioral changes in `slam-primitives`; do not prototype
  dependency internals in downstream repositories.
- [ ] Keep `CFeatureSetBundle` and `CCovisibilityGraph` public headers self-contained and
  header-only.
- [ ] Preserve `clearInactive(std::span<const SetID>)` and
  `clearInactiveFeatures(std::span<const SetID>)` for existing consumers.
- [ ] Use Catch2 for correctness and invariant regression tests; do not encode timing thresholds in
  unit tests.
- [ ] Run builds and tests with at most three parallel jobs.
- [ ] Stage each implementation stage separately and do not commit unless explicitly requested.

---

## Stage 1: Reproduce and measure current cleanup costs

**Files:**

- Create: `benchmarks/benchmark_feature_cleanup.cpp`
- Create: `benchmarks/CMakeLists.txt`
- Modify: `CMakeLists.txt`
- Reference: `doc/developments/2026-07-15_implementation_review.md`

- [ ] Add a `slam_primitives_BUILD_BENCHMARKS` option defaulting to `OFF` and an opt-in
  `slam_primitives_feature_cleanup_benchmark` executable, excluded from CTest.
- [ ] Populate bundle cases at 10, 50, and 90 percent occupancy with keep ratios of 0, 50, and
  100 percent.
- [ ] Populate graph cases with 16 and 64 retained frames, each containing 50, 300, and 1000
  feature IDs.
- [ ] Measure `clearInactive()` and `clearInactiveFeatures()` separately after a warm-up, reporting
  median time per call and processed entries rather than enforcing machine-specific pass/fail
  thresholds.
- [ ] Run a 10,000-frame graph case and record peak retained visibility/index entries so reverse
  index growth cannot be mistaken for cleanup cost.
- [ ] Capture allocation counts with a single-threaded, benchmark-local global allocation counter
  enabled only around the measured operation; keep it out of public headers and production targets.
- [ ] Record the compiler, build type, native-tuning setting, fixture sizes, timing summary, and
  allocation counts in this document before changing implementation.

**Gate:** Continue only with costs reproduced from the current implementation. If reverse-index
growth dominates the graph result, correct and remeasure that invariant before comparing cleanup
algorithms.

---

## Stage 2: Optimize compatible keep-list cleanup

**Files:**

- Modify: `src/slam_primitives/bundle/CFeatureSetBundle.h`
- Modify: `src/slam_primitives/covisibility/CCovisibilityGraph.h`
- Test: `tests/test_bundle/test_CFeatureSetBundle.cpp`
- Test: `tests/test_covisibility/test_CCovisibilityGraph.cpp`

- [ ] Add failing tests covering empty keep lists, all-kept input, mixed input, unknown keep IDs,
  duplicate keep IDs, deterministic surviving contents, slot reuse, and graph reverse-index
  consistency after cleanup.
- [ ] Preserve the existing public signatures and invalid-input behavior.
- [ ] Reserve any required lookup storage from the input size and use set semantics rather than
  `std::unordered_map<SetID, bool>`.
- [ ] Remove bundle entries in one iterator-safe pass without collecting a second removal vector or
  repeating `id_to_slot_` lookup through `free()`.
- [ ] Avoid rebuilding graph state that can be updated consistently during pruning; if a complete
  reverse-index rebuild remains necessary, document the invariant that requires it.
- [ ] Run the focused bundle/covisibility tests, the full Catch2 suite, header self-containment
  checks, and ASan/UBSan.
- [ ] Re-run the Stage 1 benchmark matrix and record before/after timing and allocation counts.

**Acceptance:** Identical public behavior, no stale bundle slots or graph index entries, and fewer
temporary allocations in both cleanup paths. Timing is reported rather than asserted.

---

## Stage 3: Add removal-oriented cleanup APIs

**Public interfaces to evaluate and implement:**

```cpp
auto CFeatureSetBundle::clearTerminated() -> std::uint32_t;
auto CCovisibilityGraph::removeFeatures(
    std::span<const SetID> removed_feature_ids) -> std::uint32_t;
```

- [ ] Add failing tests proving `clearTerminated()` frees only terminated tracks, returns the number
  freed, preserves live IDs, and makes released slots reusable.
- [ ] Implement `clearTerminated()` as one iterator-safe traversal without materializing terminated
  IDs.
- [ ] Add failing tests proving `removeFeatures()` accepts empty, unknown, duplicate, and unordered
  IDs; removes each known ID from every retained frame; preserves sorted visibility lists; and
  leaves reverse queries/index state consistent.
- [ ] Implement `removeFeatures()` using the graph's reverse information when that index is retained;
  work must scale with removed visibility entries rather than rebuilding every frame.
- [ ] Keep the existing keep-list APIs as compatibility operations and implement shared internals
  only where doing so does not add another public abstraction.
- [ ] Search the wrapper interface and downstream Python/MATLAB call sites for direct cleanup use.
  Keep both new APIs native-only unless an existing wrapped consumer is found, and record the
  search result explicitly.
- [ ] Run focused, full, sanitizer, header self-containment, and optional wrapper verification.
- [ ] Extend the benchmark matrix with removal batches of 1, 10, 100, and 300 IDs and record where
  removal-oriented cleanup outperforms keep-list pruning.

**Acceptance:** Correct removal is proportional to affected tracks/visibility entries, existing
callers remain source compatible, and the measured crossover point is documented.

---

## Stage 4: Downstream contract verification

- [ ] Build and test `pyramidal-klt-for-space-nav` against the candidate `slam-primitives` install
  without changing its pinned dependency first.
- [ ] Verify tracker retirement, keyframe cleanup, covisibility, Python/MATLAB wrappers, and ROS
  behavior against both old keep-list and new removal-oriented paths.
- [ ] Propose the downstream migration as a separate KLT commit only after the dependency API and
  benchmark evidence have been reviewed in this repository.
- [ ] Document minimum compatible `slam-primitives` version/commit and rollback to the keep-list API
  if downstream performance or invariants regress.
- [ ] Stage the final plan evidence and implementation boundary for review without committing.

## Expected commit split

- [ ] `Benchmark active-feature cleanup`
- [ ] `Optimize keep-list feature cleanup`
- [ ] `[MAJOR] Add removal-oriented feature cleanup`
- [ ] `Document cleanup performance and downstream validation`
