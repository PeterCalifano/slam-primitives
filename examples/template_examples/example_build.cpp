#include <slam-primitives/bundle/CFeatureSetBundle.h>
#include <slam-primitives/feature_sets/CFeatureTrack.h>
#include <slam-primitives/types/feature_types.h>

#include <iostream>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> objBundle_;

    Track objTrack_(CFeatureTrackID{0});
    objTrack_.addKeypointToTrack({100.0, 200.0}, CFrameID{0U});
    objTrack_.addKeypointToTrack({101.5, 201.2}, CFrameID{1U});

    const CFeatureTrackID uiTrackId_ = objBundle_.allocate(std::move(objTrack_));
    std::cout << "Allocated track with track ID=" << uiTrackId_.value()
              << ", length=" << objBundle_.get(uiTrackId_).getTrackLength() << "\n";

    return 0;
}
