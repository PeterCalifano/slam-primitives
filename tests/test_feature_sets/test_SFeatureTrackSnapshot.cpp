#include "slam_primitives/feature_sets/SFeatureTrackSnapshot.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

using namespace slam_primitives;

TEST_CASE("SFeatureTrackSnapshot preserves chronological 2D observations", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 3> track(47);
    track.addKeypointToTrack({10.25, 20.5}, 101);
    track.addKeypointToTrack({11.5, 21.75}, 102);
    track.addKeypointToTrack({12.0, 22.25}, 103);

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == 47);
    REQUIRE(snapshot.is_terminated);
    REQUIRE(snapshot.observations.size() == 3);
    REQUIRE(snapshot.observations[0].frame_id == 101);
    REQUIRE(snapshot.observations[0].location.u == Catch::Approx(10.25));
    REQUIRE(snapshot.observations[0].location.v == Catch::Approx(20.5));
    REQUIRE(snapshot.observations[1].frame_id == 102);
    REQUIRE(snapshot.observations[1].location.u == Catch::Approx(11.5));
    REQUIRE(snapshot.observations[1].location.v == Catch::Approx(21.75));
    REQUIRE(snapshot.observations[2].frame_id == 103);
    REQUIRE(snapshot.observations[2].location.u == Catch::Approx(12.0));
    REQUIRE(snapshot.observations[2].location.v == Catch::Approx(22.25));
}

TEST_CASE("SFeatureTrackSnapshot preserves manual termination", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 4> track(8);
    track.addKeypointToTrack({3.0, 4.0}, 11);
    track.terminate();

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == 8);
    REQUIRE(snapshot.is_terminated);
    REQUIRE(snapshot.observations.size() == 1);
    REQUIRE(snapshot.observations.front().frame_id == 11);
}

TEST_CASE("SFeatureTrackSnapshot safely converts an empty default track", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 4> track;

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == 0);
    REQUIRE_FALSE(snapshot.is_terminated);
    REQUIRE(snapshot.observations.empty());
}

TEST_CASE("SFeatureTrackSnapshot accepts enabled labeling policies", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 2, SLabelingEnabled<2>> track(9);
    track.addKeypointToTrack({1.0, 2.0}, -1);

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == 9);
    REQUIRE(snapshot.observations.size() == 1);
    REQUIRE(snapshot.observations.front().frame_id == -1);
}
