#pragma once
#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/types/SFeatureLocation2D.h"
#include "slam_primitives/types/type_aliases.h"
#include "slam_primitives/feature_sets/CFeatureTrack.h"
#include "slam_primitives/bundle/CFeatureSetBundle.h"

namespace fixtures
{

using TestTrack = slam_primitives::CFeatureTrack<slam_primitives::SFeatureLocation2D, 8>;
using TestBundle = slam_primitives::CFeatureSetBundle<TestTrack, 16>;

inline auto makeTrackWithKeypoints(uint32_t id, uint32_t count) -> TestTrack
{
    TestTrack t(id);
    for (uint32_t i = 0; i < count; ++i)
    {
        t.addKeypointToTrack(
            {static_cast<double>(i), static_cast<double>(i * 2)},
            static_cast<slam_primitives::FrameID>(i));
    }
    return t;
}

} // namespace fixtures
