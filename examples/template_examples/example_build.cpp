#include <iostream>

#include <template_src/placeholder.h>

#ifndef SPDLOG_UTILS_ENABLED
#define SPDLOG_UTILS_ENABLED 0
#endif

#if SPDLOG_UTILS_ENABLED
#include <utils/logging/SpdlogUtils.h>
#endif

int main()
{
#if SPDLOG_UTILS_ENABLED
    if (!spdlog_utils::InitializeLogLevelFromEnvironment())
    {
        spdlog_utils::ConfigureDefaultLogging();
    }

    auto objLogger_ = spdlog_utils::GetLogger("example_build");
    objLogger_->info("Hello, World! This is an example file for the template.");
    placeholder::placeholder_fcn();
#else
    std::cout << "Hello, World! This is an example file for the template." << std::endl;
    placeholder::placeholder_fcn();
#endif

    // Example output with spdlog enabled:
    // [12:34:56] [info] [example_build] Hello, World! This is an example file for the template.
    // [12:34:56] [info] [placeholder] Hello, World! I'm a placeholder function, yuppy.

    return 0;
}
