# slam-primitives — Implementation, Interface, and Performance Review

- **Date:** 2026-07-15
- **Branch:** `perf/review-impl-best-practices` (HEAD `24d6b92`, plus unstaged `AGENTS.md`/`CLAUDE.md` guideline updates)
- **Scope:** all public headers under `src/slam_primitives/`, `src/global_includes.h`, wrapper facade, tests, CMake build surface, and conformance against the updated coding guidelines in `AGENTS.md`/`CLAUDE.md`.
- **Method:** static review of every header and test, plus empirical verification: suspected defects were compiled into minimal probe programs against the headers (GCC, `-std=c++20 -Wall -Wextra`, and `-O2 -DNDEBUG` for timing) and executed. Findings marked **Confidence: High (reproduced)** were confirmed by running code, not just by reading it.
- **Scoring:** per the repository review checklist — importance 1 (polish) to 5 (correctness/safety blocker); confidence High / Medium / Low.

No source files were modified. Probe sources are reproduced in the Appendix so results can be re-derived.

---

## 1. Findings summary

| # | Component | Finding | Importance | Confidence |
|---|-----------|---------|:---:|:---:|
| B1 | `CCovisibilityGraph` | Reverse index stores stale logical slots → unbounded memory growth and superlinear per-frame cost in the nominal loop | **5** | High (reproduced) |
| B2 | `CCovisibilityGraph` | `addVisibilityLinks` inserts duplicate reverse-index entries for repeated (frame, feature) links | 3 | High (reproduced) |
| B3 | `CFeatureTrack` | Public inheritance exposes `CFeatureSet::addKeypoint`, silently desynchronizing keypoints from frame IDs → wrong keypoint↔frame association | **4** | High (reproduced) |
| B4 | `CCircularBuffer` | `front()`, `back()`, `operator[]` have unchecked preconditions; empty/oversized access returns valid-looking garbage | 3 | High |
| B5 | `CFeatureSet` | `addKeypoint` return value cannot distinguish "stored, now full" from "silently dropped" | 3 | High |
| B6 | `CFeatureSetBundle` | Non-deterministic iteration order in `forEachActive`/`getTerminatedIDs` (unordered_map) | 3 | High |
| B7 | `CFeatureSetBundle` | Partial state mutation if `id_to_slot_` insertion throws mid-`allocate` | 2 | Medium |
| B8 | `CFeatureSetBundle` | `SetID` (`uint32_t`) wraps after 2³² allocations → ID collision with still-active entries | 2 | Medium |
| B9 | `CCircularBuffer` et al. | No `static_assert(N > 0)`: zero-capacity instantiation compiles and hits `% 0` UB at runtime | 2 | High |
| B10 | `CCovisibilityGraph` | Duplicate `FrameID` in window is representable; queries silently bind to the older duplicate | 2 | Medium |
| D1 | `global_includes.h` | Installed public header violates every header-hygiene rule (collision-prone macros, global `using`, globals) | 3 | High |
| D2 | `labeling_policies.h` | `SLabelingEnabled<MAX_LENGTH>` ↔ track capacity match is a comment-only invariant | 2 | High |
| D3 | library-wide | `[[nodiscard]]`, `noexcept`, `constexpr` absent from query APIs, contradicting the new guidelines | 2 | High |
| D4 | `CCircularBuffer` | Iterator advertises `forward_iterator_tag` but does not model `std::forward_iterator`; const-only iteration | 2 | High |
| D5 | build | Header self-containment rule not enforced by any build target | 2 | High |
| D6 | build | Directory-scope `include_directories`, source `file(GLOB)`, global `-Werror` flag mutation | 2 | High |
| P1–P6 | hot paths | See §5 — measured and static bottlenecks with a screening plan | 2–4 | — |

---

## 2. Bugs and regressions (lead findings)

### B1 — Covisibility reverse index rots after window wrap-around; nominal loop leaks memory and degrades superlinearly

**Importance 5 · Confidence High (reproduced)**

`CCovisibilityGraph::addVisibilityLinks` records the frame's *logical* ring-buffer index into the reverse index (`CCovisibilityGraph.h:89`):

```cpp
feature_to_frame_slots_[fid].push_back(*slot);
```

