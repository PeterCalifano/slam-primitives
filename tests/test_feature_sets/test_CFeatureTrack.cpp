#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/feature_sets/CFeatureTrack.h"
#include "slam_primitives/types/SFeatureLocation2D.h"
#include "slam_primitives/types/labeling_policies.h"
#include "slam_primitives/types/type_aliases.h"

using namespace slam_primitives;
using Track = CFeatureTrack<SFeatureLocation2D, 4>;

TEST_CASE("CFeatureTrack create and add keypoints", "[feature_sets]")
{
    Track t(10);
    REQUIRE(t.getID() == 10);
    REQUIRE(t.getTrackLength() == 0);
    REQUIRE_FALSE(t.isTerminated());

    REQUIRE_FALSE(t.addKeypointToTrack({1.0, 2.0}, 100));
    REQUIRE_FALSE(t.addKeypointToTrack({3.0, 4.0}, 101));
    REQUIRE(t.getTrackLength() == 2);
}

TEST_CASE("CFeatureTrack termination at MAX_LENGTH", "[feature_sets]")
{
    Track t(1);
    REQUIRE_FALSE(t.addKeypointToTrack({0, 0}, 0));
    REQUIRE_FALSE(t.addKeypointToTrack({0, 0}, 1));
    REQUIRE_FALSE(t.addKeypointToTrack({0, 0}, 2));
    REQUIRE(t.addKeypointToTrack({0, 0}, 3)); // 4th = MAX_LENGTH
    REQUIRE(t.isTerminated());
    REQUIRE(t.getTrackLength() == 4);
}

TEST_CASE("CFeatureTrack manual terminate", "[feature_sets]")
{
    Track t(1);
    t.addKeypointToTrack({1, 1}, 0);
    REQUIRE_FALSE(t.isTerminated());
    t.terminate();
    REQUIRE(t.isTerminated());
}

TEST_CASE("CFeatureTrack add after terminated is no-op", "[feature_sets]")
{
    Track t(1);
    t.terminate();
    REQUIRE(t.addKeypointToTrack({1, 1}, 0));
    REQUIRE(t.getTrackLength() == 0);
}

TEST_CASE("CFeatureTrack getFrameIDs", "[feature_sets]")
{
    Track t(1);
    t.addKeypointToTrack({0, 0}, 10);
    t.addKeypointToTrack({0, 0}, 20);
    t.addKeypointToTrack({0, 0}, 30);

    auto ids = t.getFrameIDs();
    REQUIRE(ids.size() == 3);
    REQUIRE(ids[0] == 10);
    REQUIRE(ids[1] == 20);
    REQUIRE(ids[2] == 30);
}

TEST_CASE("CFeatureTrack getKeypointAtFrame existing", "[feature_sets]")
{
    Track t(1);
    t.addKeypointToTrack({5.0, 6.0}, 42);
    t.addKeypointToTrack({7.0, 8.0}, 43);

    auto kp = t.getKeypointAtFrame(42);
    REQUIRE(kp.has_value());
    REQUIRE(kp->u == 5.0);
    REQUIRE(kp->v == 6.0);
}

TEST_CASE("CFeatureTrack getKeypointAtFrame missing", "[feature_sets]")
{
    Track t(1);
    t.addKeypointToTrack({5.0, 6.0}, 42);

    auto kp = t.getKeypointAtFrame(99);
    REQUIRE_FALSE(kp.has_value());
}

TEST_CASE("CFeatureTrack labeling disabled no overhead", "[feature_sets]")
{
    using TrackDisabled = CFeatureTrack<SFeatureLocation2D, 4, SLabelingDisabled>;
    // Just verify it compiles and labeling data is accessible
    TrackDisabled t(1);
    REQUIRE_FALSE(TrackDisabled::capacity() == 0);
    auto& label = t.getLabelingData();
    REQUIRE_FALSE(label.has_labeling);
}

TEST_CASE("CFeatureTrack labeling enabled stores data", "[feature_sets]")
{
    using TrackEnabled = CFeatureTrack<SFeatureLocation2D, 4, SLabelingEnabled<4>>;
    TrackEnabled t(1);
    auto& label = t.getLabelingData();
    REQUIRE(label.has_labeling);

    label.labeled_keypoints[0] = {10.0, 20.0};
    REQUIRE(t.getLabelingData().labeled_keypoints[0].u == 10.0);
}

TEST_CASE("CFeatureTrack lidar augmentation", "[feature_sets]")
{
    Track t(1);
    REQUIRE_FALSE(t.getLidar().has_value());

    SLidarEnhancedData lidar{100.0, 0.5, 0.3};
    t.setLidar(lidar);
    REQUIRE(t.getLidar().has_value());
    REQUIRE(t.getLidar()->range == 100.0);
    REQUIRE(t.getLidar()->azimuth == 0.5);
    REQUIRE(t.getLidar()->elevation == 0.3);
}

TEST_CASE("CFeatureTrack length 1", "[feature_sets]")
{
    Track t(1);
    t.addKeypointToTrack({1.0, 1.0}, 0);
    REQUIRE(t.getTrackLength() == 1);
    REQUIRE(t.getFrameIDs().size() == 1);
}

TEST_CASE("CFeatureTrack just constructed length 0", "[feature_sets]")
{
    Track t(1);
    REQUIRE(t.getTrackLength() == 0);
    REQUIRE(t.getFrameIDs().empty());
}
