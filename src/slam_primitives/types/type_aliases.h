#pragma once
#include <cstdint>

namespace slam_primitives
{

using SetID = uint32_t;   ///< Unique identifier for a feature set/track within a bundle
using FrameID = int32_t;  ///< Signed frame index (negative values reserved for invalid/unset)

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
