# slam-primitives

`slam-primitives` is a header-only C++20 library for common visual-SLAM frontend data structures:

- fixed-capacity feature sets and feature tracks
- generic set bundles keyed by `SetID` and track bundles keyed by `CFeatureTrackID`
- sliding-window covisibility graphs
- validated camera views, image observations, and owning flat track batches
- lightweight feature-location and LiDAR augmentation types

The project is intentionally small and installable as a CMake package. CUDA, oneTBB, documentation, profiling flags, and Python wrapping are optional build surfaces; the core library only requires Eigen and a C++20 compiler.

## Requirements

| Dependency | Version | Notes |
|---|---:|---|
| CMake | 3.15+ | Configure/build/install |
| C++ compiler | C++20 | GCC 11+ or Clang 13+ recommended |
| Eigen3 | 3.4+ | Required library dependency |
| Catch2 | 3.x | Required for C++ tests; fetched when enabled and missing |
| Doxygen + Graphviz | any recent | Optional docs build |
| CUDA Toolkit | 12.x | Optional `-Dslam-primitives_ENABLE_CUDA=ON` configuration |
| oneTBB | any recent | Optional `-DENABLE_TBB=ON` |
| gtwrap + pybind11 | local checkout or package | Optional Python wrapper |
| ROS 2 + colcon | Jazzy recommended | Optional core/interfaces overlay |

## Quick Start

```bash
# Configure, build, and run tests in ./build
./build_lib.sh

# Use Ninja and install into ./install
./build_lib.sh -N -i

# Portable optimized build, avoiding host-specific CPU flags
./build_lib.sh -D CPU_ENABLE_NATIVE_TUNING=OFF
```

Manual CMake flow:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --install build --prefix install
```

## Main CMake Options

| Option | Default | Purpose |
|---|---:|---|
| `slam-primitives_METADATA_ONLY` | OFF | Configure identity/version metadata without enabling a compiler |
| `ENABLE_TESTS` | ON | Build and register Catch2 tests |
| `slam-primitives_ENABLE_CUDA` | OFF | Enable CUDA language support and CUDA compile interface |
| `ENABLE_TBB` | OFF | Link oneTBB when available |
| `ENABLE_OPENGL` | OFF | Enable OpenGL compile interface |
| `ENABLE_PROFILING` | OFF | Add profiling-friendly compiler settings |
| `ENABLE_GPERFTOOLS` | `ENABLE_PROFILING` | Link gperftools profiler when found |
| `ENABLE_TCMALLOC` | OFF | Link tcmalloc when explicitly requested |
| `CPU_ENABLE_NATIVE_TUNING` | ON | Add `-march=native -mtune=native` in optimized GNU/Clang builds |
| `WRITE_SOURCE_VERSION_FILE` | OFF | Write `VERSION` into the source tree during configure |
| `BUILD_DOC_XML` | OFF | Generate Doxygen XML alongside HTML |
| `slam-primitives_BUILD_PROGRAMS` | ON | Build in-tree program targets when this is the main project |
| `slam-primitives_BUILD_EXAMPLES` | ON | Build in-tree example targets when this is the main project |
| `slam-primitives_BUILD_PYTHON_WRAPPER` | OFF | Build the optional Python wrapper |
| `slam-primitives_BUILD_MATLAB_WRAPPER` | OFF | Build the optional MATLAB wrapper |
| `slam-primitives_GTWRAP_RUNTIME_DEPENDENCY_TARGETS` | empty | Shared runtime targets staged beside the Python extension |
| `slam-primitives_GTWRAP_MATLAB_MODULE_NAME` | `slam_primitives` | Identifier-safe generated MATLAB/MEX module name |

The legacy top-level aliases `PROJECT_METADATA_ONLY` and `ENABLE_CUDA` remain
accepted for existing scripts, but nested consumers must use the canonical
project-qualified options. The exported namespaced core target is always
`INTERFACE`; `BUILD_SHARED_LIBS` does not change the core
library into a compiled target. `Release` and `RelWithDebInfo` builds define
`NDEBUG`. For CI or distributable binaries, prefer setting
`CPU_ENABLE_NATIVE_TUNING=OFF`.

## Library Usage

After installing:

```cmake
find_package(slam-primitives REQUIRED CONFIG)

