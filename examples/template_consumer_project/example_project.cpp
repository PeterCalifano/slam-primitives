#include "example_project.h"

#include <slam-primitives/logging/CLogger.h>

int main()
{
    using namespace slam_primitives;

    using Track = CFeatureTrack<SFeatureLocation2D, 64>;
    CFeatureSetBundle<Track, 32> objBundle_;

    Track objTrack_(CFeatureTrackID{0});
    objTrack_.addKeypointToTrack({100.0, 200.0}, CFrameID{0U});
    objTrack_.addKeypointToTrack({101.5, 201.2}, CFrameID{1U});

    const CFeatureTrackID uiTrackId_ = objBundle_.allocate(std::move(objTrack_));
    logging::CLogger objLogger_("consumer", logging::ELogLevel::Info);
    objLogger_.info("Allocated track with track ID=", uiTrackId_.value(),
                    ", length=", objBundle_.get(uiTrackId_).getTrackLength());

    return 0;
}
