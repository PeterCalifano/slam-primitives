#pragma once
#include <Eigen/Dense>
#include <catch2/catch_test_macros.hpp>
#include <iostream>

namespace fixtures
{
   using std::cout, std::endl;

    /**
     * @brief Fixture for testing CDynamics and CDynObjects.
     *
     */
    struct SObjectFixture
    {
        SObjectFixture()
        {
        }

        // DATA MEMBERS
        int fixtureVariable = 0;
    };
}