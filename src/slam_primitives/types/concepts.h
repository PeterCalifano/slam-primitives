#pragma once
#include <concepts>
#include <cstdint>

namespace slam_primitives
{

/// @brief Constraint for types representing a 2D feature location in image space.
/// Requires public members `u` and `v` convertible to double.
template <typename T>
concept FeatureLocation = requires(T loc) {
    { loc.u } -> std::convertible_to<double>;
    { loc.v } -> std::convertible_to<double>;
};

/// @brief Constraint for labeling policy types used by CFeatureTrack.
/// A labeling policy must expose a static `has_labeling` boolean to
/// enable/disable per-track 3D point storage via EBO.
template <typename T>
concept LabelingPolicy = requires {
    { T::has_labeling } -> std::convertible_to<bool>;
};

/// @brief Constraint for types that can be stored in a CFeatureSetBundle.
/// Requires a unique ID accessor and a termination status check.
template <typename SetT>
concept FeatureSetLike = requires(SetT s) {
    { s.getID() } -> std::convertible_to<uint32_t>;
    { s.isTerminated() } -> std::convertible_to<bool>;
};

} // namespace slam_primitives
