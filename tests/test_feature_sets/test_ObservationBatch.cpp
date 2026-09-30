/// @file test_ObservationBatch.cpp
/// @brief Verifies validated image observations and flat feature-track batches.

#include "slam-primitives/feature_sets/CFeatureTrackBatch.h"
#include "slam-primitives/feature_sets/CImagePointObservation.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#include <Eigen/Core>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <vector>

using slam_primitives::CFeatureTrackBatch;
using slam_primitives::CFeatureTrackID;
using slam_primitives::CFrameID;
using slam_primitives::CImagePointObservation;
using slam_primitives::SFeatureLocation2D;

namespace
{

    auto makeObservation(std::uint32_t frame_value, double u, double v) -> CImagePointObservation
    {
        return CImagePointObservation{CFrameID{frame_value}, SFeatureLocation2D{u, v},
                                      0.25 * Eigen::Matrix2d::Identity()};
    }

    auto makeValidBatch() -> CFeatureTrackBatch
    {
        std::vector<CImagePointObservation> observations;
        observations.reserve(5U);
        observations.push_back(makeObservation(10U, 100.0, 50.0));
        observations.push_back(makeObservation(12U, 101.0, 51.0));
        observations.push_back(makeObservation(20U, 200.0, 80.0));
        observations.push_back(makeObservation(21U, 201.0, 81.0));
        observations.push_back(makeObservation(24U, 202.0, 82.0));

        return CFeatureTrackBatch{{CFeatureTrackID{2U}, CFeatureTrackID{8U}},
                                  {0U, 2U},
                                  {2U, 3U},
                                  std::move(observations)};
    }

} // namespace

static_assert(!std::is_default_constructible_v<CImagePointObservation>);
static_assert(!std::is_default_constructible_v<CFeatureTrackBatch>);

TEST_CASE("CImagePointObservation stores validated pixel uncertainty",
          "[feature_sets][observation]")
{
    Eigen::Matrix2d covariance;
    covariance << 4.0, 1.0, 1.0, 2.0;
    const CImagePointObservation observation{CFrameID{14U}, SFeatureLocation2D{123.5, 67.25},
                                             covariance};

    REQUIRE(observation.getFrameID() == CFrameID{14U});
    REQUIRE(observation.pixel().u == Catch::Approx(123.5));
    REQUIRE(observation.pixel().v == Catch::Approx(67.25));
    REQUIRE(observation.pixelCovariance().isApprox(covariance, 0.0));
}

TEST_CASE("CImagePointObservation accepts singular PSD covariance", "[feature_sets][observation]")
{
    Eigen::Matrix2d singular_covariance;
    singular_covariance << 1.0, 1.0, 1.0, 1.0;

    REQUIRE_NOTHROW(
        (CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{0.0, 0.0}, singular_covariance}));
}

TEST_CASE("CImagePointObservation accepts large finite PSD covariance",
          "[feature_sets][observation]")
{
    const Eigen::Matrix2d large_covariance = 5.0e307 * Eigen::Matrix2d::Identity();
    const CImagePointObservation observation{CFrameID{1U}, SFeatureLocation2D{0.0, 0.0},
                                             large_covariance};

    REQUIRE((observation.pixelCovariance().array() == large_covariance.array()).all());
}

TEST_CASE("CImagePointObservation rejects a negative variance at mixed scale",
          "[feature_sets][observation]")
{
    Eigen::Matrix2d indefinite = Eigen::Matrix2d::Zero();
    indefinite.diagonal() << 1.0e20, -1.0;
    REQUIRE_THROWS_AS((CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, indefinite}),
                      std::invalid_argument);

    const Eigen::Matrix2d small_psd = 1.0e-20 * Eigen::Matrix2d::Identity();
    REQUIRE_NOTHROW((CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, small_psd}));

    Eigen::Matrix2d impossible = Eigen::Matrix2d::Zero();
    impossible(0, 1) = impossible(1, 0) = 1.0e-20;
    REQUIRE_THROWS_AS((CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, impossible}),
                      std::invalid_argument);
}

TEST_CASE("CImagePointObservation rejects invalid pixels and covariance",
          "[feature_sets][observation]")
{
    SFeatureLocation2D invalid_pixel{0.0, 1.0};
    invalid_pixel.u = std::numeric_limits<double>::quiet_NaN();
    REQUIRE_THROWS_AS(
        (CImagePointObservation{CFrameID{1U}, invalid_pixel, Eigen::Matrix2d::Identity()}),
        std::invalid_argument);

    Eigen::Matrix2d nonsymmetric_covariance = Eigen::Matrix2d::Identity();
    nonsymmetric_covariance(0, 1) = 0.5;
    REQUIRE_THROWS_AS(
        (CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, nonsymmetric_covariance}),
        std::invalid_argument);

    Eigen::Matrix2d indefinite_covariance = Eigen::Matrix2d::Identity();
    indefinite_covariance(1, 1) = -0.1;
    REQUIRE_THROWS_AS(
        (CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, indefinite_covariance}),
        std::invalid_argument);

    Eigen::Matrix2d overflow_scaled_covariance = 5.0e307 * Eigen::Matrix2d::Identity();
    overflow_scaled_covariance(0, 1) = 1.0e300;
    REQUIRE_THROWS_AS(
        (CImagePointObservation{CFrameID{1U}, SFeatureLocation2D{}, overflow_scaled_covariance}),
        std::invalid_argument);
}

