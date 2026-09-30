#include "slam-primitives/feature_sets/feature_track_snapshot.h"
#include "slam-primitives/types/identifiers.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>
#include <type_traits>

using namespace slam_primitives;
static_assert(std::is_same_v<decltype(SFeatureTrackObservation2D{}.frame_id), CFrameID>);

TEST_CASE("SFeatureTrackSnapshot preserves chronological 2D observations", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 3> track{CFeatureTrackID{47U}};
    track.addKeypointToTrack({10.25, 20.5}, CFrameID{101U});
    track.addKeypointToTrack({11.5, 21.75}, CFrameID{102U});
    track.addKeypointToTrack({12.0, 22.25}, CFrameID{103U});

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == CFeatureTrackID{47U});
    REQUIRE(snapshot.is_terminated);
    REQUIRE(snapshot.observations.size() == 3);
    REQUIRE(snapshot.observations[0].frame_id == CFrameID{101U});
    REQUIRE(snapshot.observations[0].location.u == Catch::Approx(10.25));
    REQUIRE(snapshot.observations[0].location.v == Catch::Approx(20.5));
    REQUIRE(snapshot.observations[1].frame_id == CFrameID{102U});
    REQUIRE(snapshot.observations[1].location.u == Catch::Approx(11.5));
    REQUIRE(snapshot.observations[1].location.v == Catch::Approx(21.75));
    REQUIRE(snapshot.observations[2].frame_id == CFrameID{103U});
    REQUIRE(snapshot.observations[2].location.u == Catch::Approx(12.0));
    REQUIRE(snapshot.observations[2].location.v == Catch::Approx(22.25));
}

TEST_CASE("SFeatureTrackSnapshot preserves manual termination", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 4> track{CFeatureTrackID{8U}};
    track.addKeypointToTrack({3.0, 4.0}, CFrameID{11U});
    track.terminate();

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == CFeatureTrackID{8U});
    REQUIRE(snapshot.is_terminated);
    REQUIRE(snapshot.observations.size() == 1);
    REQUIRE(snapshot.observations.front().frame_id == CFrameID{11U});
}

TEST_CASE("SFeatureTrackSnapshot rejects an unassigned track", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 4> track;

    REQUIRE_THROWS_AS(makeFeatureTrackSnapshot(track), std::logic_error);
}

TEST_CASE("SFeatureTrackSnapshot accepts enabled labeling policies", "[feature_sets]")
{
    CFeatureTrack<SFeatureLocation2D, 2, SLabelingEnabled<2>> track{CFeatureTrackID{9U}};
    track.addKeypointToTrack({1.0, 2.0}, CFrameID{0U});

    const auto snapshot = makeFeatureTrackSnapshot(track);

    REQUIRE(snapshot.track_id == CFeatureTrackID{9U});
    REQUIRE(snapshot.observations.size() == 1);
    REQUIRE(snapshot.observations.front().frame_id == CFrameID{0U});
}
