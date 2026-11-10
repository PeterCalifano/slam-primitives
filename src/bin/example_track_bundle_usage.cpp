#include <slam-primitives/types/feature_types.h>
#include <slam-primitives/feature_sets/CFeatureTrack.h>
#include <slam-primitives/bundle/CFeatureSetBundle.h>
#include <iostream>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> bundle;

    Track track(CFeatureTrackID{0});
    track.addKeypointToTrack({100.0, 200.0}, CFrameID{0U});
    track.addKeypointToTrack({101.5, 201.2}, CFrameID{1U});

    auto id = bundle.allocate(std::move(track));
    std::cout << "Allocated track with track ID=" << id.value()
              << ", length=" << bundle.get(id).getTrackLength() << "\n";

    return 0;
}