But logical indices into `CCircularBuffer` shift down by one on every eviction. Eviction (`pushFrame` → `removeFrameFromIndex(0)`, `CCovisibilityGraph.h:49-60,200-216`) erases the *value* `0` from each feature's slot list — while links added to the newest frame of a full window were recorded as `MAX_FRAMES - 1`. **The erase never matches anything, so no reverse-index entry is ever removed.**

Consequences in the *nominal* per-frame usage (`pushFrame` → `addVisibilityLinks`, repeated beyond `MAX_FRAMES` frames):

1. **Unbounded memory growth.** The index should hold at most `MAX_FRAMES × features_per_frame` entries; it instead grows by one entry per feature per frame forever.
2. **Superlinear CPU degradation.** Each eviction runs `std::erase` over each feature's ever-growing slot vector, so per-frame cost grows with total mission length.
3. **Semantic corruption.** Even before the leak dominates, surviving entries are stale (probe: after one eviction the index reads `[1 2 2]` where ground truth is `[0 1 2]` — wrong values *and* a duplicate).

Measured (GCC `-O2`, window 64, 300 features/frame — Appendix probe 3):

| Frames processed | Per-frame cost | Index entries (correct cap: 19,200) |
|---|---|---|
| 0–2,000 | 65 µs | 599,700 |
| 4,000–6,000 | 241 µs | 1,799,700 |
| 8,000–10,000 | 1,983 µs | 2,999,700 |
| 10,000–12,000 | **3,981 µs** | 3,599,700 |

At 30 fps this frontend exceeds its real-time budget within a few minutes of operation. Today no public query reads `feature_to_frame_slots_` (the class docstring at `CCovisibilityGraph.h:20` promises a reverse-index query that does not exist), so results of `getVisibleFeatures`/`getCovisibleFeatures` remain correct — the failure mode is resource exhaustion, not wrong answers.

**Recommended fix (pick one):**
- **Simplest:** delete `feature_to_frame_slots_` entirely. It is write-only — maintained but never queried. Reintroduce it only when a `getFramesForFeature()` query lands (YAGNI; also removes `removeFrameFromIndex`).
- If the reverse query is wanted now: key the index by **`FrameID`**, not by slot (`unordered_map<SetID, small vector of FrameID>`), and erase by the evicted frame's ID. `FrameID` is stable; logical slots are not.
- Either way, `clearInactiveFeatures` (`CCovisibilityGraph.h:151-174`) stops being the only thing that heals the index.

**Regression test to add:** push `3 × MAX_FRAMES` frames with links and assert an exposed index-size invariant (or, minimally, assert per-frame timing/memory via a bounded-entries accessor). The existing wrap-around test (`test_CCovisibilityGraph.cpp:78`) never combines eviction *with* links present in the evicted frame plus continued operation, which is why this survived 65+ passing tests.

### B2 — `addVisibilityLinks` duplicates reverse-index entries

**Importance 3 · Confidence High (reproduced)** — subsumed by B1's fix, listed separately because it is a distinct defect.

At `CCovisibilityGraph.h:81-90` the sorted-insert into `visible_features` correctly skips duplicates, but the reverse-index `push_back` runs **unconditionally**. Re-linking the same feature to the same frame (legitimate in re-detection flows) appends a duplicate slot entry each time. Probe result: two identical calls yield `feature 5 -> slots [0 0]`. Fix: move the index update inside the "actually inserted" branch.

### B3 — `CFeatureTrack` publicly inherits `addKeypoint`, breaking the keypoint↔frame invariant

**Importance 4 · Confidence High (reproduced)**

`CFeatureTrack : public CFeatureSet` (`CFeatureTrack.h:26`) leaves the base's `addKeypoint()` callable on a track. It advances the base's `pointer_to_next_` without touching `frame_ids_`/`track_length_`. Probe result:

```
t.addKeypoint({1,2});               // compiles, looks legitimate
t.addKeypointToTrack({3,4}, 100);   // proper API
t.getKeypointAtFrame(100)  ==> (1, 2)   // WRONG keypoint for frame 100
size() == 2, getTrackLength() == 1      // silent desync
```

A keypoint↔frame misassociation is precisely the class of silent data corruption a SLAM frontend must structurally exclude, and the type system currently invites it. Note `getKeypointAtFrame` (`CFeatureTrack.h:82-92`) reads `keypoints_[i]` indexed by *track* bookkeeping while writes are indexed by *base* bookkeeping — the two counters are assumed to be locked together, but nothing enforces it.

