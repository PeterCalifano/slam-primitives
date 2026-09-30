#pragma once
#include <catch2/catch_test_macros.hpp>
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/types/identifiers.h"
#include "slam-primitives/feature_sets/CFeatureTrack.h"
#include "slam-primitives/bundle/CFeatureSetBundle.h"

namespace fixtures
{

    using TestTrack = slam_primitives::CFeatureTrack<slam_primitives::SFeatureLocation2D, 8>;
    using TestBundle = slam_primitives::CFeatureSetBundle<TestTrack, 16>;

    inline auto makeTrackWithKeypoints(slam_primitives::CFeatureTrackID id,
                                       uint32_t count) -> TestTrack
    {
        TestTrack t(id);
        for (uint32_t i = 0; i < count; ++i)
        {
            t.addKeypointToTrack({static_cast<double>(i), static_cast<double>(i * 2)},
                                 slam_primitives::CFrameID{i});
        }
        return t;
    }

} // namespace fixtures
