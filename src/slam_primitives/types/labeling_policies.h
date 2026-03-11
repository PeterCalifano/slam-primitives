#pragma once
#include <array>
#include <cstdint>
#include <Eigen/Dense>
#include "SFeatureLocation2D.h"

namespace slam_primitives
{

/// @brief Labeling policy that disables per-track 3D labeling.
/// Empty struct; optimized away via [[no_unique_address]] / EBO in CFeatureTrack.
struct SLabelingDisabled
{
    static constexpr bool has_labeling = false;
};

/// @brief Labeling policy that enables per-track 3D labeling.
/// Stores backend-assigned labeled keypoint reprojections and the
/// triangulated 3D point position in the target body frame (TB).
/// @tparam MAX_LENGTH  Maximum track length (must match the owning CFeatureTrack).
template <uint32_t MAX_LENGTH>
struct SLabelingEnabled
{
    static constexpr bool has_labeling = true;
    std::array<SFeatureLocation2D, MAX_LENGTH> labeled_keypoints{}; ///< Backend-labeled reprojections
    Eigen::Vector3d point_position_TB{Eigen::Vector3d::Zero()};     ///< 3D position in target body frame
};

} // namespace slam_primitives