**Recommended fix:** private inheritance (re-exposing `getKeypoint`, `getKeypoints`, `getID`, `setID`, `size`, `capacity`, `isInitialized` via `using` declarations) or composition. Public inheritance is also semantically wrong here (a track is not substitutable for a set — it already shadows `isTerminated` non-virtually). Alternatively make `addKeypoint` `protected` in a track-facing base. Add a compile-time regression: `static_assert(!requires(CFeatureTrack<...> t, LocT k) { t.addKeypoint(k); });`

### B4 — `CCircularBuffer` unchecked preconditions on `front()`/`back()`/`operator[]`

**Importance 3 · Confidence High**

- `front()`/`back()` on an empty buffer (`CCircularBuffer.h:47-60`) return `data_[0]`-ish default-constructed elements — no UB (array is in-bounds), but silently wrong, and indistinguishable from real data.
- `operator[](index)` (`CCircularBuffer.h:36-44`) wraps `index % N`, so `buf[size_]`…`buf[N-1]` and any larger index return stale or wrapped elements instead of failing.
- `<stdexcept>` is included (line 4) but never used — the header's own include list suggests a checked contract that was never written.

Per the new guidelines, distinguish the three failure classes explicitly: either document narrow contracts and add side-effect-free `assert`s (internal-invariant style), or throw `std::out_of_range` like `CFeatureSet::getKeypoint` already does. The current mix (checked `CFeatureSet::getKeypoint`, unchecked `CCircularBuffer::operator[]`) is inconsistent across the same library. Tests never cover empty-buffer `front()`/`back()` or out-of-range `operator[]` — add boundary tests once the contract is chosen.

### B5 — `CFeatureSet::addKeypoint` conflates "stored" with "dropped"

**Importance 3 · Confidence High**

`addKeypoint` (`CFeatureSet.h:39-54`) returns `true` both when the keypoint was stored and capacity was reached, and when the keypoint was **silently discarded** because the set was already full. A caller cannot detect data loss. Same shape in `CFeatureTrack::addKeypointToTrack` (returns "terminated", not "accepted"). Consider an enum result (`EAddResult{ADDED, ADDED_NOW_FULL, REJECTED_FULL}`) or a `bool wasAdded` + separate `isFull()` query, and `[[nodiscard]]` on it. This is an API-contract fix; wrapper facades forward the same ambiguity to Python/MATLAB.

### B6 — Non-deterministic iteration order in bundle bulk operations

**Importance 3 · Confidence High**

`forEachActive`, `getTerminatedIDs`, and `clearInactive` iterate `std::unordered_map` (`CFeatureSetBundle.h:138-163,185`), so visit order varies across runs/builds. The guidelines require public headers to be "deterministic, low-surprise"; for SLAM pipelines, run-to-run reproducibility is usually a hard requirement (the wrapper facade already compensates by sorting — `slam_primitives_wrapper_interfaces.h:283,293` — which is a hint the core contract is wrong). Options: iterate `occupied_` slots in index order (cheap, deterministic), or document the non-guarantee loudly. Note `getTerminatedIDs` order additionally feeds test fragility (`test_CFeatureSetBundle.cpp:88-97` already has to use `std::find`).

### B7 — Exception-safety hole in `CFeatureSetBundle::allocate`

**Importance 2 · Confidence Medium (strong static evidence, unlikely runtime path)**

In `allocate` (`CFeatureSetBundle.h:40-59`): `occupied_.set(slot)` happens before `id_to_slot_[id] = slot`; if the map insertion throws (`bad_alloc`), the bit stays set with no owning map entry → the slot leaks permanently and `active_count_` diverges. Also `next_id_` is consumed and the caller's `set` is moved-from even on failure. Reorder (map insert first, or use strong-guarantee sequencing) or document the basic guarantee. Related: `active_count_` (`CFeatureSetBundle.h:218`) duplicates `id_to_slot_.size()` — redundant state that can only ever disagree; consider deleting the counter.

### B8 — `SetID` wrap-around on long missions

**Importance 2 · Confidence Medium**

