/// @file SFeatureTrackSnapshot.h
/// @brief ROS-independent value snapshots for two-dimensional feature tracks.

#pragma once

#include <cstdint>
#include <vector>

#include "slam_primitives/feature_sets/CFeatureTrack.h"
#include "slam_primitives/types/SFeatureLocation2D.h"
#include "slam_primitives/types/concepts.h"
#include "slam_primitives/types/type_aliases.h"

namespace slam_primitives
{

    /// @brief One pixel-space feature-track observation associated with a frame.
    struct SFeatureTrackObservation2D
    {
        FrameID frame_id{0};           ///< Frame in which the feature was observed.
        SFeatureLocation2D location{}; ///< Pixel-space feature location in that frame.
    };

    /// @brief ROS-independent value snapshot of a 2D feature track.
    struct SFeatureTrackSnapshot
    {
        SetID track_id{0}; ///< Stable feature-track identifier.
        std::vector<SFeatureTrackObservation2D> observations{};        ///< Chronological frame/location pairs.
        bool is_terminated{false}; ///< Whether the source track has terminated.
    };

    /// @brief Convert a 2D feature track into a value snapshot for external consumers.
    /// @tparam MAX_LENGTH Maximum source-track capacity.
    /// @tparam LabelPolicyT Source-track labeling policy.
    /// @param track Source track whose observations are copied in insertion order.
    /// @return Snapshot containing the source ID, chronological observations, and termination state.
    template <uint32_t MAX_LENGTH, LabelingPolicy LabelPolicyT>
    [[nodiscard]] auto makeFeatureTrackSnapshot(
        const CFeatureTrack<SFeatureLocation2D, MAX_LENGTH, LabelPolicyT> &track) -> SFeatureTrackSnapshot
    {
        SFeatureTrackSnapshot snapshot{
            .track_id = track.getID(),
            .is_terminated = track.isTerminated(),
        };

        const auto track_length = track.getTrackLength();
        snapshot.observations.reserve(track_length);
        const auto locations = track.getKeypoints();
        const auto frame_ids = track.getFrameIDs();

        for (uint32_t observation_index = 0;
             observation_index < track_length;
             ++observation_index)
        {
            snapshot.observations.push_back({
                .frame_id = frame_ids[observation_index],
                .location = locations[observation_index],
            });
        }

        return snapshot;
    }

} // namespace slam_primitives