add_executable(app main.cpp)
target_link_libraries(app PRIVATE slam-primitives::slam-primitives)
```

Public C++ headers use `<slam-primitives/...>` in build and install trees.
The C++ namespace and Python/MATLAB module names remain `slam_primitives`.

Minimal C++ example:

```cpp
#include <slam-primitives/bundle/CFeatureSetBundle.h>
#include <slam-primitives/feature_sets/CFeatureTrack.h>
#include <slam-primitives/types/identifiers.h>
#include <slam-primitives/types/feature_types.h>

using namespace slam_primitives;

int main()
{
    using Track = CFeatureTrack<SFeatureLocation2D, 64>;

    CFeatureSetBundle<Track, 32> bundle;
    Track track;
    track.addKeypointToTrack({100.0, 200.0}, CFrameID{0U});
    track.addKeypointToTrack({101.5, 201.2}, CFrameID{1U});

    const CFeatureTrackID id = bundle.allocate(std::move(track));
    return bundle.get(id).getTrackLength() == 2 ? 0 : 1;
}
```

`SetID` remains the 64-bit ID of a generic `CFeatureSet`. Tracks use the
distinct 64-bit `CFeatureTrackID`; a track bundle returns that type.
`CFeatureSet` and `CFeatureTrack` are independent value types. A track stores
each keypoint with its strictly increasing `CFrameID` through
`addKeypointToTrack()`; it has no inherited keypoint-only mutation path. A new set
or track has no assigned ID until its constructor, `setID()`, or bundle
allocation assigns one. `getID()` throws on an unassigned object. A bundle
preserves an assigned ID and rejects an active duplicate. For an unassigned
object it generates a fresh ID above every ID previously inserted, starting at
1. An explicit ID may be reused after its entry is freed; generated IDs are
never reused. `checkedSetIDToUint32()` and `CFeatureTrackID::toUint32()` reject
lossy narrowing.

Native frame APIs use `CFrameID`, a valid unsigned 32-bit value that defaults
to frame 0. The signed `FrameID` alias is only for checked conversion through
`CFrameID::fromLegacy()` and `toLegacy()`; negative legacy values are rejected.
Direct construction from signed or wider integers also checks for negative values
and 32-bit overflow.

Public headers are grouped by the contract they define:

| Module/header | Contents |
|---|---|
| `types/identifiers.h` | Distinct set, track, and frame IDs; checked conversions; identifier constraints |
| `types/feature_types.h` | Pixel locations, LiDAR data, and the `FeatureLocation` concept |
| `camera/` | Pinhole calibration and calibrated camera views |
| `feature_sets/labeling_policies.h` | Track labeling data and the `LabelingPolicy` concept |
| `bundle/CFeatureSetBundle.h` | Bundle storage and the `BundleStorable` concept |
| `detail/covariance_validation.h` | Internal covariance validation used by camera views and observations |

Includes use the installed `slam-primitives/` prefix. Internal headers in `detail/`
are installed for the public inline implementation; they are not an application API.

The native data core also provides `CPinholeCameraCalibration`, `CCameraView`,
`CImagePointObservation`, and `CFeatureTrackBatch`. Camera views use `CFrameID`
and explicit world-to-camera geometry. Image observations own validated pixel
covariance. A flat batch owns chronological observations grouped under sorted
`CFeatureTrackID` values; its returned spans borrow the batch's storage.
Numerical triangulation and application policy belong to consumers.

The downstream package example is in `examples/template_consumer_project`. It requires an installed prefix and intentionally does not auto-build the parent repository.

```bash
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/tmp/slam-primitives-install
cmake --build build --parallel
cmake --install build --prefix /tmp/slam-primitives-install

