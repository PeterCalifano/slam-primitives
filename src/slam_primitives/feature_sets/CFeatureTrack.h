#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include "CFeatureSet.h"
#include "slam_primitives/types/concepts.h"
#include "slam_primitives/types/type_aliases.h"
#include "slam_primitives/types/labeling_policies.h"

namespace slam_primitives
{

/// @brief Temporal feature track: a sequence of 2D keypoint observations across frames.
///
/// Extends CFeatureSet with frame-indexed storage, manual/automatic termination,
/// optional LiDAR augmentation, and a configurable labeling policy for backend
/// 3D point association. Auto-terminates when MAX_LENGTH is reached.
///
/// @tparam LocT          Feature location type (must satisfy FeatureLocation).
/// @tparam MAX_LENGTH    Maximum number of observations in the track.
/// @tparam LabelPolicyT  Labeling policy (SLabelingDisabled or SLabelingEnabled<N>).
///                        Disabled policy is optimized away via [[no_unique_address]].
template <FeatureLocation LocT, uint32_t MAX_LENGTH = 128,
          LabelingPolicy LabelPolicyT = SLabelingDisabled>
class CFeatureTrack : public CFeatureSet<LocT, MAX_LENGTH>
{
    using Base = CFeatureSet<LocT, MAX_LENGTH>;

public:
    /// @brief Construct an empty feature track with default-initialized metadata.
    CFeatureTrack() = default;

    /// @brief Construct an empty feature track with a predefined feature-set identifier.
    /// @param id Unique feature-set identifier forwarded to the base class.
    explicit CFeatureTrack(uint32_t id) : Base(id) {}

    /// @brief Append a keypoint observation at the given frame.
    /// @param kp Keypoint observation to append.
    /// @param frame Frame identifier associated with @p kp.
    /// @return true if the track is terminated (either was already, or just reached MAX_LENGTH).
    auto addKeypointToTrack(LocT kp, FrameID frame) -> bool
    {
        if (terminated_)
        {
            return true;
        }
        bool full = Base::addKeypoint(kp);
        frame_ids_[track_length_] = frame;
        ++track_length_;
        if (full)
        {
            terminated_ = true;
        }
        return terminated_;
    }

    /// @brief Manually terminate the track.
    ///
    /// Once terminated, subsequent calls to addKeypointToTrack() return true and do
    /// not append further observations.
    void terminate() { terminated_ = true; }

    /// @brief Check whether the track has been terminated.
    /// @return true if the track is terminated (manually or by reaching MAX_LENGTH).
    auto isTerminated() const -> bool { return terminated_; }

    /// @brief Get the current number of valid observations in the track.
    /// @return Number of stored keypoint/frame pairs.
    auto getTrackLength() const -> uint32_t { return track_length_; }

    /// @brief Get a read-only view of frame IDs associated with stored observations.
    /// @return Span over frame IDs in insertion order with size getTrackLength().
    auto getFrameIDs() const -> std::span<const FrameID>
    {
        return std::span<const FrameID>(frame_ids_.data(), track_length_);
    }

    /// @brief Retrieve the keypoint observed at a specific frame, if present.
    /// @param frame Frame identifier to query.
    /// @return Keypoint for @p frame if found, std::nullopt otherwise.
    auto getKeypointAtFrame(FrameID frame) const -> std::optional<LocT>
    {
        for (uint32_t i = 0; i < track_length_; ++i)
        {
            if (frame_ids_[i] == frame)
            {
                return Base::keypoints_[i];
            }
        }
        return std::nullopt;
    }

    /// @brief Access mutable labeling policy payload associated with this track.
    /// @return Reference to policy-defined labeling data.
    auto getLabelingData() -> LabelPolicyT& { return labeling_data_; }

    /// @brief Access read-only labeling policy payload associated with this track.
    /// @return Const reference to policy-defined labeling data.
    auto getLabelingData() const -> const LabelPolicyT& { return labeling_data_; }

    /// @brief Attach LiDAR-enhanced metadata to this track.
    /// @param lidar LiDAR enhancement payload to store.
    void setLidar(SLidarEnhancedData lidar) { lidar_ = lidar; }

    /// @brief Access optional LiDAR-enhanced metadata associated with this track.
    /// @return Const reference to an optional LiDAR payload.
    auto getLidar() const -> const std::optional<SLidarEnhancedData>& { return lidar_; }

private:
// PRIVATE DATA MEMBERS
    std::array<FrameID, MAX_LENGTH> frame_ids_{};
    uint32_t track_length_{0};
    bool terminated_{false};
    [[no_unique_address]] LabelPolicyT labeling_data_{};
    std::optional<SLidarEnhancedData> lidar_{};
};

} // namespace slam_primitives
