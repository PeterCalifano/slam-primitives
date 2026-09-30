# slam-primitives {#mainpage}

`slam-primitives` is a header-only C++20 library with reusable SLAM data
structures for feature locations, feature sets, feature tracks, feature-set
bundles, circular buffers, and sliding-window covisibility graphs.

See README.md for build and installation instructions.

## Covisibility frame window

`CCovisibilityGraph<MAX_FRAMES, FeatureIDT>` owns fixed-capacity storage and
defaults to retaining `MAX_FRAMES` frames. An explicit constructor argument or
`setWindowSize()` selects a runtime limit from 1 through that capacity;
`getWindowSize()` reports the limit and `frameCount()` reports retained contents.
Shrinking removes the oldest excess frames immediately and updates reverse-index
slots. Increasing the limit never restores evicted frames. Invalid limits and
duplicate live frame IDs are rejected before eviction or configuration mutation.
Spans into removed frames become invalid; the graph object remains in place.
The same API is exposed by `CCovisibilityGraphWrapper` for Python/MATLAB.

The runnable `examples/template_examples/example_graph_window.cpp` demonstrates
shrinking and growing without changing the graph type. Build with examples
enabled and run `example_graph_window`; expected output is:

```text
window=3 retained=3
window=1 retained=1 visible=2
window=4 retained=2
```

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