cmake -S examples/template_consumer_project -B /tmp/slam-primitives-consumer \
  -DSLAM_PRIMITIVES_INSTALL_PREFIX=/tmp/slam-primitives-install
cmake --build /tmp/slam-primitives-consumer --parallel
```

## Documentation

```bash
cmake -S . -B build-docs -DBUILD_DOC_XML=ON
cmake --build build-docs --target doc
```

Generated outputs:

- HTML: `build-docs/doc/html/index.html`
- XML: `build-docs/doc/xml`

## Optional Python Wrapper

The Python wrapper is off by default and builds the import package `slam_primitives`.

Wrapper source of truth:

- Package entrypoint: `python/slam_primitives/__init__.py`
- Interface file: `src/slam_primitives/wrapped/slam_primitives.i`
- Header-only facade: `src/slam_primitives/wrapped/slam_primitives_wrapper_interfaces.h`

No generated wrapper `.cpp` is checked in. Generated C++, packaging metadata,
the extension, and its runtime manifest stay under `build-wrap/python/`; an
ordinary wrapper configure/build does not modify `python/` in the checkout.

Example:

```bash
cmake -S . -B build-wrap \
  -Dslam-primitives_BUILD_PYTHON_WRAPPER=ON \
  -Dslam-primitives_GTWRAP_ROOT_DIR=/path/to/wrap
cmake --build build-wrap --target slam-primitives_py --parallel
ctest --test-dir build-wrap -R slam-primitives_python_import --output-on-failure
```

The wrapper exposes Python-friendly feature-track, bundle, and covisibility flows through concrete classes:

- `CFeatureTrack2D`
- `CFeatureTrackBundle2D`
- `CCovisibilityGraphWrapper`

These facades expose track IDs as numeric `uint64_t` and frame IDs as numeric
`uint32_t`. `CFeatureTrackBundle2D` supports generated IDs through
`allocateTrack()` and caller-supplied IDs through `allocateTrackWithID()`;
both forms also accept an initial observation. Python vector results are
ordinary lists after binding conversion.

`import slam_primitives` always works from the source package. `HAS_WRAPPER` is `True` only when the compiled extension imports successfully; otherwise it remains `False` and `WRAPPER_IMPORT_ERROR` records the import failure.

The core `INTERFACE` target has no runtime library to package. If future
project-owned shared dependencies are required by the extension, list their
build targets in `slam-primitives_GTWRAP_RUNTIME_DEPENDENCY_TARGETS`; CMake
stages those explicit runtime artifacts beside the wrapper without scanning or
copying unrelated system libraries.

## Header-only Logging

Consumers can opt into the dependency-free C++20 logger by including
`slam-primitives/logging/CLogger.h`. It preserves the library's `INTERFACE`
target model, has no spdlog dependency, and supports severity filtering,
explicit colors, stream routing, environment configuration, and complete-line
concurrent output. See
[doc/logging.md](doc/logging.md) for its ownership and threading contract.

## Optional ROS 2 Overlay

The standalone header-only build never requires ROS. A separate optional colcon
workspace installs the core CMake package and the existing feature-track
message interfaces:

```bash
./build_ros2.sh --clean
```

The overlay contains only the `slam_primitives` core shim and
`slam_primitives_interfaces`; it intentionally has no lifecycle node, bridge,
or spinup package. See [doc/ros2_overlay.md](doc/ros2_overlay.md) for package,
metadata synchronization, CUDA, and CI details.

## CI

GitHub workflows are initialized for:

- Linux configure/build/test/install/consumer/docs validation
- manual self-hosted CUDA configure/build/test validation
- optional ROS 2 Jazzy core/interfaces overlay validation
- documentation artifact builds

The Linux CI path also validates compiler-free project metadata, installation
through a downstream consumer, canonical source-package contents, absence of
configure-time source-tree `VERSION` writes, and removed template/backend
surfaces.
