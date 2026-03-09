# cpp_cuda_template_project {#mainpage}

See the [README](../../README.md) for full usage documentation, or read on for the condensed reference.

## Installation

```bash
git clone <repo-url> my_project && cd my_project
./build_lib.sh -t release -i      # build + install to ./install
```

## Common Build Toggles

```bash
# Enable CUDA + NVCC optimization toggles
./build_lib.sh -D ENABLE_CUDA=ON -D CUDA_ENABLE_FMAD=ON -D CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION=ON

# Enable oneTBB and explicit SIMD/FMA
./build_lib.sh -D ENABLE_TBB=ON -D CPU_ENABLE_SIMD=ON -D CPU_SIMD_LEVEL=avx2 -D CPU_ENABLE_FMA=ON

# Disable native tuning for portable binaries
./build_lib.sh -D CPU_ENABLE_NATIVE_TUNING=OFF
```

## Wrapper Build

```bash
# Python wrapper
./build_lib.sh -p

# Python + MATLAB wrappers
./build_lib.sh -p -m

# Use a local wrap checkout instead of installed gtwrap
./build_lib.sh -p --gtwrap-root /path/to/wrap
```

Install Python package manually from the generated folder:

```bash
cd build/python
python -m pip install .
```

## Example usage (assuming installation worked)

```cmake
set(my_project_DIR "/path/to/install/lib/cmake/my_project")
find_package(my_project REQUIRED)
target_link_libraries(my_target PRIVATE my_project::my_project)
```

See `examples/template_consumer_project/` for a complete downstream CMake project.

## Adapting to a new project

Replace all occurrences of `template_project` with your project name, rename
`src/template_src/` and `src/template_src_kernels/`, and update
`set(project_name ...)` in the root `CMakeLists.txt`.

Full details in `README.md`.