`next_id_++` (`CFeatureSetBundle.h:43`) wraps at 2³². At high feature churn (e.g., 1,000 new tracks/frame @ 30 fps ≈ 40 h) a wrapped ID collides with a still-active key: `id_to_slot_[id] = slot` overwrites the existing mapping, orphaning the old slot (occupied bit never freed) and corrupting `active_count_`. For spaceflight-length missions this is reachable. Cheap mitigations: `uint64_t SetID`, or explicit overflow check throwing `std::runtime_error`, or documented mission-profile bound.

### B9 — Zero-capacity instantiations compile and are UB at runtime

**Importance 2 · Confidence High**

`CCircularBuffer<T, 0>` compiles; first `push_back` evaluates `% 0` → UB. Same missing guard in `CFeatureSet<L, 0>` / `CFeatureTrack<L, 0>` (writes to `std::array<T,0>`). One-line fix each, per the "express invariants in the type system" rule: `static_assert(N > 0, "...")`.

### B10 — Duplicate `FrameID`s in the covisibility window

**Importance 2 · Confidence Medium**

`pushFrame` never checks whether the ID is already present; `findFrameSlot` (`CCovisibilityGraph.h:186-196`) then resolves all queries/links to the *older* duplicate. Negative IDs (docs say "reserved for invalid" — `type_aliases.h:8`, and `SFrameEntry.frame_id{-1}` uses −1 as sentinel) are also accepted, so a caller pushing `-1` collides with the sentinel. Either reject duplicates/negatives (`std::invalid_argument`) or document last-write-wins semantics and make the sentinel a named constant.

---

## 3. Design gaps and improvements

### D1 — `global_includes.h` violates the project's own header rules and is installed

`src/global_includes.h` defines unprefixed, collision-prone **public macros** (`RED`, `GREEN`, `RESET`, …), a global-namespace `using std::scientific`, and global-namespace consts (`prec`, `EPS_DOUBLE`) — everything the "Keep public headers self-contained… avoid public macros" rule forbids. Nothing in the library includes it, yet `src/CMakeLists.txt:137-138` **installs it into the public include tree**, where `#define RED` will fight with downstream code (ncurses, other loggers). Recommendation: stop installing it; if the ANSI helpers are wanted, move them into `namespace slam_primitives::term` as `inline constexpr std::string_view` values. Importance 3, High confidence.

### D2 — Labeling policy capacity match is enforced only by a comment

`SLabelingEnabled<MAX_LENGTH>` documents "must match the owning CFeatureTrack" (`labeling_policies.h:20`) but `CFeatureTrack<Loc, 8, SLabelingEnabled<4>>` compiles fine and invites out-of-bounds writes into `labeled_keypoints`. Give the policy a `static constexpr uint32_t extent` and `static_assert` in `CFeatureTrack` that `!has_labeling || extent == MAX_LENGTH`. Also consider `<Eigen/Core>` instead of `<Eigen/Dense>` there (see P6).

### D3 — Contract annotations are systematically missing

The updated guidelines call for `[[nodiscard]]` on value-returning queries and `noexcept`/`constexpr` where they express a contract. Currently **zero** occurrences in the library: `getKeypoint`, `getKeypoints`, `size`, `capacity`, `contains`, `activeCount`, `getTerminatedIDs`, `getCovisibleFeatures`, `allocate` (ignoring the returned `SetID` orphans the entry!) etc. are all unannotated. Most accessors are trivially `noexcept`; `capacity()` is already `constexpr`, `size()` could be. Suggest one sweep, prioritizing `allocate`, `addKeypoint*`, and all `get*`. Importance 2 (ratchet, not regression), High confidence.

### D4 — `CCircularBuffer::Iterator` mislabels its category and is const-only

It advertises `std::forward_iterator_tag` (`CCircularBuffer.h:80`) but is not default-constructible, so it fails `std::forward_iterator`/`std::ranges` requirements; there is also no mutable iteration and no `cbegin/cend`. Add a defaulted constructor, `static_assert(std::forward_iterator<Iterator>)` in tests, and (optionally) random-access support — the container is O(1)-indexable, and `std::ranges` algorithms would benefit. Naming nit: it's a `const_iterator` in behavior.

### D5 — Header self-containment is a stated gate with no enforcement

The new testing rule ("every new or changed public header must compile in a minimal TU that includes it first and by itself") has no build machinery behind it. Existing tests happen to include headers first, but nothing guards e.g. a future header that leans on a transitive include. Cheap enforcement: a `header_selfcheck` target that generates one `#include "<header>"`-only TU per public header (CMake `foreach` + `file(WRITE)`), compiled with the library's warning set. This also operationalizes the review-checklist "Header hygiene" line.

