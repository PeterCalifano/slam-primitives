/// @file labeling_policies.h
/// @brief Defines the labeling contract and optional per-track labeling data.

#pragma once
#include <array>
#include <concepts>
#include <cstdint>
#include <Eigen/Core>
#include "slam-primitives/types/feature_types.h"

namespace slam_primitives
{

    /// @brief Constraint for labeling policy types used by CFeatureTrack.
    /// A labeling policy must expose a static `has_labeling` boolean to
    /// enable/disable per-track 3D point storage.
    template <typename T>
    concept LabelingPolicy = requires {
        { T::has_labeling } -> std::convertible_to<bool>;
    };

    /// @brief Labeling policy that disables per-track 3D labeling.
    /// Empty policy stored with [[no_unique_address]] in CFeatureTrack.
    struct SLabelingDisabled
    {
        static constexpr bool has_labeling = false;
    };

    /// @brief Labeling policy that enables per-track 3D labeling.
    /// Stores backend-assigned labeled keypoint reprojections and the
    /// triangulated 3D point position in the target body frame (TB).
    /// @tparam MAX_LENGTH  Maximum track length (must match the owning CFeatureTrack).
    template <uint32_t MAX_LENGTH> struct SLabelingEnabled
    {
        static constexpr bool has_labeling = true;
        std::array<SFeatureLocation2D, MAX_LENGTH>
            labeled_keypoints{}; ///< Backend-labeled reprojections
        Eigen::Vector3d point_position_TB{
            Eigen::Vector3d::Zero()}; ///< 3D position in target body frame
    };

} // namespace slam_primitives
