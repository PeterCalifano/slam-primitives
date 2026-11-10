/// @file test_slam_primitives_wrapper_interfaces.cpp
/// @brief Check binding-facade identifier widths, conversion and runtime frame retention.
#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>

#include "slam-primitives/wrapped/slam_primitives_wrapper_interfaces.h"

#include <vector>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <utility>

using namespace slam_primitives;
static_assert(std::is_same_v<decltype(std::declval<const CFeatureTrack2D &>().getFrameIDs()),
                             std::vector<std::uint32_t>>);

TEST_CASE("Binding facades retain frames above the signed legacy range", "[wrapped]")
{
    CFeatureTrack2D track{7U};
    const auto last_frame = std::numeric_limits<std::uint32_t>::max();
    REQUIRE_FALSE(track.addKeypointToTrack({1.0, 2.0}, last_frame));
    REQUIRE(track.getFrameIDs() == std::vector<std::uint32_t>{last_frame});
    REQUIRE(track.hasKeypointAtFrame(last_frame));

    CCovisibilityGraphWrapper graph;
    graph.pushFrame(last_frame);
    graph.addVisibilityLinks(last_frame, {7U});
    REQUIRE(graph.getVisibleFeatures(last_frame) == std::vector<std::uint64_t>{7U});
}

TEST_CASE("CFeatureTrack2D exposes feature-track operations with binding-friendly containers",
          "[wrapped]")
{
    CFeatureTrack2D track_(42);

    REQUIRE(track_.getID() == 42);
    REQUIRE_FALSE(track_.isTerminated());
    REQUIRE_FALSE(track_.addKeypointToTrack({1.0, 2.0}, 10));
    REQUIRE_FALSE(track_.addKeypointToTrack({3.0, 4.0}, 11));

    REQUIRE(track_.getTrackLength() == 2);
    REQUIRE(track_.getFrameIDs() == std::vector<std::uint32_t>{10, 11});
    REQUIRE(track_.hasKeypointAtFrame(11));
    REQUIRE(track_.getKeypointAtFrame(11).u == Catch::Approx(3.0));

    track_.setLidar({12.0, 0.5, -0.25});
    REQUIRE(track_.hasLidar());
    REQUIRE(track_.getLidar().range == Catch::Approx(12.0));
}

TEST_CASE("CFeatureTrackBundle2D exposes bundle-track flow without raw spans", "[wrapped]")
{
    CFeatureTrackBundle2D bundle_;

    const std::uint64_t first_id_ = bundle_.allocateTrack();
    const std::uint64_t second_id_ = bundle_.allocateTrack();

    REQUIRE(first_id_ != second_id_);
    REQUIRE(bundle_.activeCount() == 2);
    REQUIRE(bundle_.contains(first_id_));

    REQUIRE_FALSE(bundle_.addObservation(first_id_, {10.0, 20.0}, 100));
    REQUIRE_FALSE(bundle_.addObservation(first_id_, {11.0, 21.0}, 101));
    REQUIRE(bundle_.getTrackLength(first_id_) == 2);
    REQUIRE(bundle_.getFrameIDs(first_id_) == std::vector<std::uint32_t>{100, 101});

    bundle_.terminateTrack(first_id_);
    REQUIRE(bundle_.getTerminatedIDs() == std::vector<std::uint64_t>{first_id_});

    bundle_.clearInactive({first_id_});
    REQUIRE(bundle_.contains(first_id_));
    REQUIRE_FALSE(bundle_.contains(second_id_));
    REQUIRE(bundle_.activeCount() == 1);
}

TEST_CASE("CFeatureTrackBundle2D preserves explicit 64-bit track IDs", "[wrapped]")
{
    CFeatureTrackBundle2D bundle;
    const std::uint64_t high_id = std::uint64_t{1} << 40U;

    REQUIRE(bundle.allocateTrackWithID(high_id) == high_id);
    REQUIRE(bundle.getTrackCopy(high_id).getID() == high_id);
    REQUIRE(bundle.allocateTrack() == high_id + 1U);
    REQUIRE(bundle.allocateTrackWithInitialObservationAndID(high_id + 10U, {4.0, 5.0}, 17) ==
            high_id + 10U);
    REQUIRE(bundle.getTrackLength(high_id + 10U) == 1U);
    REQUIRE_THROWS_AS(bundle.allocateTrackWithID(high_id), std::invalid_argument);
}

TEST_CASE("CCovisibilityGraphWrapper exposes covisibility flow with vectors", "[wrapped]")
{
    CCovisibilityGraphWrapper graph_;

    graph_.pushFrame(1);
    graph_.pushFrame(2);
    graph_.addVisibilityLinks(1, {3, 1, 2, 2});
    graph_.addVisibilityLinks(2, {2, 3, 5});

    REQUIRE(graph_.getVisibleFeatures(1) == std::vector<std::uint64_t>{1, 2, 3});
    REQUIRE(graph_.getCovisibleFeatures(1, 2) == std::vector<std::uint64_t>{2, 3});

    graph_.clearInactiveFeatures({3});
    REQUIRE(graph_.getVisibleFeatures(1) == std::vector<std::uint64_t>{3});
    REQUIRE(graph_.getCovisibleFeatures(1, 2) == std::vector<std::uint64_t>{3});
}

TEST_CASE("CCovisibilityGraphWrapper accepts high track IDs", "[wrapped]")
{
    CCovisibilityGraphWrapper graph;
    const std::uint64_t high_id = std::uint64_t{1} << 40U;
    graph.pushFrame(1);
    graph.addVisibilityLinks(1, {high_id});
    REQUIRE(graph.getVisibleFeatures(1) == std::vector<std::uint64_t>{high_id});
}

TEST_CASE("CCovisibilityGraphWrapper exposes validated runtime retention", "[wrapped][window]")
{
    REQUIRE(CCovisibilityGraphWrapper{}.getWindowSize() == 64U);
    CCovisibilityGraphWrapper graph{2U};
    const auto high_id = (std::uint64_t{1} << 53U) + 1U;
    for (std::uint32_t frame = 0U; frame < 3U; ++frame)
    {
        graph.pushFrame(frame);
        graph.addVisibilityLinks(frame, {high_id});
    }
    REQUIRE(graph.getVisibleFeatures(0U).empty());
    REQUIRE(graph.getCovisibleFeatures(1U, 2U) == std::vector<std::uint64_t>{high_id});
    graph.setWindowSize(1U);
    REQUIRE(graph.getWindowSize() == 1U);
    REQUIRE(graph.frameCount() == 1U);
    REQUIRE(graph.getVisibleFeatures(1U).empty());
    REQUIRE(graph.getVisibleFeatures(2U) == std::vector<std::uint64_t>{high_id});
    for (const auto invalid : {0U, 65U, std::numeric_limits<std::uint32_t>::max()})
    {
        REQUIRE_THROWS_AS(CCovisibilityGraphWrapper{invalid}, std::invalid_argument);
        REQUIRE_THROWS_AS(graph.setWindowSize(invalid), std::invalid_argument);
        REQUIRE(graph.getWindowSize() == 1U);
        REQUIRE(graph.getVisibleFeatures(2U) == std::vector<std::uint64_t>{high_id});
    }
}