### D6 — Build-system hygiene (legacy patterns from the template)

- `include_directories(lib/header_only)` at directory scope (`CMakeLists.txt:323`) leaks includes into every target; prefer `target_include_directories` on the interface target.
- `WARNINGS_ARE_ERRORS` appends `-Werror` to global `CMAKE_CXX_FLAGS` (`CMakeLists.txt:224-227`) rather than the compile-interface target — it therefore also hardens fetched third-party code (Catch2) and can break CI on toolchain bumps.
- `file(GLOB)` source discovery (`src/CMakeLists.txt:7-8`, module CMakeLists) is order/reconfigure-fragile; explicit lists are the documented CMake recommendation. Low urgency for a header-only tree, but the pattern will bite when the first `.cpp`/`.cu` appears (it silently flips the target from `INTERFACE` to `SHARED`, an ABI-relevant change — worth an explicit opt-in rather than a glob side effect).
- Positive notes: central `HandleCompilerFlags` with `-Wall -Wextra -Wconversion -Wnull-dereference -Wfloat-equal`, sanitizer plumbing (`SANITIZE_BUILD`, ASan/UBSan/LSan), profiling hooks, and native-tuning opt-out are all in good shape and match the "warnings as design feedback" bar.

### D7 — Smaller items (importance 1–2)

- **Concept/alias drift:** `FeatureSetLike` spells `uint32_t` where `SetID` is meant (`concepts.h:28-30`); `CFeatureSet::setID/getID` likewise. Purely cosmetic today, but it undercuts the "strongly typed IDs" direction; a real `struct SetID { uint32_t value; }` would prevent passing a raw index where an ID belongs.
- **`is_initialized_` is a soft sentinel** (`CFeatureSet.h:98,110`): default-constructed sets report ID 0, indistinguishable from a legitimate ID 0 (bundle IDs start at 1 — an implicit, undocumented dependency). Consider `std::optional<SetID>`-style semantics or documenting that 0 is reserved.
- **`free()` leaves the stale object in its slot** (`CFeatureSetBundle.h:69-79`): fine for the current POD-array payloads, but if `SetT` ever owns heap memory the pool will pin it until slot reuse. Document, or assign `SetT{}` on free.
- **Facade naming:** local variables with trailing underscores (`frame_ids_`, `keypoint_`, `ids_` in `slam_primitives_wrapper_interfaces.h` and `test_slam_primitives_wrapper_interfaces.cpp`) read as member names; reserve the suffix for members.
- **Docstring drift:** `CCovisibilityGraph` promises a reverse-index query that doesn't exist (see B1); `CFeatureSet::addKeypoint` doc says "returns true when the set reaches capacity" but it also returns true on rejected adds (B5).

---

## 4. Conformance to the updated guidelines (AGENTS.md / CLAUDE.md, pending diff)

The revised guidelines are internally consistent and the diff's refinements (absence vs. invalid input vs. invariant taxonomy; Rule of Zero; `explicit`; header standalone-compile gate; importance/confidence rubric) are good. Assessment of the code against them:

**Already met:** Rule of Zero throughout; `explicit` single-argument constructors (`CFeatureSet.h:32`, facade constructors); `std::optional` for expected absence (`getKeypointAtFrame`, `getLidar`); standard exceptions for invalid public input in `CFeatureSetBundle` and `CFeatureSet::getKeypoint`; `std::span` views for non-owning ranges; concepts over SFINAE with negative `static_assert` tests; no owning raw pointers anywhere; fixed-capacity compile-time templates; EBO via `[[no_unique_address]]` with a size test.

**Not yet met (tracked above):** invariants enforceable by the type system left to comments (B3, D2, B9); `[[nodiscard]]`/`noexcept` absent (D3); determinism (B6); header hygiene of `global_includes.h` (D1); self-containment enforcement (D5); "distinguish absence / invalid input / invariant failure" not applied to `CCircularBuffer` (B4).

Suggestion: treat the new guidelines as a ratchet — apply them mechanically in one focused PR (annotations + static_asserts + hygiene), separate from the behavioral fixes B1–B3.

---

## 5. Hot paths and bottlenecks

