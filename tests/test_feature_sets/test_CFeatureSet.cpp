#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>
#include "slam-primitives/feature_sets/CFeatureSet.h"
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/types/identifiers.h"

#include <cstdint>
#include <stdexcept>
#include <type_traits>

using namespace slam_primitives;
using Set = CFeatureSet<SFeatureLocation2D, 4>;
static_assert(std::is_same_v<Set::IDType, SetID>);

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
    REQUIRE_THROWS_AS(s.getID(), std::logic_error);
    REQUIRE(s.size() == 0);
    REQUIRE_FALSE(s.isInitialized());
}

TEST_CASE("CFeatureSet setID assigns identifier and marks initialized", "[feature_sets]")
{
    Set s;

    s.setID(7);

    REQUIRE(s.getID() == 7);
    REQUIRE(s.isInitialized());
    REQUIRE_THROWS_AS(s.setID(8), std::logic_error);
    REQUIRE(s.getID() == 7);
}

TEST_CASE("Assigned feature sets reject replacement with a different identity", "[feature_sets]")
{
    Set set{SetID{7U}};
    REQUIRE_THROWS_AS((set = Set{SetID{8U}}), std::logic_error);
    REQUIRE_THROWS_AS((set = Set{}), std::logic_error);
    REQUIRE(set.getID() == 7U);

    Set same_id{SetID{7U}};
    same_id.addKeypoint({3.0, 4.0});
    set = same_id;
    REQUIRE(set.getID() == 7U);
    REQUIRE(set.size() == 1U);
}

TEST_CASE("CFeatureSet retains a caller-assigned 64-bit ID", "[feature_sets]")
{
    const SetID high_id = std::uint64_t{1} << 40U;
    Set s(high_id);
    REQUIRE(s.getID() == high_id);
}

TEST_CASE("CFeatureSet add keypoints", "[feature_sets]")
{
    Set s(1);
    REQUIRE_FALSE(s.addKeypoint({1.0, 2.0}));
    REQUIRE_FALSE(s.addKeypoint({3.0, 4.0}));
    REQUIRE(s.size() == 2);

    auto span = s.getKeypoints();
    REQUIRE(span.size() == 2);
    REQUIRE(span[0].u == Catch::Approx(1.0));
    REQUIRE(span[1].v == Catch::Approx(4.0));
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
    for (int i = 0; i < 4; ++i)
        s.addKeypoint({static_cast<double>(i), 0.0});
    REQUIRE(s.addKeypoint({99.0, 99.0})); // still returns full
    REQUIRE(s.size() == 4);               // no growth
    REQUIRE(s.getKeypoint(3).u == Catch::Approx(3.0));
    REQUIRE_THROWS_AS(s.getKeypoint(4), std::out_of_range);
}

TEST_CASE("CFeatureSet getKeypoint valid index", "[feature_sets]")
{
    Set s(1);
    s.addKeypoint({5.0, 6.0});
    auto &kp = s.getKeypoint(0);
    REQUIRE(kp.u == Catch::Approx(5.0));
    REQUIRE(kp.v == Catch::Approx(6.0));
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
