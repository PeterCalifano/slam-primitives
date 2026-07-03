#pragma once
/**
 * @file slam_primitives_wrapper_interfaces.h
 * @brief Concrete binding-friendly facades for the template-heavy SLAM primitives.
 *
 * Why this wrapper exists:
 * - The core `slam-primitives` target is intentionally header-only and exposes
 *   native C++ APIs: fixed-capacity templates, `std::span`, optional return
 *   values, and compile-time capacities.
 * - Generated language bindings need a concrete ABI surface. Python and MATLAB
 *   wrappers cannot conveniently bind every template instantiation or span
 *   contract directly.
 * - These facades keep the native classes as the source of truth while exposing
 *   selected concrete 2D/vector-returning flows for gtwrap.
 *
 * Enabling a binding builds a separate generated module target. It does not add
 * checked-in wrapper `.cpp` files and does not change the core library target
 * from header-only `INTERFACE` usage.
 *
 * MATLAB caveat: gtwrap can parse and generate MATLAB wrapper code for these
 * `std::vector` methods, but the generated MATLAB API currently uses gtwrap
 * `std.vector...` handle classes rather than plain MATLAB numeric arrays. The
 * facade therefore guarantees a concrete C++ wrapper ABI, not MATLAB-native
 * vector ergonomics.
 */

#include "slam_primitives/bundle/CFeatureSetBundle.h"
#include "slam_primitives/covisibility/CCovisibilityGraph.h"
#include "slam_primitives/feature_sets/CFeatureTrack.h"
#include "slam_primitives/types/SFeatureLocation2D.h"
#include "slam_primitives/types/type_aliases.h"

#include <algorithm>
#include <span>
#include <stdexcept>
#include <utility>
#include <vector>

namespace slam_primitives
{

    /**
     * @brief 2D feature-track facade with concrete capacity and vector accessors.
     *
     * Missing optional values are converted to exceptions for binding callers.
     * The native track remains accessible for C++ tests and future internal
     * bridge code, but the gtwrap interface binds only the binding-friendly API.
     */
    class CFeatureTrack2D
    {
      public:
        /// @brief Native track type wrapped by this facade.
        using TrackT = CFeatureTrack<SFeatureLocation2D, 128>;

        /// @brief Construct an empty track facade with the native default SetID.
        CFeatureTrack2D() = default;

        /// @brief Construct an empty track facade with an explicit SetID.
        /// @param id Feature-track identifier stored in the native track.
        explicit CFeatureTrack2D(SetID id) : track_(id) {}

        /// @brief Wrap an existing native track.
        /// @param track Native track moved into the facade.
        explicit CFeatureTrack2D(TrackT track) : track_(std::move(track)) {}

        /// @brief Append a 2D keypoint observation at a frame.
        /// @param keypoint Image-plane keypoint location.
        /// @param frame Frame identifier associated with @p keypoint.
        /// @return true if the native track is terminated after the call.
        auto addKeypointToTrack(SFeatureLocation2D keypoint, FrameID frame) -> bool
        {
            return track_.addKeypointToTrack(keypoint, frame);
        }

        /// @brief Manually terminate the wrapped track.
        void terminate() { track_.terminate(); }

        /// @brief Check whether the wrapped track is terminated.
        auto isTerminated() const -> bool { return track_.isTerminated(); }

        /// @brief Return the number of observations stored in the track.
        auto getTrackLength() const -> uint32_t { return track_.getTrackLength(); }

        /// @brief Return the SetID stored in the native track.
        auto getID() const -> SetID { return track_.getID(); }

        /// @brief Return the number of stored keypoints.
        auto size() const -> uint32_t { return track_.size(); }

        /// @brief Return the keypoint at a zero-based observation index.
        /// @throws std::out_of_range when @p index is outside the stored range.
        auto getKeypoint(uint32_t index) const -> SFeatureLocation2D
        {
            return track_.getKeypoint(index);
        }

        /// @brief Return frame IDs in observation order.
        ///
        /// The native API returns a span. The facade returns an owning vector so
        /// generated bindings do not expose view lifetimes.
        auto getFrameIDs() const -> std::vector<FrameID>
        {
            const auto frame_ids_ = track_.getFrameIDs();
            return {frame_ids_.begin(), frame_ids_.end()};
        }

        /// @brief Check whether an observation exists at a frame.
        auto hasKeypointAtFrame(FrameID frame) const -> bool
        {
            return track_.getKeypointAtFrame(frame).has_value();
        }

        /// @brief Return the keypoint observed at a frame.
        /// @throws std::out_of_range when @p frame is absent.
        auto getKeypointAtFrame(FrameID frame) const -> SFeatureLocation2D
        {
            auto keypoint_ = track_.getKeypointAtFrame(frame);
            if (!keypoint_.has_value())
            {
                throw std::out_of_range("CFeatureTrack2D::getKeypointAtFrame: frame not found");
            }
            return *keypoint_;
        }