Presumed per-frame pipeline: detect → `bundle.allocate` new tracks → `addObservation` per tracked feature → `pushFrame` + `addVisibilityLinks` → `getTerminatedIDs`/`clearInactive*`. Numbers below from a single-run `-O2` wall-clock probe (Appendix probe 4) — indicative, not rigorous.

### Measured

| Path | Measurement | Reading |
|---|---|---|
| P1 `findFreeSlot` linear bitset scan (`CFeatureSetBundle.h:201-212`) | alloc/free cycle at slot 499/512: **380 ns** vs. 38 ns at slot 0 | 10× penalty at high occupancy; O(MAX_SLOTS) per allocation. Replace with a free-list (`std::vector<uint32_t>` stack, O(1)) or word-wise scan (`std::countr_one` over 64-bit words). At hundreds of new tracks/frame this is sub-ms but pure waste. |
| P2 `clearInactive` (`CFeatureSetBundle.h:174-197`) | 400 kept / 0 removed: **9.8 µs/call** | Three avoidable costs: `unordered_map<SetID,bool>` used as a set (use `unordered_set` or, better, a sorted-span merge), a temporary `to_remove` vector, and `free(id)` re-doing the map `find` per removal. Single-pass over `id_to_slot_` with iterator-erase halves the lookups. |
| P3 `addVisibilityLinks` + B1 leak | 65 µs/frame (early) → **3,981 µs/frame** by frame 12k | Dominated by the B1 defect; must be re-benchmarked after the fix. Healthy-path costs: sorted-insert into `std::vector` is O(k) per insert worst case (O(k²) per batch of k unsorted features); with sorted input inserts hit the tail (cheap). If callers can guarantee sorted, unique input, take that as a documented precondition and `std::ranges::merge`; otherwise copy-sort-unique once per call. |
| P4 `clearInactiveFeatures` (`CCovisibilityGraph.h:151-174`) | 64 frames × 300 features: **140 µs/call** | Full erase + index rebuild each call; the map-as-set pattern again. Fine if called rarely; if per-frame, use `unordered_set` and skip the rebuild entirely once B1's fix removes/re-keys the index. |

### Static (screen via benchmarks before optimizing)

- **P5 Allocation churn per frame.** `SFrameEntry.visible_features` is a fresh empty `std::vector` each `pushFrame`; growth to ~300 entries costs ~8–9 reallocations per frame, and the evicted frame's capacity is thrown away (move-assign in `CCircularBuffer::push_back` replaces the old vector). Mitigations: `reserve()` in `addVisibilityLinks`, or recycle the evicted entry's storage (clear-and-swap instead of replace). Similarly, `getTerminatedIDs`, `getCovisibleFeatures`, and every wrapper `toVector` allocate per call — acceptable at Python-boundary frequency, worth an output-parameter overload on the native hot path.
- **P6 Compile-time and object-size.** `labeling_policies.h` includes `<Eigen/Dense>` for one `Vector3d`; `<Eigen/Core>` suffices and meaningfully cuts per-TU parse cost for every consumer of `CFeatureTrack`. Also note `CFeatureTrack<SFeatureLocation2D,128>` is ≈2.6 KB by value: `bundle.allocate(std::move(track))` *copies* that (moving `std::array` copies elements), and `getTrackCopy` copies it twice (native → facade → binding). Fine at current scales; document the value-semantics cost so nobody puts it in an inner loop.
- **P7 `CCircularBuffer` indexing.** `(start_ + index) % N` on every access, including once per iterator dereference. For power-of-two N the compiler reduces it to a mask; for other N a conditional subtract is cheaper. Only worth touching with profile evidence — flagged for the benchmark list, not for immediate change.
- **P8 `findFrameSlot` linear scan** (`CCovisibilityGraph.h:186-196`) — O(MAX_FRAMES) per query, ×2 in `getCovisibleFeatures`. At 64 frames this is trivial; becomes relevant only if MAX_FRAMES grows or queries become per-feature. A `FrameID → slot` map is the fix if profiling ever says so.

### Recommended screening plan

