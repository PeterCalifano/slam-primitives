/// @file CFeatureTrack.h
/// @brief Defines an independent feature track with paired keypoints and frames.

#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <utility>
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/feature_sets/labeling_policies.h"
#include "slam-primitives/types/identifiers.h"

namespace slam_primitives
{

    /// @brief Temporal feature track: a sequence of 2D keypoint observations across frames.
    ///
    /// Stores keypoints and strictly increasing frame IDs as inseparable pairs.
    /// Auto-terminates at MAX_LENGTH. Generic sets and tracks are independent
    /// value types with different identifier domains.
    ///
    /// @tparam LocT          Feature location type (must satisfy FeatureLocation).
    /// @tparam MAX_LENGTH    Maximum number of observations in the track.
    /// @tparam LabelPolicyT  Labeling policy (SLabelingDisabled or SLabelingEnabled<N>).
    ///                        Disabled policy is optimized away via [[no_unique_address]].
    template <FeatureLocation LocT, uint32_t MAX_LENGTH = 128,
              LabelingPolicy LabelPolicyT = SLabelingDisabled>
    class CFeatureTrack
    {
        static_assert(MAX_LENGTH > 0U, "CFeatureTrack requires positive capacity");

      public:
        using IDType = CFeatureTrackID; ///< Identifier domain for tracks.

        /// @brief Construct an empty feature track with default-initialized metadata.
        CFeatureTrack() = default;

        /// @brief Construct an empty feature track with its track identifier.
        /// @param id Track identity.
        explicit CFeatureTrack(CFeatureTrackID id) : id_(id) {}

        /// @brief Copy the complete track, including paired observations and ID.
        CFeatureTrack(const CFeatureTrack &) = default;

        /// @brief Move the complete track, including paired observations and ID.
        CFeatureTrack(CFeatureTrack &&) = default;

        /// @brief Replace track contents when an assigned ID remains unchanged.
        /// @param other Source track.
        /// @return This track.
        /// @throws std::logic_error If this track has a different assigned ID.
        auto operator=(const CFeatureTrack &other) -> CFeatureTrack &
        {
            if (this != &other)
            {
                checkAssignableID(other);
                keypoints_ = other.keypoints_;
                frame_ids_ = other.frame_ids_;
                track_length_ = other.track_length_;
                terminated_ = other.terminated_;
                labeling_data_ = other.labeling_data_;
                lidar_ = other.lidar_;
                id_ = other.id_;
            }
            return *this;
        }

        /// @brief Move track contents when an assigned ID remains unchanged.
        /// @param other Source track.
        /// @return This track.
        /// @throws std::logic_error If this track has a different assigned ID.
        auto operator=(CFeatureTrack &&other) -> CFeatureTrack &
        {
            if (this != &other)
            {
                checkAssignableID(other);
                keypoints_ = std::move(other.keypoints_);
                frame_ids_ = std::move(other.frame_ids_);
                track_length_ = other.track_length_;
                terminated_ = other.terminated_;
                labeling_data_ = std::move(other.labeling_data_);
                lidar_ = std::move(other.lidar_);
                id_ = other.id_;
            }
            return *this;
        }

        /// @brief Append a keypoint observation at the given frame.
        /// @param kp Keypoint observation to append.
        /// @param frame Frame identifier, strictly greater than the previous one.
        /// @return true if the track is terminated (either was already, or just reached MAX_LENGTH).
        /// @throws std::invalid_argument If an active track receives an old or repeated frame.
        auto addKeypointToTrack(LocT kp, CFrameID frame) -> bool
        {
            if (terminated_)
            {
                return true;
            }
            if (track_length_ > 0U && frame <= frame_ids_[track_length_ - 1U])
            {
                throw std::invalid_argument("CFeatureTrack: frame IDs must increase");
            }
            keypoints_[track_length_] = std::move(kp);
            frame_ids_[track_length_] = frame;
            ++track_length_;
            terminated_ = track_length_ == MAX_LENGTH;
            return terminated_;
        }

        /// @brief Manually terminate the track.
        ///
        /// Once terminated, subsequent calls to addKeypointToTrack() return true and do
        /// not append further observations.
        void terminate() noexcept
        {
            terminated_ = true;
        }

        /// @brief Check whether the track has been terminated.
        /// @return true if the track is terminated (manually or by reaching MAX_LENGTH).
        [[nodiscard]] auto isTerminated() const noexcept -> bool
        {
            return terminated_;
        }

