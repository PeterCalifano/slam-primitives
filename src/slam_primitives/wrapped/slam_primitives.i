namespace slam_primitives
{

    // This file is the source gtwrap interface. Generated wrapper .cpp files are
    // build artifacts and must not be checked in.
    //
    // Keep this surface concrete and binding-friendly: expose fixed-capacity facade
    // classes and std::vector APIs here, while the core headers remain templated and
    // span-oriented for native C++ users.
    //
    // MATLAB caveat: gtwrap can generate code for these std::vector signatures, but
    // the generated MATLAB surface uses gtwrap std.vector... handle classes. Plain
    // MATLAB numeric arrays are not supported by this interface yet.

#include <slam-primitives/types/feature_types.h>
#include <slam-primitives/types/identifiers.h>
#include <slam-primitives/wrapped/slam_primitives_wrapper_interfaces.h>

    class SFeatureLocation2D
    {
        SFeatureLocation2D();

        double u;
        double v;
    };

    class SLidarEnhancedData
    {
        SLidarEnhancedData();

        double range;
        double azimuth;
        double elevation;
    };

    class CFeatureTrack2D
    {
        CFeatureTrack2D();
        CFeatureTrack2D(uint64_t id);

        bool addKeypointToTrack(slam_primitives::SFeatureLocation2D keypoint, uint32_t frame);
        void terminate();
        bool isTerminated() const;
        uint32_t getTrackLength() const;
        uint64_t getID() const;
        uint32_t size() const;
        slam_primitives::SFeatureLocation2D getKeypoint(uint32_t index) const;
        std::vector<uint32_t> getFrameIDs() const;
        bool hasKeypointAtFrame(uint32_t frame) const;
        slam_primitives::SFeatureLocation2D getKeypointAtFrame(uint32_t frame) const;
        void setLidar(slam_primitives::SLidarEnhancedData lidar);
        bool hasLidar() const;
        slam_primitives::SLidarEnhancedData getLidar() const;
    };

    class CFeatureTrackBundle2D
    {
        CFeatureTrackBundle2D();

        uint64_t allocateTrack();
        uint64_t allocateTrackWithID(uint64_t id);
        uint64_t allocateTrackWithInitialObservation(slam_primitives::SFeatureLocation2D keypoint,
                                                     uint32_t frame);
        uint64_t allocateTrackWithInitialObservationAndID(
            uint64_t id, slam_primitives::SFeatureLocation2D keypoint, uint32_t frame);
        bool contains(uint64_t id) const;
        void releaseTrack(uint64_t id);
        uint32_t activeCount() const;
        bool addObservation(uint64_t id, slam_primitives::SFeatureLocation2D keypoint,
                            uint32_t frame);
        void terminateTrack(uint64_t id);
        bool isTerminated(uint64_t id) const;
        uint32_t getTrackLength(uint64_t id) const;
        slam_primitives::CFeatureTrack2D getTrackCopy(uint64_t id) const;
        std::vector<uint32_t> getFrameIDs(uint64_t id) const;
        bool hasKeypointAtFrame(uint64_t id, uint32_t frame) const;
        slam_primitives::SFeatureLocation2D getKeypointAtFrame(uint64_t id, uint32_t frame) const;
        void setLidar(uint64_t id, slam_primitives::SLidarEnhancedData lidar);
        bool hasLidar(uint64_t id) const;
        slam_primitives::SLidarEnhancedData getLidar(uint64_t id) const;
        std::vector<uint64_t> getTerminatedIDs() const;
        std::vector<uint64_t> getActiveIDs();
        void clearInactive(const std::vector<uint64_t> &active_ids);
    };

    class CCovisibilityGraphWrapper
    {
        CCovisibilityGraphWrapper();

        void pushFrame(uint32_t id);
        void addVisibilityLinks(uint32_t frame, const std::vector<uint64_t> &features);
        std::vector<uint64_t> getVisibleFeatures(uint32_t frame) const;
        std::vector<uint64_t> getLastFrameVisibility() const;
        std::vector<uint64_t> getCovisibleFeatures(uint32_t first_frame,
                                                   uint32_t second_frame) const;
        void clearInactiveFeatures(const std::vector<uint64_t> &active_feature_ids);
        uint32_t frameCount() const;
    };

} // namespace slam_primitives