1. **Fix B1 first** — all covisibility timing below frame ~64 is contaminated by the leak.
2. **Timing tests:** add a `benchmarks/` target (Catch2 `BENCHMARK` or google-benchmark, Release + `CPU_ENABLE_NATIVE_TUNING=OFF` for comparability) covering: bundle allocate/free at 10/50/90/99% occupancy (P1); `clearInactive` at varying keep-ratios (P2); `addVisibilityLinks` sorted vs. shuffled × {50, 300, 1000} features (P3/P5); `getCovisibleFeatures` (P8); circular-buffer push/index/iterate (P7). Track results in-repo so regressions are diffable.
3. **Valgrind:** `valgrind --tool=massif` on a 10k-frame pipeline sim — this is the regression harness for B1-class leaks (the current test suite cannot see them). `--tool=callgrind` + kcachegrind on the same sim to rank P1–P8 by inclusive cost before optimizing any of them. `--tool=cachegrind` only if the circular-buffer modulo question (P7) survives callgrind.
4. **Sanitizers:** the build already has `SANITIZE_BUILD=ON` (ASan+UBSan+LSan) — wire it into CI at least weekly; UBSan would catch B9-style `% 0` immediately, ASan the out-of-bounds writes a D2 mismatch enables.
5. **Determinism check:** run the pipeline sim twice with different `ASLR`/hash seeds and diff outputs — catches B6-class ordering dependencies cheaply.

---

## 6. Test-coverage gaps (beyond per-finding notes)

Current suite (931 lines, 8 files) is strong on nominal + simple boundary behavior. Missing classes of coverage:

- **Cross-invariant tests:** nothing asserts `size() == getTrackLength()` on tracks (would catch B3), or covisibility index consistency across evictions (would catch B1/B2).
- **Long-run/soak behavior:** all tests use ≤5 pushes past capacity; no test runs hundreds of frames through the sliding window.
- **Unchecked-precondition behavior:** empty `front()/back()`, `operator[](size())` (B4) — untestable until the contract is chosen, which is itself the finding.
- **Exception/exhaustion paths:** pool-full is tested; free-then-refill-to-full, and allocate-after-clearInactive interleavings are not.
- **Compile-time negatives:** the concepts file has good negative `static_assert`s; add ones for B9 (`N > 0`) and B3 (no `addKeypoint` on tracks) once fixed.

---

## Appendix — Reproduction probes

All probes compiled with `g++ -std=c++20 -Wall -Wextra -I<repo>/src -I/usr/include/eigen3` (timing probes with `-O2 -DNDEBUG`), run on the dev machine, 2026-07-15.

### Probe 1 — B1/B2 index staleness (subclass exposes protected index)

```cpp
template <uint32_t N>
class GraphProbe : public CCovisibilityGraph<N> { /* dump feature_to_frame_slots_ */ };

GraphProbe<3> g;
for (FrameID f : {1, 2, 3}) { g.pushFrame(f); g.addVisibilityLinks(f, std::vector<SetID>{7}); }
// index: feature 7 -> [0 1 2]   (correct)
g.pushFrame(4); g.addVisibilityLinks(4, std::vector<SetID>{7});
// index: feature 7 -> [1 2 2]   (stale + duplicate; correct would be [0 1 2])

GraphProbe<3> g2; g2.pushFrame(10);
g2.addVisibilityLinks(10, std::vector<SetID>{5});
g2.addVisibilityLinks(10, std::vector<SetID>{5});
// index: feature 5 -> [0 0]     (duplicate entry, B2)
```

### Probe 2 — B3 keypoint/frame desync

```cpp
CFeatureTrack<SFeatureLocation2D, 4> t(1);
t.addKeypoint({1.0, 2.0});              // public via base; bypasses frame bookkeeping
t.addKeypointToTrack({3.0, 4.0}, 100);
// size()=2, getTrackLength()=1, getKeypointAtFrame(100) == (1,2)  [expected (3,4)]
```

### Probe 3 — B1 growth/degradation (window 64, 300 features/frame)

Output reproduced in §2/B1 table. Key line of the probe:

```cpp
for (int f = 0; f < kFrames; ++f) { g.pushFrame(f); g.addVisibilityLinks(f, feats); }
// per-2000-frame block timing + total index entry count via protected accessor
```

### Probe 4 — hot-path timings

Output reproduced in §5. Workloads: 200k free/alloc cycles at fixed occupancy (P1); 20k `clearInactive` calls with 400 kept IDs (P2); 20k frames × 300 links sorted vs. shuffled (P3); 2k `clearInactiveFeatures` over a full 64-frame window (P4).
