# Header-only logging

The optional logger lives in
`src/slam_primitives/logging/CLogger.h`. It is a dependency-free C++20 public
header and does not change the core library's `INTERFACE` target model.

## Design

`slam_primitives::logging::CLogger` provides:

- ordered severity filtering from `Quiet` through `Trace`;
- component-scoped lines in the form `[component][LEVEL] message`;
- diagnostic-stream routing for critical, error, and warning messages;
- ordinary-output routing for info, debug, and trace messages;
- explicit, disabled-by-default ANSI colors;
- case-insensitive named or numeric level parsing;
- optional `SLAM_PRIMITIVES_LOG_LEVEL` environment configuration.

Each call formats a complete line before emitting it through
`std::osyncstream`. Calls from multiple threads can therefore share a
destination stream buffer without interleaving partial lines. A logger stores
references to its output streams; callers that provide custom streams must keep
them alive for the logger's lifetime and must not mutate or destroy them
concurrently.

The logger deliberately has no singleton, registry, file sink, formatting
dependency, timestamp policy, or asynchronous queue. Consumers that do not
include and instantiate `CLogger` incur no logging-specific compile or runtime
work.

## Levels and environment configuration

A configured level includes every less-verbose severity. For example, `Info`
enables critical, error, warning, and informational messages while filtering
debug and trace messages.

`setLevelFromEnvironment()` reads `SLAM_PRIMITIVES_LOG_LEVEL` by default. It
accepts the names `quiet`/`off`, `critical`/`fatal`, `error`,
`warning`/`warn`, `info`, `debug`, and `trace`, or a numeric value from `0` to
`6`. Missing or invalid values leave the current level unchanged.

```bash
SLAM_PRIMITIVES_LOG_LEVEL=debug ./my_consumer
```

## C++ usage

```cpp
#include <slam_primitives/logging/CLogger.h>

int main()
{
    slam_primitives::logging::CLogger logger(
        "frontend", slam_primitives::logging::ELogLevel::Info);
    logger.setLevelFromEnvironment();
    logger.info("Processing ", 3, " tracks.");
    logger.debug("Detailed diagnostics are enabled.");
    return 0;
}
```

With the configured `Info` level, this emits:

```text
[frontend][INFO] Processing 3 tracks.
```

Custom streams make capture explicit in tests and applications:

```cpp
#include <sstream>

std::ostringstream output;
std::ostringstream diagnostics;
slam_primitives::logging::CLogger logger(
    "worker",
    slam_primitives::logging::ELogLevel::Info,
    slam_primitives::logging::ELogColorMode::Disabled,
    output,
    diagnostics);
```
