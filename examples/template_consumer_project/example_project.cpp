#include "example_project.h"

#include <iostream>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> objBundle_;

    Track objTrack_(0);
    objTrack_.addKeypointToTrack({100.0, 200.0}, 0);
    objTrack_.addKeypointToTrack({101.5, 201.2}, 1);

    const SetID uiTrackId_ = objBundle_.allocate(std::move(objTrack_));
    std::cout << "Allocated track with SetID=" << uiTrackId_
              << ", length=" << objBundle_.get(uiTrackId_).getTrackLength() << "\n";

    return 0;
}
