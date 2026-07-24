# Optional ROS 2 Overlay

The ROS 2 overlay is a separate colcon workspace for consuming the
`slam-primitives` header-only core and its project-specific feature-track
messages. The normal CMake build remains ROS-free:

```bash
./build_lib.sh
```

Build the overlay only when ROS integration is required:

```bash
./build_ros2.sh --clean
```

## Package layout

| Package | Role |
|---|---|
| `slam_primitives` | Plain-CMake colcon shim around the core library. |
| `slam_primitives_interfaces` | Feature observation and track messages. |

The shim adds the repository root as a CMake subdirectory with tests, examples,
programs, wrappers, and OpenGL disabled. The core remains an `INTERFACE`
library; colcon installs its headers and namespaced CMake package target into
the overlay prefix.

This repository intentionally has no ROS bridge node, lifecycle component,
service, launch package, or spinup package. Runtime behavior belongs in a
consumer repository until a `slam-primitives`-owned ROS execution contract is
defined.

## Build options

`build_ros2.sh` sources `/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash` and accepts:

- `--clean`
- `--skip-tests`
- `--debug` or `--release`
- `--cuda`
- `--no-version-sync`
- repeatable `--packages-select`, `--cmake-arg`, and `--colcon-arg`

CUDA is disabled by default. OptiX and PTX are intentionally unsupported.

## Metadata ownership

The root `CMakeLists.txt` owns project description, homepage, maintainer,
license, and version metadata. `PROJECT_METADATA_ONLY=ON` exposes those values
without configuring a compiler or dependencies.

Before a normal overlay build, `generate_version.sh --sync-ros2` calls
`ros2/tools/sync_package_metadata.py`. The synchronizer updates both manifests
while preserving package names, dependencies, XML processing instructions, and
file modes:

```bash
./generate_version.sh --no-sync-ros2
version_core_="$(awk -F': ' \
  '$1 == "Project version core" { print $2; exit }' VERSION)"
python3 ros2/tools/sync_package_metadata.py \
  --project-root . --ros2-dir ros2 --version "${version_core_}" --check
```

Use `--no-version-sync` only when inspecting an intentionally unsynchronized
workspace. Release preparation must synchronize manifests before creating the
source archive.
