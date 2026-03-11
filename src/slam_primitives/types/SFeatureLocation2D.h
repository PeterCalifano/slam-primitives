#pragma once

namespace slam_primitives
{

/// @brief 2D feature location in image coordinates (pixel space).
/// Satisfies the FeatureLocation concept.
struct SFeatureLocation2D
{
    double u{0.0}; ///< Horizontal (column) coordinate [px]
    double v{0.0}; ///< Vertical (row) coordinate [px]
};

} // namespace slam_primitives
