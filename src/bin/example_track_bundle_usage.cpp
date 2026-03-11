#include <slam_primitives/types/SFeatureLocation2D.h>
#include <slam_primitives/feature_sets/CFeatureTrack.h>
#include <slam_primitives/bundle/CFeatureSetBundle.h>
#include <iostream>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> bundle;

    Track track(0);
    track.addKeypointToTrack({100.0, 200.0}, 0);
    track.addKeypointToTrack({101.5, 201.2}, 1);

    auto id = bundle.allocate(std::move(track));
    std::cout << "Allocated track with SetID=" << id
              << ", length=" << bundle.get(id).getTrackLength() << "\n";

    return 0;
}
