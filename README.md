# slam-primitives

`slam-primitives` is a header-only C++20 library for common visual-SLAM frontend data structures:

- fixed-capacity feature sets and feature tracks
- track bundles with monotonic `SetID` allocation
- sliding-window covisibility graphs
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
| CUDA Toolkit | 12.x | Optional `-DENABLE_CUDA=ON` configuration |
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
| `ENABLE_TESTS` | ON | Build and register Catch2 tests |
| `ENABLE_CUDA` | OFF | Enable CUDA language support and CUDA compile interface |
| `ENABLE_TBB` | OFF | Link oneTBB when available |
| `ENABLE_OPENGL` | OFF | Enable OpenGL compile interface |
| `ENABLE_PROFILING` | OFF | Add profiling-friendly compiler settings |
| `ENABLE_GPERFTOOLS` | `ENABLE_PROFILING` | Link gperftools profiler when found |
| `ENABLE_TCMALLOC` | OFF | Link tcmalloc when explicitly requested |
| `BUILD_SHARED_LIBS` | ON | Standard CMake library-type selector |
| `CPU_ENABLE_NATIVE_TUNING` | ON | Add `-march=native -mtune=native` in optimized GNU/Clang builds |
| `WRITE_SOURCE_VERSION_FILE` | OFF | Write `VERSION` into the source tree during configure |
| `BUILD_DOC_XML` | OFF | Generate Doxygen XML alongside HTML |
| `slam-primitives_BUILD_PROGRAMS` | ON | Build in-tree program targets when this is the main project |
| `slam-primitives_BUILD_EXAMPLES` | ON | Build in-tree example targets when this is the main project |
| `slam-primitives_BUILD_PYTHON_WRAPPER` | OFF | Build the optional Python wrapper |

`Release` and `RelWithDebInfo` builds define `NDEBUG`. For CI or distributable binaries, prefer setting `CPU_ENABLE_NATIVE_TUNING=OFF`.

## Library Usage

After installing:

```cmake
find_package(slam-primitives REQUIRED CONFIG)

add_executable(app main.cpp)
target_link_libraries(app PRIVATE slam-primitives::slam-primitives)
```

Minimal C++ example:

```cpp
#include <slam_primitives/bundle/CFeatureSetBundle.h>
#include <slam_primitives/feature_sets/CFeatureTrack.h>
#include <slam_primitives/types/SFeatureLocation2D.h>

using namespace slam_primitives;

int main()
{
    using Track = CFeatureTrack<SFeatureLocation2D, 64>;

    CFeatureSetBundle<Track, 32> bundle;
    Track track(0);
    track.addKeypointToTrack({100.0, 200.0}, 0);
    track.addKeypointToTrack({101.5, 201.2}, 1);

    const SetID id = bundle.allocate(std::move(track));
    return bundle.get(id).getTrackLength() == 2 ? 0 : 1;
}
```

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

No generated wrapper `.cpp` is checked in. Generated C++ stays in the build tree.

Example:

```bash
cmake -S . -B build-wrap \
  -Dslam-primitives_BUILD_PYTHON_WRAPPER=ON \
  -Dslam-primitives_GTWRAP_ROOT_DIR=/home/peterc/devDir/dev-tools/wrap \
  -DGTWRAP_SYNC_TO_MASTER=OFF
cmake --build build-wrap --target slam-primitives_py --parallel
ctest --test-dir build-wrap -R slam-primitives_python_import --output-on-failure
```

The wrapper exposes Python-friendly feature-track, bundle, and covisibility flows through concrete classes:

- `CFeatureTrack2D`
- `CFeatureTrackBundle2D`
- `CCovisibilityGraphWrapper`

`import slam_primitives` always works from the source package. `HAS_WRAPPER` is `True` only when the compiled extension imports successfully; otherwise it remains `False` and `WRAPPER_IMPORT_ERROR` records the import failure.

## Header-only Logging

Consumers can opt into the dependency-free C++20 logger by including
`slam_primitives/logging/CLogger.h`. It preserves the library's `INTERFACE`
target model and supports severity filtering, explicit colors, stream routing,
environment configuration, and complete-line concurrent output. See
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
