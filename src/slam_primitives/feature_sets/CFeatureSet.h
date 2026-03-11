#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <stdexcept>
#include "slam_primitives/types/concepts.h"

namespace slam_primitives
{

/// @brief Fixed-capacity ordered collection of 2D feature locations.
///
/// Stores up to MAX_SIZE keypoints in insertion order. addKeypoint() returns
/// true when the set reaches capacity; further additions are no-ops.
/// Satisfies the FeatureSetLike concept (always reports non-terminated).
///
/// Used as the base class for CFeatureTrack and can also be used standalone
/// to represent a single-frame feature detection result.
///
/// @tparam LocT      Feature location type (must satisfy FeatureLocation).
/// @tparam MAX_SIZE  Maximum number of keypoints (compile-time capacity).
template <FeatureLocation LocT, uint32_t MAX_SIZE = 128>
class CFeatureSet
{
public:
    // CONSTRUCTORS
    /// @brief Construct an empty, non-initialized feature set.
    CFeatureSet() = default;

    /// @brief Construct an empty feature set with an explicit identifier.
    /// @param id Unique identifier associated with this feature set.
    explicit CFeatureSet(uint32_t id) : set_id_(id), is_initialized_(true) {}

    /// @brief Add a keypoint to the feature set.
    ///
    /// If the set is already full, this call is a no-op and returns true.
    /// @param kp Keypoint to append at the next insertion position.
    /// @return true if the set is full after the call, false otherwise.
    auto addKeypoint(LocT kp) -> bool
    {
        if (is_full_)
        {
            return true;
        }

        // Add keypoint and update state
        keypoints_[pointer_to_next_] = kp;
        ++pointer_to_next_;
        if (pointer_to_next_ >= MAX_SIZE)
        {
            is_full_ = true;
        }
        return is_full_;
    }

    /// @brief Access the keypoint at a specific index.
    /// @param idx Zero-based keypoint index.
    /// @return Const reference to the keypoint at @p idx.
    /// @throws std::out_of_range If @p idx is greater than or equal to size().
    auto getKeypoint(uint32_t idx) const -> const LocT&
    {
        if (idx >= pointer_to_next_)
        {
            throw std::out_of_range("CFeatureSet::getKeypoint: index out of range");
        }
        return keypoints_[idx];
    }

    /// @brief Get a read-only view of all currently stored keypoints.
    /// @return Span over valid keypoints in insertion order with length size().
    auto getKeypoints() const -> std::span<const LocT>
    {
        return std::span<const LocT>(keypoints_.data(), pointer_to_next_);
    }

    /// @brief Get the identifier associated with this feature set.
    /// @return Feature-set identifier.
    auto getID() const -> uint32_t { return set_id_; }

    /// @brief Get the current number of keypoints stored in the feature set.
    /// @return Number of valid keypoints.
    auto size() const -> uint32_t { return pointer_to_next_; }

    /// @brief Get the compile-time maximum keypoint capacity.
    /// @return Maximum number of keypoints that can be stored.
    static constexpr auto capacity() -> uint32_t { return MAX_SIZE; }

    /// @brief Check whether this feature set has been explicitly initialized.
    /// @return true if constructed with an explicit identifier, false otherwise.
    auto isInitialized() const -> bool { return is_initialized_; }

    /// @brief Feature-set termination status required by FeatureSetLike.
    /// @return Always false for CFeatureSet (termination applies to derived tracks).
    auto isTerminated() const -> bool { return false; }

protected:
    // PROTECTED DATA MEMBERS
    std::array<LocT, MAX_SIZE> keypoints_{};
    uint32_t pointer_to_next_{0};
    uint32_t set_id_{0};
    bool is_full_{false};
    bool is_initialized_{false};
};

} // namespace slam_primitives