        /// @brief Get the assigned track ID.
        /// @return Strong track identity.
        /// @throws std::logic_error If unassigned.
        [[nodiscard]] auto getID() const -> CFeatureTrackID
        {
            if (!id_)
            {
                throw std::logic_error("CFeatureTrack::getID: ID is unassigned");
            }
            return *id_;
        }

        /// @brief Assign a track ID once.
        /// @param id Track identity.
        /// @throws std::logic_error If already assigned.
        void setID(CFeatureTrackID id)
        {
            if (id_)
            {
                throw std::logic_error("CFeatureTrack::setID: ID is already assigned");
            }
            id_ = id;
        }

        /// @brief Report whether this track has an assigned ID.
        [[nodiscard]] auto isInitialized() const noexcept -> bool
        {
            return id_.has_value();
        }

        /// @brief Get the number of valid keypoint/frame pairs.
        [[nodiscard]] auto size() const noexcept -> uint32_t
        {
            return track_length_;
        }

        /// @brief Get the compile-time pair capacity.
        [[nodiscard]] static constexpr auto capacity() noexcept -> uint32_t
        {
            return MAX_LENGTH;
        }

        /// @brief Get the keypoint at a stored observation position.
        /// @param idx Zero-based index.
        /// @return Read-only keypoint reference.
        /// @throws std::out_of_range If outside the valid pair range.
        [[nodiscard]] auto getKeypoint(uint32_t idx) const -> const LocT &
        {
            if (idx >= track_length_)
            {
                throw std::out_of_range("CFeatureTrack::getKeypoint: index out of range");
            }
            return keypoints_[idx];
        }

        /// @brief Borrow the keypoints in frame order.
        [[nodiscard]] auto getKeypoints() const noexcept -> std::span<const LocT>
        {
            return {keypoints_.data(), track_length_};
        }

        /// @brief Get the current number of valid observations in the track.
        /// @return Number of stored keypoint/frame pairs.
        [[nodiscard]] auto getTrackLength() const noexcept -> uint32_t
        {
            return size();
        }

        /// @brief Get a read-only view of frame IDs associated with stored observations.
        /// @return Span over frame IDs in insertion order with size getTrackLength().
        [[nodiscard]] auto getFrameIDs() const noexcept -> std::span<const CFrameID>
        {
            return std::span<const CFrameID>(frame_ids_.data(), track_length_);
        }

        /// @brief Retrieve the keypoint observed at a specific frame, if present.
        /// @param frame Frame identifier to query.
        /// @return Keypoint for @p frame if found, std::nullopt otherwise.
        [[nodiscard]] auto getKeypointAtFrame(CFrameID frame) const -> std::optional<LocT>
        {
            for (uint32_t i = 0; i < track_length_; ++i)
            {
                if (frame_ids_[i] == frame)
                {
                    return keypoints_[i];
                }
            }
            return std::nullopt;
        }

        /// @brief Access mutable labeling policy payload associated with this track.
        /// @return Reference to policy-defined labeling data.
        auto getLabelingData() -> LabelPolicyT &
        {
            return labeling_data_;
        }

        /// @brief Access read-only labeling policy payload associated with this track.
        /// @return Const reference to policy-defined labeling data.
        auto getLabelingData() const -> const LabelPolicyT &
        {
            return labeling_data_;
        }

        /// @brief Attach LiDAR-enhanced metadata to this track.
        /// @param lidar LiDAR enhancement payload to store.
        void setLidar(SLidarEnhancedData lidar)
        {
            lidar_ = lidar;
        }

        /// @brief Access optional LiDAR-enhanced metadata associated with this track.
        /// @return Const reference to an optional LiDAR payload.
        auto getLidar() const -> const std::optional<SLidarEnhancedData> &
        {
            return lidar_;
        }

      private:
        void checkAssignableID(const CFeatureTrack &other) const
        {
            if (id_ && id_ != other.id_)
            {
                throw std::logic_error("CFeatureTrack::operator=: assigned ID cannot change");
            }
        }

        // PRIVATE DATA MEMBERS
        std::array<LocT, MAX_LENGTH> keypoints_{};
        std::array<CFrameID, MAX_LENGTH> frame_ids_{};
        uint32_t track_length_{0};
        std::optional<CFeatureTrackID> id_{};
        bool terminated_{false};
        [[no_unique_address]] LabelPolicyT labeling_data_{};
        std::optional<SLidarEnhancedData> lidar_{};
    };

} // namespace slam_primitives
