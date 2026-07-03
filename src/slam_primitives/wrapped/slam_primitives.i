namespace slam_primitives {

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

#include <slam_primitives/types/SFeatureLocation2D.h>
#include <slam_primitives/types/type_aliases.h>
#include <slam_primitives/wrapped/slam_primitives_wrapper_interfaces.h>

class SFeatureLocation2D {
  SFeatureLocation2D();

  double u;
  double v;
};

class SLidarEnhancedData {
  SLidarEnhancedData();

  double range;
  double azimuth;
  double elevation;
};

class CFeatureTrack2D {
  CFeatureTrack2D();
  CFeatureTrack2D(uint32_t id);

  bool addKeypointToTrack(slam_primitives::SFeatureLocation2D keypoint, int32_t frame);
  void terminate();
  bool isTerminated() const;
  uint32_t getTrackLength() const;
  uint32_t getID() const;
  uint32_t size() const;
  slam_primitives::SFeatureLocation2D getKeypoint(uint32_t index) const;
  std::vector<int32_t> getFrameIDs() const;
  bool hasKeypointAtFrame(int32_t frame) const;
  slam_primitives::SFeatureLocation2D getKeypointAtFrame(int32_t frame) const;
  void setLidar(slam_primitives::SLidarEnhancedData lidar);
  bool hasLidar() const;
  slam_primitives::SLidarEnhancedData getLidar() const;
};

class CFeatureTrackBundle2D {
  CFeatureTrackBundle2D();

  uint32_t allocateTrack();
  uint32_t allocateTrackWithInitialObservation(slam_primitives::SFeatureLocation2D keypoint, int32_t frame);
  bool contains(uint32_t id) const;
  void releaseTrack(uint32_t id);
  uint32_t activeCount() const;
  bool addObservation(uint32_t id, slam_primitives::SFeatureLocation2D keypoint, int32_t frame);
  void terminateTrack(uint32_t id);
  bool isTerminated(uint32_t id) const;
  uint32_t getTrackLength(uint32_t id) const;
  slam_primitives::CFeatureTrack2D getTrackCopy(uint32_t id) const;
  std::vector<int32_t> getFrameIDs(uint32_t id) const;
  bool hasKeypointAtFrame(uint32_t id, int32_t frame) const;
  slam_primitives::SFeatureLocation2D getKeypointAtFrame(uint32_t id, int32_t frame) const;
  void setLidar(uint32_t id, slam_primitives::SLidarEnhancedData lidar);
  bool hasLidar(uint32_t id) const;
  slam_primitives::SLidarEnhancedData getLidar(uint32_t id) const;
  std::vector<uint32_t> getTerminatedIDs() const;
  std::vector<uint32_t> getActiveIDs();
  void clearInactive(const std::vector<uint32_t>& active_ids);
};

class CCovisibilityGraphWrapper {
  CCovisibilityGraphWrapper();

  void pushFrame(int32_t id);
  void addVisibilityLinks(int32_t frame, const std::vector<uint32_t>& features);
  std::vector<uint32_t> getVisibleFeatures(int32_t frame) const;
  std::vector<uint32_t> getLastFrameVisibility() const;
  std::vector<uint32_t> getCovisibleFeatures(int32_t first_frame, int32_t second_frame) const;
  void clearInactiveFeatures(const std::vector<uint32_t>& active_feature_ids);
  uint32_t frameCount() const;
};

} // namespace slam_primitives