        /// @brief Attach LiDAR augmentation metadata to the track.
        void setLidar(SLidarEnhancedData lidar) { track_.setLidar(lidar); }

        /// @brief Check whether LiDAR augmentation metadata is available.
        auto hasLidar() const -> bool { return track_.getLidar().has_value(); }

        /// @brief Return LiDAR augmentation metadata.
        /// @throws std::out_of_range when LiDAR metadata has not been set.
        auto getLidar() const -> SLidarEnhancedData
        {
            const auto &lidar_ = track_.getLidar();
            if (!lidar_.has_value())
            {
                throw std::out_of_range("CFeatureTrack2D::getLidar: LiDAR data not set");
            }
            return *lidar_;
        }

        /**
         * @brief Access the underlying native track.
         *
         * This method is intentionally not listed in the gtwrap interface. It is
         * present for C++ integration tests and adapter code that must cross the
         * facade/native boundary without copying.
         */
        auto native() -> TrackT & { return track_; }
        auto native() const -> const TrackT & { return track_; }

      private:
        TrackT track_{};
    };

    /**
     * @brief Fixed-capacity bundle facade for language feature-track flows.
     *
     * The facade hides span-based inputs and outputs behind std::vector so
     * callers can allocate, update, terminate, and prune tracks from generated
     * bindings without depending on C++ template parameters.
     */
    class CFeatureTrackBundle2D
    {
      public:
        /// @brief Native track type stored by the bundle facade.
        using TrackT = CFeatureTrack2D::TrackT;

        /// @brief Native fixed-capacity bundle type wrapped by this facade.
        using BundleT = CFeatureSetBundle<TrackT, 512>;

        /// @brief Construct an empty bundle facade.
        CFeatureTrackBundle2D() = default;

        /// @brief Allocate an empty native track in the bundle.
        /// @return Newly assigned SetID.
        auto allocateTrack() -> SetID
        {
            TrackT track_;
            return bundle_.allocate(std::move(track_));
        }

        /// @brief Allocate a track initialized with one observation.
        /// @param keypoint First keypoint observation.
        /// @param frame Frame identifier for @p keypoint.
        /// @return Newly assigned SetID.
        auto allocateTrackWithInitialObservation(SFeatureLocation2D keypoint, FrameID frame) -> SetID
        {
            TrackT track_;
            track_.addKeypointToTrack(keypoint, frame);
            return bundle_.allocate(std::move(track_));
        }

        /// @brief Check whether a SetID is currently active in the bundle.
        auto contains(SetID id) const -> bool { return bundle_.contains(id); }

        /// @brief Release the track associated with a SetID.
        /// @throws std::out_of_range when @p id is unknown.
        void releaseTrack(SetID id) { bundle_.free(id); }

        /// @brief Return the number of active tracks in the bundle.
        auto activeCount() const -> uint32_t { return bundle_.activeCount(); }

        /// @brief Append an observation to an active track.
        /// @return true if the target track is terminated after the call.
        /// @throws std::out_of_range when @p id is unknown.
        auto addObservation(SetID id, SFeatureLocation2D keypoint, FrameID frame) -> bool
        {
            return bundle_.get(id).addKeypointToTrack(keypoint, frame);
        }

        /// @brief Manually terminate a track.
        /// @throws std::out_of_range when @p id is unknown.
        void terminateTrack(SetID id) { bundle_.get(id).terminate(); }

        /// @brief Check whether a track is terminated.
        /// @throws std::out_of_range when @p id is unknown.
        auto isTerminated(SetID id) const -> bool { return bundle_.get(id).isTerminated(); }

        /// @brief Return the observation count for a track.
        /// @throws std::out_of_range when @p id is unknown.
        auto getTrackLength(SetID id) const -> uint32_t { return bundle_.get(id).getTrackLength(); }

        /// @brief Return a copy of a track as a facade object.
        /// @throws std::out_of_range when @p id is unknown.
        auto getTrackCopy(SetID id) const -> CFeatureTrack2D
        {
            return CFeatureTrack2D(bundle_.get(id));
        }

        /// @brief Return frame IDs for a track in observation order.
        /// @throws std::out_of_range when @p id is unknown.
        auto getFrameIDs(SetID id) const -> std::vector<FrameID>
        {
            const auto frame_ids_ = bundle_.get(id).getFrameIDs();
            return {frame_ids_.begin(), frame_ids_.end()};
        }

        /// @brief Check whether a track has an observation at a frame.
        /// @throws std::out_of_range when @p id is unknown.
        auto hasKeypointAtFrame(SetID id, FrameID frame) const -> bool
        {
            return bundle_.get(id).getKeypointAtFrame(frame).has_value();
        }

