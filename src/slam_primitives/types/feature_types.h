/// @file feature_types.h
/// @brief Defines pixel locations, associated LiDAR data, and the location contract.

#pragma once

#include <concepts>

namespace slam_primitives
{

    /// @brief Constraint for types representing a 2D feature location in image space.
    /// Requires public members `u` and `v` convertible to double.
    template <typename T>
    concept FeatureLocation = requires(T loc) {
        { loc.u } -> std::convertible_to<double>;
        { loc.v } -> std::convertible_to<double>;
    };

    /// @brief 2D feature location in image coordinates (pixel space).
    /// Satisfies the FeatureLocation concept.
    struct SFeatureLocation2D
    {
        double u{0.0}; ///< Horizontal (column) coordinate [px]
        double v{0.0}; ///< Vertical (row) coordinate [px]
    };

    /// @brief LiDAR measurement associated with a feature track.
    /// Stores spherical coordinates from a LiDAR range measurement that
    /// augments a 2D visual feature with depth information.
    struct SLidarEnhancedData
    {
        double range{0.0};     ///< Range to target [m]
        double azimuth{0.0};   ///< Azimuth angle [rad]
        double elevation{0.0}; ///< Elevation angle [rad]
    };

} // namespace slam_primitives
