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

#include "slam-primitives/bundle/CFeatureSetBundle.h"
#include "slam-primitives/covisibility/CCovisibilityGraph.h"
#include "slam-primitives/feature_sets/CFeatureTrack.h"
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/types/identifiers.h"

#include <algorithm>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <utility>
#include <vector>

// gtwrap includes this header after pybind11 in generated Python translation
// units. Enable vector value conversion there without imposing a pybind11
// dependency on native or MATLAB consumers of this header.
#ifdef PYBIND11_VERSION_MAJOR
#include <pybind11/stl.h>
#endif

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

        /// @brief Construct an empty track facade without an assigned ID.
        CFeatureTrack2D() = default;

        /// @brief Construct an empty track facade with an explicit track ID.
        /// @param id Feature-track identifier stored in the native track.
        explicit CFeatureTrack2D(std::uint64_t id) : track_(CFeatureTrackID{id}) {}

        /// @brief Wrap an existing native track.
        /// @param track Native track moved into the facade.
        explicit CFeatureTrack2D(TrackT track) : track_(std::move(track)) {}

        /// @brief Append a 2D keypoint observation at a frame.
        /// @param keypoint Image-plane keypoint location.
        /// @param frame Frame identifier associated with @p keypoint.
        /// @return true if the native track is terminated after the call.
        auto addKeypointToTrack(SFeatureLocation2D keypoint, std::uint32_t frame) -> bool
        {
            return track_.addKeypointToTrack(keypoint, CFrameID{frame});
        }

        /// @brief Manually terminate the wrapped track.
        void terminate()
        {
            track_.terminate();
        }

        /// @brief Check whether the wrapped track is terminated.
        auto isTerminated() const -> bool
        {
            return track_.isTerminated();
        }

        /// @brief Return the number of observations stored in the track.
        auto getTrackLength() const -> uint32_t
        {
            return track_.getTrackLength();
        }

        /// @brief Return the native track ID as a binding-friendly integer.
        /// @throws std::logic_error If the track is unassigned.
        auto getID() const -> std::uint64_t
        {
            return track_.getID().value();
        }

        /// @brief Return the number of stored keypoints.
        auto size() const -> uint32_t
        {
            return track_.size();
        }

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
        auto getFrameIDs() const -> std::vector<std::uint32_t>
        {
            const auto frame_ids_ = track_.getFrameIDs();
            std::vector<std::uint32_t> values;
            values.reserve(frame_ids_.size());
            for (const auto frame_id : frame_ids_)
            {
                values.push_back(frame_id.value());
            }
            return values;
        }

        /// @brief Check whether an observation exists at a frame.
        auto hasKeypointAtFrame(std::uint32_t frame) const -> bool
        {
            return track_.getKeypointAtFrame(CFrameID{frame}).has_value();
        }

        /// @brief Return the keypoint observed at a frame.
        /// @throws std::out_of_range when @p frame is absent.
        auto getKeypointAtFrame(std::uint32_t frame) const -> SFeatureLocation2D
        {
            auto keypoint_ = track_.getKeypointAtFrame(CFrameID{frame});
            if (!keypoint_.has_value())
            {
                throw std::out_of_range("CFeatureTrack2D::getKeypointAtFrame: frame not found");
            }
            return *keypoint_;
        }

        /// @brief Attach LiDAR augmentation metadata to the track.
        void setLidar(SLidarEnhancedData lidar)
        {
            track_.setLidar(lidar);
        }

        /// @brief Check whether LiDAR augmentation metadata is available.
        auto hasLidar() const -> bool
        {
            return track_.getLidar().has_value();
        }

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
        auto native() -> TrackT &
        {
            return track_;
        }
        auto native() const -> const TrackT &
        {
            return track_;
        }

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
        /// @return Newly assigned track ID.
        auto allocateTrack() -> std::uint64_t
        {
            TrackT track_;
            return bundle_.allocate(std::move(track_)).value();
        }

        /// @brief Store a track with a caller-supplied ID.
        /// @param id Track ID to preserve in the bundle.
        /// @return The supplied track ID.
        auto allocateTrackWithID(std::uint64_t id) -> std::uint64_t
        {
            return bundle_.allocate(TrackT{CFeatureTrackID{id}}).value();
        }

        /// @brief Allocate a track initialized with one observation.
        /// @param keypoint First keypoint observation.
        /// @param frame Frame identifier for @p keypoint.
        /// @return Newly assigned track ID.
        auto allocateTrackWithInitialObservation(SFeatureLocation2D keypoint,
                                                 std::uint32_t frame) -> std::uint64_t
        {
            TrackT track_;
            track_.addKeypointToTrack(keypoint, CFrameID{frame});
            return bundle_.allocate(std::move(track_)).value();
        }

        /// @brief Store a caller-identified track with its first observation.
        /// @param id Track ID to preserve in the bundle.
        /// @param keypoint First keypoint observation.
        /// @param frame Frame identifier for @p keypoint.
        /// @return The supplied track ID.
        auto allocateTrackWithInitialObservationAndID(std::uint64_t id, SFeatureLocation2D keypoint,
                                                      std::uint32_t frame) -> std::uint64_t
        {
            TrackT track_{CFeatureTrackID{id}};
            track_.addKeypointToTrack(keypoint, CFrameID{frame});
            return bundle_.allocate(std::move(track_)).value();
        }

        /// @brief Check whether a track ID is currently active in the bundle.
        auto contains(std::uint64_t id) const -> bool
        {
            return bundle_.contains(CFeatureTrackID{id});
        }

        /// @brief Release the track associated with a track ID.
        /// @throws std::out_of_range when @p id is unknown.
        void releaseTrack(std::uint64_t id)
        {
            bundle_.free(CFeatureTrackID{id});
        }

        /// @brief Return the number of active tracks in the bundle.
        auto activeCount() const -> uint32_t
        {
            return bundle_.activeCount();
        }

        /// @brief Append an observation to an active track.
        /// @return true if the target track is terminated after the call.
        /// @throws std::out_of_range when @p id is unknown.
        auto addObservation(std::uint64_t id, SFeatureLocation2D keypoint,
                            std::uint32_t frame) -> bool
        {
            return bundle_.get(CFeatureTrackID{id}).addKeypointToTrack(keypoint, CFrameID{frame});
        }

        /// @brief Manually terminate a track.
        /// @throws std::out_of_range when @p id is unknown.
        void terminateTrack(std::uint64_t id)
        {
            bundle_.get(CFeatureTrackID{id}).terminate();
        }

        /// @brief Check whether a track is terminated.
        /// @throws std::out_of_range when @p id is unknown.
        auto isTerminated(std::uint64_t id) const -> bool
        {
            return bundle_.get(CFeatureTrackID{id}).isTerminated();
        }

        /// @brief Return the observation count for a track.
        /// @throws std::out_of_range when @p id is unknown.
        auto getTrackLength(std::uint64_t id) const -> uint32_t
        {
            return bundle_.get(CFeatureTrackID{id}).getTrackLength();
        }

        /// @brief Return a copy of a track as a facade object.
        /// @throws std::out_of_range when @p id is unknown.
        auto getTrackCopy(std::uint64_t id) const -> CFeatureTrack2D
        {
            return CFeatureTrack2D(bundle_.get(CFeatureTrackID{id}));
        }

        /// @brief Return frame IDs for a track in observation order.
        /// @throws std::out_of_range when @p id is unknown.
        auto getFrameIDs(std::uint64_t id) const -> std::vector<std::uint32_t>
        {
            const auto frame_ids_ = bundle_.get(CFeatureTrackID{id}).getFrameIDs();
            std::vector<std::uint32_t> values;
            values.reserve(frame_ids_.size());
            for (const auto frame_id : frame_ids_)
            {
                values.push_back(frame_id.value());
            }
            return values;
        }

        /// @brief Check whether a track has an observation at a frame.
        /// @throws std::out_of_range when @p id is unknown.
        auto hasKeypointAtFrame(std::uint64_t id, std::uint32_t frame) const -> bool
        {
            return bundle_.get(CFeatureTrackID{id}).getKeypointAtFrame(CFrameID{frame}).has_value();
        }

        /// @brief Return the keypoint for a track/frame pair.
        /// @throws std::out_of_range when @p id or @p frame is absent.
        auto getKeypointAtFrame(std::uint64_t id, std::uint32_t frame) const -> SFeatureLocation2D
        {
            auto keypoint_ = bundle_.get(CFeatureTrackID{id}).getKeypointAtFrame(CFrameID{frame});
            if (!keypoint_.has_value())
            {
                throw std::out_of_range(
                    "CFeatureTrackBundle2D::getKeypointAtFrame: frame not found");
            }
            return *keypoint_;
        }

        /// @brief Attach LiDAR augmentation metadata to a track.
        /// @throws std::out_of_range when @p id is unknown.
        void setLidar(std::uint64_t id, SLidarEnhancedData lidar)
        {
            bundle_.get(CFeatureTrackID{id}).setLidar(lidar);
        }

        /// @brief Check whether a track has LiDAR augmentation metadata.
        /// @throws std::out_of_range when @p id is unknown.
        auto hasLidar(std::uint64_t id) const -> bool
        {
            return bundle_.get(CFeatureTrackID{id}).getLidar().has_value();
        }

        /// @brief Return LiDAR augmentation metadata for a track.
        /// @throws std::out_of_range when @p id is unknown or metadata is absent.
        auto getLidar(std::uint64_t id) const -> SLidarEnhancedData
        {
            const auto &lidar_ = bundle_.get(CFeatureTrackID{id}).getLidar();
            if (!lidar_.has_value())
            {
                throw std::out_of_range("CFeatureTrackBundle2D::getLidar: LiDAR data not set");
            }
            return *lidar_;
        }

        /// @brief Return IDs of active tracks currently marked terminated.
        auto getTerminatedIDs() const -> std::vector<std::uint64_t>
        {
            std::vector<std::uint64_t> ids_;
            for (const CFeatureTrackID id : bundle_.getTerminatedIDs())
            {
                ids_.push_back(id.value());
            }
            std::sort(ids_.begin(), ids_.end());
            return ids_;
        }

        /// @brief Return IDs of all active tracks.
        auto getActiveIDs() -> std::vector<std::uint64_t>
        {
            std::vector<std::uint64_t> ids_;
            bundle_.forEachActive([&ids_](CFeatureTrackID id, TrackT &)
                                  { ids_.push_back(id.value()); });
            std::sort(ids_.begin(), ids_.end());
            return ids_;
        }

        /// @brief Release all tracks whose ID is not listed in @p active_ids.
        void clearInactive(const std::vector<std::uint64_t> &active_ids)
        {
            std::vector<CFeatureTrackID> typed_ids;
            typed_ids.reserve(active_ids.size());
            for (const auto id : active_ids)
            {
                typed_ids.emplace_back(id);
            }
            bundle_.clearInactive(typed_ids);
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
        using GraphT = CCovisibilityGraph<64, CFeatureTrackID>;

        /// @brief Construct an empty covisibility graph facade.
        CCovisibilityGraphWrapper() = default;

        /// @brief Add a frame to the sliding covisibility window.
        void pushFrame(std::uint32_t id)
        {
            graph_.pushFrame(CFrameID{id});
        }

        /// @brief Mark a set of features visible in a frame.
        ///
        /// Unknown frames are ignored by the native graph.
        void addVisibilityLinks(std::uint32_t frame, const std::vector<std::uint64_t> &features)
        {
            std::vector<CFeatureTrackID> typed_features;
            typed_features.reserve(features.size());
            for (const auto id : features)
            {
                typed_features.emplace_back(id);
            }
            graph_.addVisibilityLinks(CFrameID{frame}, typed_features);
        }

        /// @brief Return features visible in a frame.
        auto getVisibleFeatures(std::uint32_t frame) const -> std::vector<std::uint64_t>
        {
            return toVector(graph_.getVisibleFeatures(CFrameID{frame}));
        }

        /// @brief Return features visible in the most recently pushed frame.
        auto getLastFrameVisibility() const -> std::vector<std::uint64_t>
        {
            return toVector(graph_.getLastFrameVisibility());
        }

        /// @brief Return sorted features visible in both input frames.
        auto getCovisibleFeatures(std::uint32_t first_frame,
                                  std::uint32_t second_frame) const -> std::vector<std::uint64_t>
        {
            const auto typed_ids =
                graph_.getCovisibleFeatures(CFrameID{first_frame}, CFrameID{second_frame});
            return toVector(typed_ids);
        }

        /// @brief Remove all feature visibility entries not listed as active.
        void clearInactiveFeatures(const std::vector<std::uint64_t> &active_feature_ids)
        {
            std::vector<CFeatureTrackID> typed_ids;
            typed_ids.reserve(active_feature_ids.size());
            for (const auto id : active_feature_ids)
            {
                typed_ids.emplace_back(id);
            }
            graph_.clearInactiveFeatures(typed_ids);
        }

        /// @brief Return the number of frames retained in the graph.
        auto frameCount() const -> uint32_t
        {
            return graph_.frameCount();
        }

      private:
        static auto toVector(std::span<const CFeatureTrackID> values) -> std::vector<std::uint64_t>
        {
            std::vector<std::uint64_t> ids;
            ids.reserve(values.size());
            for (const auto id : values)
            {
                ids.push_back(id.value());
            }
            return ids;
        }

        GraphT graph_{};
    };

} // namespace slam_primitives