        /// @brief Return the keypoint for a track/frame pair.
        /// @throws std::out_of_range when @p id or @p frame is absent.
        auto getKeypointAtFrame(SetID id, FrameID frame) const -> SFeatureLocation2D
        {
            auto keypoint_ = bundle_.get(id).getKeypointAtFrame(frame);
            if (!keypoint_.has_value())
            {
                throw std::out_of_range("CFeatureTrackBundle2D::getKeypointAtFrame: frame not found");
            }
            return *keypoint_;
        }

        /// @brief Attach LiDAR augmentation metadata to a track.
        /// @throws std::out_of_range when @p id is unknown.
        void setLidar(SetID id, SLidarEnhancedData lidar) { bundle_.get(id).setLidar(lidar); }

        /// @brief Check whether a track has LiDAR augmentation metadata.
        /// @throws std::out_of_range when @p id is unknown.
        auto hasLidar(SetID id) const -> bool { return bundle_.get(id).getLidar().has_value(); }

        /// @brief Return LiDAR augmentation metadata for a track.
        /// @throws std::out_of_range when @p id is unknown or metadata is absent.
        auto getLidar(SetID id) const -> SLidarEnhancedData
        {
            const auto &lidar_ = bundle_.get(id).getLidar();
            if (!lidar_.has_value())
            {
                throw std::out_of_range("CFeatureTrackBundle2D::getLidar: LiDAR data not set");
            }
            return *lidar_;
        }

        /// @brief Return IDs of active tracks currently marked terminated.
        auto getTerminatedIDs() const -> std::vector<SetID>
        {
            auto ids_ = bundle_.getTerminatedIDs();
            std::sort(ids_.begin(), ids_.end());
            return ids_;
        }

        /// @brief Return IDs of all active tracks.
        auto getActiveIDs() -> std::vector<SetID>
        {
            std::vector<SetID> ids_;
            bundle_.forEachActive([&ids_](SetID id, TrackT &)
                                  { ids_.push_back(id); });
            std::sort(ids_.begin(), ids_.end());
            return ids_;
        }

        /// @brief Release all tracks whose SetID is not listed in @p active_ids.
        void clearInactive(const std::vector<SetID> &active_ids)
        {
            // The native API consumes a span; the facade owns no storage beyond
            // this call and therefore creates the span directly from the vector.
            bundle_.clearInactive(std::span<const SetID>(active_ids.data(), active_ids.size()));
        }

      private:
        BundleT bundle_{};
    };

    /**
     * @brief Covisibility graph facade with vector inputs and outputs.
     *
     * This is the language-binding path for frame visibility updates, covisible
     * feature queries, and active-feature pruning.
     */
    class CCovisibilityGraphWrapper
    {
      public:
        /// @brief Native graph type wrapped by this facade.
        using GraphT = CCovisibilityGraph<64>;

        /// @brief Construct an empty covisibility graph facade.
        CCovisibilityGraphWrapper() = default;

        /// @brief Add a frame to the sliding covisibility window.
        void pushFrame(FrameID id) { graph_.pushFrame(id); }

        /// @brief Mark a set of features visible in a frame.
        ///
        /// Unknown frames are ignored by the native graph.
        void addVisibilityLinks(FrameID frame, const std::vector<SetID> &features)
        {
            // Keep the binding ABI vector-based while forwarding a zero-copy
            // span to the native graph implementation.
            graph_.addVisibilityLinks(frame, std::span<const SetID>(features.data(), features.size()));
        }

        /// @brief Return features visible in a frame.
        auto getVisibleFeatures(FrameID frame) const -> std::vector<SetID>
        {
            return toVector(graph_.getVisibleFeatures(frame));
        }

        /// @brief Return features visible in the most recently pushed frame.
        auto getLastFrameVisibility() const -> std::vector<SetID>
        {
            return toVector(graph_.getLastFrameVisibility());
        }

        /// @brief Return sorted features visible in both input frames.
        auto getCovisibleFeatures(FrameID first_frame, FrameID second_frame) const -> std::vector<SetID>
        {
            return graph_.getCovisibleFeatures(first_frame, second_frame);
        }

        /// @brief Remove all feature visibility entries not listed as active.
        void clearInactiveFeatures(const std::vector<SetID> &active_feature_ids)
        {
            // See addVisibilityLinks: the facade boundary owns binding-friendly
            // containers; the native graph keeps the span-based contract.
            graph_.clearInactiveFeatures(std::span<const SetID>(active_feature_ids.data(), active_feature_ids.size()));
        }

        /// @brief Return the number of frames retained in the graph.
        auto frameCount() const -> uint32_t { return graph_.frameCount(); }

      private:
        static auto toVector(std::span<const SetID> values) -> std::vector<SetID>
        {
            return {values.begin(), values.end()};
        }

        GraphT graph_{};
    };

} // namespace slam_primitives
