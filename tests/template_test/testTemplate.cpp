#include <iostream>
#include <template_fixtures/test_fixtures.h>

using std::cout, std::endl;

TEST_CASE("test_template", "[test]")
{
    // Test print method
    SECTION("This_is_a_test_section")
    {
        cout << "This is a test section" << "\n";
    }

    REQUIRE(1 == 1);
};

/*
TEST_CASE_METHOD(fixtures::SObjectFixture, "test_template_method_fixture", "[test]")
{
    // Test print method
    SECTION("This_is_a_test_section")
    {
        cout << "This is a test section inside a fixture object, which contains the variable: " << fixtureVariable << "\n";
    }

    REQUIRE(1 == 1);
    REQUIRE(fixtureVariable == 0);
};
*/