#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/feature_sets/CFeatureSet.h"
#include "slam_primitives/types/SFeatureLocation2D.h"

using namespace slam_primitives;
using Set = CFeatureSet<SFeatureLocation2D, 4>;

TEST_CASE("CFeatureSet construct with ID", "[feature_sets]")
{
    Set s(42);
    REQUIRE(s.getID() == 42);
    REQUIRE(s.size() == 0);
    REQUIRE(s.isInitialized());
    REQUIRE_FALSE(s.isTerminated());
}

TEST_CASE("CFeatureSet default construct", "[feature_sets]")
{
    Set s;
    REQUIRE(s.getID() == 0);
    REQUIRE(s.size() == 0);
    REQUIRE_FALSE(s.isInitialized());
}

TEST_CASE("CFeatureSet add keypoints", "[feature_sets]")
{
    Set s(1);
    REQUIRE_FALSE(s.addKeypoint({1.0, 2.0}));
    REQUIRE_FALSE(s.addKeypoint({3.0, 4.0}));
    REQUIRE(s.size() == 2);

    auto span = s.getKeypoints();
    REQUIRE(span.size() == 2);
    REQUIRE(span[0].u == 1.0);
    REQUIRE(span[1].v == 4.0);
}

TEST_CASE("CFeatureSet full signal on last add", "[feature_sets]")
{
    Set s(1);
    REQUIRE_FALSE(s.addKeypoint({1.0, 1.0}));
    REQUIRE_FALSE(s.addKeypoint({2.0, 2.0}));
    REQUIRE_FALSE(s.addKeypoint({3.0, 3.0}));
    REQUIRE(s.addKeypoint({4.0, 4.0})); // full
    REQUIRE(s.size() == 4);
    REQUIRE(Set::capacity() == 4);
}

TEST_CASE("CFeatureSet add beyond capacity is no-op", "[feature_sets]")
{
    Set s(1);
    for (int i = 0; i < 4; ++i) s.addKeypoint({static_cast<double>(i), 0.0});
    REQUIRE(s.addKeypoint({99.0, 99.0})); // still returns full
    REQUIRE(s.size() == 4); // no growth
}

TEST_CASE("CFeatureSet getKeypoint valid index", "[feature_sets]")
{
    Set s(1);
    s.addKeypoint({5.0, 6.0});
    auto& kp = s.getKeypoint(0);
    REQUIRE(kp.u == 5.0);
    REQUIRE(kp.v == 6.0);
}

TEST_CASE("CFeatureSet getKeypoint out of range", "[feature_sets]")
{
    Set s(1);
    REQUIRE_THROWS_AS(s.getKeypoint(0), std::out_of_range);
    s.addKeypoint({1.0, 1.0});
    REQUIRE_THROWS_AS(s.getKeypoint(1), std::out_of_range);
}

TEST_CASE("CFeatureSet empty set getKeypoints", "[feature_sets]")
{
    Set s(1);
    auto span = s.getKeypoints();
    REQUIRE(span.empty());
}
