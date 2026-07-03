#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>

#include "slam_primitives/wrapped/slam_primitives_wrapper_interfaces.h"

#include <vector>

using namespace slam_primitives;

TEST_CASE("CFeatureTrack2D exposes feature-track operations with binding-friendly containers", "[wrapped]")
{
    CFeatureTrack2D track_(42);

    REQUIRE(track_.getID() == 42);
    REQUIRE_FALSE(track_.isTerminated());
    REQUIRE_FALSE(track_.addKeypointToTrack({1.0, 2.0}, 10));
    REQUIRE_FALSE(track_.addKeypointToTrack({3.0, 4.0}, 11));

    REQUIRE(track_.getTrackLength() == 2);
    REQUIRE(track_.getFrameIDs() == std::vector<FrameID>{10, 11});
    REQUIRE(track_.hasKeypointAtFrame(11));
    REQUIRE(track_.getKeypointAtFrame(11).u == Catch::Approx(3.0));

    track_.setLidar({12.0, 0.5, -0.25});
    REQUIRE(track_.hasLidar());
    REQUIRE(track_.getLidar().range == Catch::Approx(12.0));
}

TEST_CASE("CFeatureTrackBundle2D exposes bundle-track flow without raw spans", "[wrapped]")
{
    CFeatureTrackBundle2D bundle_;

    const SetID first_id_ = bundle_.allocateTrack();
    const SetID second_id_ = bundle_.allocateTrack();

    REQUIRE(first_id_ != second_id_);
    REQUIRE(bundle_.getTrackCopy(first_id_).getID() == first_id_);
    REQUIRE(bundle_.getTrackCopy(second_id_).getID() == second_id_);
    REQUIRE(bundle_.activeCount() == 2);
    REQUIRE(bundle_.contains(first_id_));

    REQUIRE_FALSE(bundle_.addObservation(first_id_, {10.0, 20.0}, 100));
    REQUIRE_FALSE(bundle_.addObservation(first_id_, {11.0, 21.0}, 101));
    REQUIRE(bundle_.getTrackLength(first_id_) == 2);
    REQUIRE(bundle_.getFrameIDs(first_id_) == std::vector<FrameID>{100, 101});

    bundle_.terminateTrack(first_id_);
    REQUIRE(bundle_.getTerminatedIDs() == std::vector<SetID>{first_id_});

    bundle_.clearInactive({first_id_});
    REQUIRE(bundle_.contains(first_id_));
    REQUIRE_FALSE(bundle_.contains(second_id_));
    REQUIRE(bundle_.activeCount() == 1);
}

TEST_CASE("CFeatureTrackBundle2D copies bundle-allocated initial-observation tracks with assigned IDs", "[wrapped]")
{
    CFeatureTrackBundle2D bundle_;

    const SetID id_ = bundle_.allocateTrackWithInitialObservation({2.5, 3.5}, 7);
    const auto track_ = bundle_.getTrackCopy(id_);

    REQUIRE(track_.getID() == id_);
    REQUIRE(track_.getTrackLength() == 1);
    REQUIRE(track_.getFrameIDs() == std::vector<FrameID>{7});
    REQUIRE(track_.getKeypointAtFrame(7).u == Catch::Approx(2.5));
    REQUIRE(track_.getKeypointAtFrame(7).v == Catch::Approx(3.5));
}

TEST_CASE("CCovisibilityGraphWrapper exposes covisibility flow with vectors", "[wrapped]")
{
    CCovisibilityGraphWrapper graph_;

    graph_.pushFrame(1);
    graph_.pushFrame(2);
    graph_.addVisibilityLinks(1, {3, 1, 2, 2});
    graph_.addVisibilityLinks(2, {2, 3, 5});

    REQUIRE(graph_.getVisibleFeatures(1) == std::vector<SetID>{1, 2, 3});
    REQUIRE(graph_.getCovisibleFeatures(1, 2) == std::vector<SetID>{2, 3});

    graph_.clearInactiveFeatures({3});
    REQUIRE(graph_.getVisibleFeatures(1) == std::vector<SetID>{3});
    REQUIRE(graph_.getCovisibleFeatures(1, 2) == std::vector<SetID>{3});
}
