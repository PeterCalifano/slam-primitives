#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>
#include "slam_primitives/types/SFeatureLocation2D.h"
#include "slam_primitives/types/concepts.h"
#include "slam_primitives/types/labeling_policies.h"
#include "slam_primitives/types/type_aliases.h"
#include "slam_primitives/feature_sets/CFeatureSet.h"
#include "slam_primitives/feature_sets/CFeatureTrack.h"

using namespace slam_primitives;

// Concept satisfaction checks (static_assert in tests only)
static_assert(FeatureLocation<SFeatureLocation2D>);
static_assert(LabelingPolicy<SLabelingDisabled>);
static_assert(LabelingPolicy<SLabelingEnabled<64>>);

// Negative compile-time checks
struct SBadType { int x; };
static_assert(!FeatureLocation<SBadType>);
static_assert(!LabelingPolicy<SBadType>);
static_assert(!LabelingPolicy<int>);

// FeatureSetLike concept
static_assert(FeatureSetLike<CFeatureSet<SFeatureLocation2D>>);
static_assert(FeatureSetLike<CFeatureTrack<SFeatureLocation2D>>);
static_assert(!FeatureSetLike<SBadType>);

// EBO: SLabelingDisabled is empty
static_assert(sizeof(SLabelingDisabled) == 1);

TEST_CASE("SFeatureLocation2D default construction", "[types]")
{
    SFeatureLocation2D loc;
    REQUIRE(loc.u == Catch::Approx(0.0));
    REQUIRE(loc.v == Catch::Approx(0.0));
}

TEST_CASE("SFeatureLocation2D value init", "[types]")
{
    SFeatureLocation2D loc{1.5, 2.5};
    REQUIRE(loc.u == Catch::Approx(1.5));
    REQUIRE(loc.v == Catch::Approx(2.5));
}

TEST_CASE("SLabelingDisabled has no labeling", "[types]")
{
    REQUIRE_FALSE(SLabelingDisabled::has_labeling);
}

TEST_CASE("SLabelingEnabled has labeling", "[types]")
{
    REQUIRE(SLabelingEnabled<32>::has_labeling);
}

TEST_CASE("SLabelingEnabled stores labeled keypoints", "[types]")
{
    SLabelingEnabled<4> labeling;
    labeling.labeled_keypoints[0] = {3.0, 4.0};
    REQUIRE(labeling.labeled_keypoints[0].u == Catch::Approx(3.0));
    REQUIRE(labeling.labeled_keypoints[0].v == Catch::Approx(4.0));
}

TEST_CASE("SLabelingEnabled stores point position", "[types]")
{
    SLabelingEnabled<4> labeling;
    labeling.point_position_TB = Eigen::Vector3d(1.0, 2.0, 3.0);
    REQUIRE(labeling.point_position_TB.x() == Catch::Approx(1.0));
    REQUIRE(labeling.point_position_TB.y() == Catch::Approx(2.0));
    REQUIRE(labeling.point_position_TB.z() == Catch::Approx(3.0));
}

TEST_CASE("EBO verification on CFeatureTrack", "[types]")
{
    // Track with labeling disabled should be smaller than with labeling enabled
    using TrackDisabled = CFeatureTrack<SFeatureLocation2D, 4, SLabelingDisabled>;
    using TrackEnabled = CFeatureTrack<SFeatureLocation2D, 4, SLabelingEnabled<4>>;
    REQUIRE(sizeof(TrackDisabled) < sizeof(TrackEnabled));
}

TEST_CASE("SLidarEnhancedData default values", "[types]")
{
    SLidarEnhancedData lidar;
    REQUIRE(lidar.range == Catch::Approx(0.0));
    REQUIRE(lidar.azimuth == Catch::Approx(0.0));
    REQUIRE(lidar.elevation == Catch::Approx(0.0));
}
