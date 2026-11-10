/// @file CFeatureTrackBatch.h
/// @brief Defines an owning flat batch of validated feature-track observations.

#pragma once

#include "slam-primitives/feature_sets/CImagePointObservation.h"
#include "slam-primitives/types/identifiers.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <limits>
#include <span>
#include <stdexcept>
#include <utility>
#include <vector>

namespace slam_primitives
{

    /// @brief Owning contiguous representation of multiple chronological feature
    ///        tracks.
    ///
    /// Track IDs are strictly increasing. Offsets and positive counts partition
    /// the observation array contiguously, and frame IDs are strictly increasing
    /// inside each track. The class owns copied/moved values and never exposes live
    /// `CFeatureTrack` storage. Returned spans borrow this batch's storage and
    /// become invalid when the batch is destroyed, moved, or assigned.
    class CFeatureTrackBatch final
    {
      public:
        // CONSTRUCTORS
        /// @brief Construct and validate a flat feature-track batch.
        /// @param track_ids Strictly increasing feature-track identifiers.
        /// @param observation_offsets Zero-based contiguous observation offsets.
        /// @param observation_counts Positive observation count for each track.
        /// @param observations Flat observation storage partitioned by the metadata.
        /// @throws std::invalid_argument If metadata sizes differ, IDs or frames
        ///         are unordered/duplicated, counts are zero, or offsets/counts do
        ///         not partition all observations exactly.
        CFeatureTrackBatch(std::vector<CFeatureTrackID> track_ids,
                           std::vector<std::uint32_t> observation_offsets,
                           std::vector<std::uint32_t> observation_counts,
                           std::vector<CImagePointObservation> observations)
            : track_ids_(std::move(track_ids)),
              observation_offsets_(std::move(observation_offsets)),
              observation_counts_(std::move(observation_counts)),
              observations_(std::move(observations))
        {
            validate();
        }

        // GETTERS
        /// @brief Return the number of tracks in the batch.
        /// @return Track count.
        [[nodiscard]] auto trackCount() const noexcept -> std::size_t
        {
            return track_ids_.size();
        }

        /// @brief Return the total number of observations in the batch.
        /// @return Flat observation count.
        [[nodiscard]] auto observationCount() const noexcept -> std::size_t
        {
            return observations_.size();
        }

        /// @brief Return all track IDs in deterministic order.
        /// @return Read-only span over track IDs.
        [[nodiscard]] auto getTrackIDs() const noexcept -> std::span<const CFeatureTrackID>
        {
            return track_ids_;
        }

        /// @brief Return all zero-based observation offsets.
        /// @return Read-only span over offsets.
        [[nodiscard]] auto observationOffsets() const noexcept -> std::span<const std::uint32_t>
        {
            return observation_offsets_;
        }

        /// @brief Return all per-track observation counts.
        /// @return Read-only span over counts.
        [[nodiscard]] auto observationCounts() const noexcept -> std::span<const std::uint32_t>
        {
            return observation_counts_;
        }

        /// @brief Return the complete flat observation storage.
        /// @return Read-only observation span.
        [[nodiscard]] auto observations() const noexcept -> std::span<const CImagePointObservation>
        {
            return observations_;
        }

        /// @brief Return observations for a zero-based track index.
        /// @param track_index Index into getTrackIDs().
        /// @return Read-only chronological observation span.
        /// @throws std::out_of_range If @p track_index is outside the batch.
        [[nodiscard]] auto observationsForTrack(std::size_t track_index) const
            -> std::span<const CImagePointObservation>
        {
            if (track_index >= track_ids_.size())
            {
                throw std::out_of_range(
                    "CFeatureTrackBatch::observationsForTrack: index out of range");
            }

            const auto offset = static_cast<std::size_t>(observation_offsets_[track_index]);
            const auto count = static_cast<std::size_t>(observation_counts_[track_index]);
            return std::span<const CImagePointObservation>{observations_.data() + offset, count};
        }

        /// @brief Return observations for one strong track identifier.
        /// @param track_id Track identifier to locate by deterministic binary search.
        /// @return Read-only chronological observation span.
        /// @throws std::out_of_range If @p track_id is not present.
        [[nodiscard]] auto observationsForTrack(CFeatureTrackID track_id) const
            -> std::span<const CImagePointObservation>
        {
            const auto iterator = std::lower_bound(track_ids_.begin(), track_ids_.end(), track_id);
            if (iterator == track_ids_.end() || *iterator != track_id)
            {
                throw std::out_of_range(
                    "CFeatureTrackBatch::observationsForTrack: track ID not found");
            }
            return observationsForTrack(
                static_cast<std::size_t>(std::distance(track_ids_.begin(), iterator)));
        }

      private:
        // PRIVATE METHODS
        void validate() const
        {
            // Establish the parallel-metadata shape and the uint32 layout bound
            // before any offset arithmetic is attempted.
            if (observation_offsets_.size() != track_ids_.size() ||
                observation_counts_.size() != track_ids_.size())
            {
                throw std::invalid_argument(
                    "CFeatureTrackBatch: track, offset, and count sizes must match");
            }
            if (observations_.size() >
                static_cast<std::size_t>(std::numeric_limits<std::uint32_t>::max()))
            {
                throw std::invalid_argument(
                    "CFeatureTrackBatch: observation storage exceeds uint32 layout");
            }

            // Strict ordering makes track identity unique and enables logarithmic
            // lookup without maintaining a second index.
            for (std::size_t track_index = 1U; track_index < track_ids_.size(); ++track_index)
            {
                if (!(track_ids_[track_index - 1U] < track_ids_[track_index]))
                {
                    throw std::invalid_argument(
                        "CFeatureTrackBatch: track IDs must be strictly increasing");
                }
            }

            // Validate the complete flat partition in one forward pass while also
            // enforcing chronological observations inside each track.
            std::size_t expected_offset = 0U;
            for (std::size_t track_index = 0U; track_index < track_ids_.size(); ++track_index)
            {
                const auto offset = static_cast<std::size_t>(observation_offsets_[track_index]);
                const auto count = static_cast<std::size_t>(observation_counts_[track_index]);
                if (offset != expected_offset || count == 0U ||
                    count > observations_.size() - expected_offset)
                {
                    throw std::invalid_argument(
                        "CFeatureTrackBatch: offsets and counts must partition observations");
                }

                const auto track_begin =
                    observations_.cbegin() + static_cast<std::ptrdiff_t>(expected_offset);
                const auto track_end = track_begin + static_cast<std::ptrdiff_t>(count);
                const auto nonchronological_pair =
                    std::adjacent_find(track_begin, track_end,
                                       [](const CImagePointObservation &previous_observation,
                                          const CImagePointObservation &current_observation) {
                                           return !(previous_observation.getFrameID() <
                                                    current_observation.getFrameID());
                                       });
                if (nonchronological_pair != track_end)
                {
                    throw std::invalid_argument(
                        "CFeatureTrackBatch: frame IDs must increase within each track");
                }
                expected_offset += count;
            }

            if (expected_offset != observations_.size())
            {
                throw std::invalid_argument(
                    "CFeatureTrackBatch: metadata must cover every observation exactly");
            }
        }

        // PRIVATE DATA MEMBERS
        std::vector<CFeatureTrackID> track_ids_;
        std::vector<std::uint32_t> observation_offsets_;
        std::vector<std::uint32_t> observation_counts_;
        std::vector<CImagePointObservation> observations_;
    };

} // namespace slam_primitives
