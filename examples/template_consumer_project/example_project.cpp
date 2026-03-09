#include "example_project.h"

int main()
{
    std::cout << "Hello, World! This is an example of project using the template_project as library, integrating it through cmake.\n";

    // Call the placeholder function from the template_src library
    placeholder::placeholder_fcn();

    return 0;
}