/// @file test_StrongIDs.cpp
/// @brief Verifies explicit, checked frame and feature-track identifier boundaries.

#include "slam-primitives/types/identifiers.h"

#include <catch2/catch_test_macros.hpp>

#include <cstdint>
#include <functional>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <unordered_map>

using slam_primitives::CFeatureTrackID;
using slam_primitives::CFrameID;
using slam_primitives::checkedSetIDToUint32;
using slam_primitives::FrameID;
using slam_primitives::SetID;

static_assert(std::is_default_constructible_v<CFrameID>);
static_assert(!std::is_convertible_v<std::uint32_t, CFrameID>);
static_assert(!std::is_convertible_v<CFrameID, std::uint32_t>);
static_assert(!std::is_constructible_v<CFrameID, double>);
static_assert(!std::is_constructible_v<CFrameID, bool>);
static_assert(std::is_trivially_copyable_v<CFrameID>);

static_assert(!std::is_default_constructible_v<CFeatureTrackID>);
static_assert(!std::is_convertible_v<std::uint32_t, CFeatureTrackID>);
static_assert(!std::is_convertible_v<CFeatureTrackID, std::uint32_t>);
static_assert(std::is_trivially_copyable_v<CFeatureTrackID>);
static_assert(sizeof(SetID) == sizeof(std::uint64_t));
static_assert(std::is_same_v<CFeatureTrackID::ValueType, std::uint64_t>);
static_assert(!std::is_convertible_v<SetID, CFeatureTrackID>);
static_assert(!std::is_convertible_v<CFeatureTrackID, SetID>);

TEST_CASE("CFrameID provides ordered strong values", "[types][strong_id]")
{
    const CFrameID first_frame{};
    const CFrameID earlier{7U};
    const CFrameID later{11U};

    REQUIRE(first_frame == CFrameID{0U});
    REQUIRE(earlier.value() == 7U);
    REQUIRE(earlier == CFrameID{7U});
    REQUIRE(earlier < later);
    REQUIRE(CFrameID{std::numeric_limits<std::uint32_t>::max()}.value() ==
            std::numeric_limits<std::uint32_t>::max());
}

TEST_CASE("CFrameID checks the signed legacy boundary", "[types][strong_id]")
{
    const auto largest_legacy = std::numeric_limits<FrameID>::max();
    const auto frame_id = CFrameID::fromLegacy(largest_legacy);

    REQUIRE(frame_id.value() == static_cast<std::uint32_t>(largest_legacy));
    REQUIRE(frame_id.toLegacy() == largest_legacy);
    REQUIRE_THROWS_AS(CFrameID::fromLegacy(FrameID{-1}), std::invalid_argument);

    const CFrameID beyond_legacy{static_cast<std::uint32_t>(largest_legacy) + std::uint32_t{1}};
    REQUIRE_THROWS_AS(beyond_legacy.toLegacy(), std::overflow_error);
}

TEST_CASE("Direct frame construction rejects negative and overflowing integers",
          "[types][strong_id]")
{
    REQUIRE_THROWS_AS(CFrameID(-1), std::invalid_argument);
    REQUIRE_THROWS_AS(CFrameID(std::uint64_t{1} << 32U), std::overflow_error);
    REQUIRE(CFrameID(std::uint64_t{1} << 31U).value() == (std::uint32_t{1} << 31U));
}

TEST_CASE("Track IDs preserve values above the 32-bit range without mixing with set IDs",
          "[types][strong_id]")
{
    const SetID high_set_id = std::uint64_t{1} << 40U;
    const CFeatureTrackID high_track_id{high_set_id};

    REQUIRE(high_track_id.value() == high_set_id);
    REQUIRE(CFeatureTrackID{3U} < CFeatureTrackID{8U});
    REQUIRE_THROWS_AS(high_track_id.toUint32(), std::overflow_error);
    REQUIRE_THROWS_AS(checkedSetIDToUint32(high_set_id), std::overflow_error);
    REQUIRE(CFeatureTrackID{42U}.toUint32() == 42U);
    REQUIRE(checkedSetIDToUint32(SetID{42U}) == 42U);
}

TEST_CASE("Track IDs can key a hash index without becoming set IDs", "[types][strong_id]")
{
    std::unordered_map<CFeatureTrackID, int> observation_counts;
    observation_counts.emplace(CFeatureTrackID{7U}, 2);
    observation_counts.emplace(CFeatureTrackID{8U}, 3);

    REQUIRE(observation_counts.at(CFeatureTrackID{7U}) == 2);
    REQUIRE(observation_counts.at(CFeatureTrackID{8U}) == 3);
}
