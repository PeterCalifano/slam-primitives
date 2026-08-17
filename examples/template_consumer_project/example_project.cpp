#include "example_project.h"

#include <slam_primitives/logging/CLogger.h>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> objBundle_;

    Track objTrack_(0);
    objTrack_.addKeypointToTrack({100.0, 200.0}, 0);
    objTrack_.addKeypointToTrack({101.5, 201.2}, 1);

    const SetID uiTrackId_ = objBundle_.allocate(std::move(objTrack_));
    logging::CLogger objLogger_("consumer", logging::ELogLevel::Info);
    objLogger_.info(
        "Allocated track with SetID=", uiTrackId_,
        ", length=", objBundle_.get(uiTrackId_).getTrackLength());

    return 0;
}
