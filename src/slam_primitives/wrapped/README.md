# Optional Language Wrapper

The wrapper is optional and disabled by default. The C++ library remains
header-only for normal consumers; enabling a language binding generates wrapper
sources from `slam_primitives.i` at build time.

The checked-in wrapper surface is intentionally small:

- `slam_primitives_wrapper_interfaces.h` provides concrete facades for feature tracks,
  feature-track bundles, and covisibility flows.
- `slam_primitives.i` is the gtwrap source interface.
- Generated wrapper `.cpp` files are build artifacts and are not checked in.

The facades convert native span/template-heavy APIs into binding-friendly
`std::vector` and exception-based flows. Native ownership and behavior stay in
the existing primitives.

MATLAB note: gtwrap can generate MATLAB wrapper code from this interface, but
the current vector surface is exposed as gtwrap `std.vector...` handle classes
such as `std.vectoruint32_t`. Plain MATLAB `uint32` arrays are not part of the
supported wrapper boundary yet.

Build the wrapper explicitly:

Python example:

```bash
cmake -S . -B build-wrapper \
  -Dslam-primitives_BUILD_PYTHON_WRAPPER=ON \
  -Dslam-primitives_GTWRAP_ROOT_DIR=/path/to/wrap
cmake --build build-wrapper --target slam-primitives_py
ctest --test-dir build-wrapper -R slam-primitives_python_import --output-on-failure
```

Import contract:

```python
import slam_primitives

if slam_primitives.HAS_WRAPPER:
    track = slam_primitives.CFeatureTrack2D(7)
else:
    print(slam_primitives.WRAPPER_IMPORT_ERROR)
```