TEST_CASE("CFeatureTrackBatch exposes deterministic flat track spans",
          "[feature_sets][track_batch]")
{
    const CFeatureTrackBatch batch = makeValidBatch();

    REQUIRE(batch.trackCount() == 2U);
    REQUIRE(batch.observationCount() == 5U);
    REQUIRE(batch.getTrackIDs().size() == 2U);
    REQUIRE(batch.observationOffsets()[0] == 0U);
    REQUIRE(batch.observationOffsets()[1] == 2U);
    REQUIRE(batch.observationCounts()[0] == 2U);
    REQUIRE(batch.observationCounts()[1] == 3U);

    const auto first_track = batch.observationsForTrack(std::size_t{0});
    REQUIRE(first_track.size() == 2U);
    REQUIRE(first_track.front().getFrameID() == CFrameID{10U});
    REQUIRE(first_track.back().getFrameID() == CFrameID{12U});

    const auto second_track = batch.observationsForTrack(CFeatureTrackID{8U});
    REQUIRE(second_track.size() == 3U);
    REQUIRE(second_track.front().pixel().u == Catch::Approx(200.0));
    REQUIRE(second_track.back().getFrameID() == CFrameID{24U});
}

TEST_CASE("CFeatureTrackBatch represents an empty batch explicitly", "[feature_sets][track_batch]")
{
    const CFeatureTrackBatch batch{{}, {}, {}, {}};

    REQUIRE(batch.trackCount() == 0U);
    REQUIRE(batch.observationCount() == 0U);
    REQUIRE(batch.observations().empty());
}

TEST_CASE("CFeatureTrackBatch accepts a single-observation track", "[feature_sets][track_batch]")
{
    const CFeatureTrackBatch batch{
        {CFeatureTrackID{7U}}, {0U}, {1U}, {makeObservation(4U, 12.0, 8.0)}};

    const auto observations = batch.observationsForTrack(CFeatureTrackID{7U});
    REQUIRE(observations.size() == 1U);
    REQUIRE(observations.front().getFrameID() == CFrameID{4U});
}

TEST_CASE("CFeatureTrackBatch rejects inconsistent flat layout", "[feature_sets][track_batch]")
{
    const std::vector<CFeatureTrackID> track_ids{CFeatureTrackID{1U}};
    const std::vector<CImagePointObservation> observations{makeObservation(1U, 1.0, 1.0),
                                                           makeObservation(2U, 2.0, 2.0)};

    REQUIRE_THROWS_AS((CFeatureTrackBatch{track_ids, {}, {}, observations}), std::invalid_argument);
    REQUIRE_THROWS_AS((CFeatureTrackBatch{track_ids, {1U}, {1U}, observations}),
                      std::invalid_argument);
    REQUIRE_THROWS_AS((CFeatureTrackBatch{track_ids, {0U}, {0U}, observations}),
                      std::invalid_argument);
    REQUIRE_THROWS_AS((CFeatureTrackBatch{track_ids, {0U}, {1U}, observations}),
                      std::invalid_argument);
    REQUIRE_THROWS_AS((CFeatureTrackBatch{track_ids, {0U}, {3U}, observations}),
                      std::invalid_argument);
}

TEST_CASE("CFeatureTrackBatch rejects duplicate or unordered track IDs",
          "[feature_sets][track_batch]")
{
    const std::vector<CImagePointObservation> observations{makeObservation(1U, 1.0, 1.0),
                                                           makeObservation(2U, 2.0, 2.0)};

    REQUIRE_THROWS_AS(
        (CFeatureTrackBatch{
            {CFeatureTrackID{3U}, CFeatureTrackID{3U}}, {0U, 1U}, {1U, 1U}, observations}),
        std::invalid_argument);
    REQUIRE_THROWS_AS(
        (CFeatureTrackBatch{
            {CFeatureTrackID{4U}, CFeatureTrackID{2U}}, {0U, 1U}, {1U, 1U}, observations}),
        std::invalid_argument);
}

TEST_CASE("CFeatureTrackBatch rejects duplicate or unordered frame IDs per track",
          "[feature_sets][track_batch]")
{
    REQUIRE_THROWS_AS(
        (CFeatureTrackBatch{{CFeatureTrackID{1U}},
                            {0U},
                            {2U},
                            {makeObservation(5U, 1.0, 1.0), makeObservation(5U, 2.0, 2.0)}}),
        std::invalid_argument);
    REQUIRE_THROWS_AS(
        (CFeatureTrackBatch{{CFeatureTrackID{1U}},
                            {0U},
                            {2U},
                            {makeObservation(8U, 1.0, 1.0), makeObservation(7U, 2.0, 2.0)}}),
        std::invalid_argument);
}

TEST_CASE("CFeatureTrackBatch reports missing tracks and indices", "[feature_sets][track_batch]")
{
    const CFeatureTrackBatch batch = makeValidBatch();

    REQUIRE_THROWS_AS(batch.observationsForTrack(std::size_t{2}), std::out_of_range);
    REQUIRE_THROWS_AS(batch.observationsForTrack(CFeatureTrackID{7U}), std::out_of_range);
}
