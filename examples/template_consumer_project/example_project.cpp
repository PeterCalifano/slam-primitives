#include "example_project.h"

int main()
{
    spdlog_utils::ConfigureDefaultLogging();
    auto objLogger_ = spdlog_utils::GetLogger("example_consumer_project");
    objLogger_->info("Hello, World! This is an example of project using the template_project as library, integrating it through cmake.");

    // Call the placeholder function from the template_src library
    placeholder::placeholder_fcn();

    return 0;
}
