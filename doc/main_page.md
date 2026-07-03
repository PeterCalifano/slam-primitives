# slam-primitives {#mainpage}

`slam-primitives` is a header-only C++20 library with reusable SLAM data
structures for feature locations, feature sets, feature tracks, feature-set
bundles, circular buffers, and sliding-window covisibility graphs.

See README.md for build and installation instructions.

## Build

```bash
./build_lib.sh -t relwithdebinfo -i
```

The installed package exports:

```cmake
find_package(slam-primitives REQUIRED CONFIG)
target_link_libraries(my_target PRIVATE slam-primitives::slam-primitives)
```

## Optional Components

- CUDA language support is optional and disabled by default.
- Python wrapper support is optional and generated from the configured wrapper
  interface when enabled.
- Documentation builds generate HTML by default and XML when
  `BUILD_DOC_XML=ON`.

## Examples

Use `examples/template_examples/` for in-tree usage and
`examples/template_consumer_project/` for an installed-package consumer smoke.
