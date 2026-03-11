#pragma once
#include <cstdint>

namespace slam_primitives
{

/// @brief Discriminator for the type of feature collection stored in a bundle slot.
enum class ESetType : uint8_t
{
    FEATURE_SET = 0,  ///< Unordered set of keypoints (single-frame)
    FEATURE_TRACK = 1 ///< Temporally ordered sequence of keypoints across frames
};

} // namespace slam_primitives
