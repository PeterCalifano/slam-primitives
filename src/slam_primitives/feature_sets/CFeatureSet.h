/// @file CFeatureSet.h
/// @brief Defines a fixed-capacity generic feature set.

#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <utility>
#include "slam-primitives/types/feature_types.h"
#include "slam-primitives/types/identifiers.h"

namespace slam_primitives
{

    /// @brief Fixed-capacity ordered collection of 2D feature locations.
    ///
    /// Stores up to MAX_SIZE keypoints in insertion order. addKeypoint() returns
    /// true when the set reaches capacity; further additions are no-ops.
    /// Satisfies the BundleStorable concept (always reports non-terminated).
    /// Represents a generic, possibly single-frame feature detection result.
    ///
    /// @tparam LocT      Feature location type (must satisfy FeatureLocation).
    /// @tparam MAX_SIZE  Maximum number of keypoints (compile-time capacity).
    template <FeatureLocation LocT, uint32_t MAX_SIZE = 128> class CFeatureSet
    {
      public:
        using IDType = SetID; ///< Generic set identifier domain.

        // CONSTRUCTORS
        /// @brief Construct an empty, non-initialized feature set.
        CFeatureSet() = default;

        /// @brief Construct an empty feature set with an explicit identifier.
        /// @param id Unique identifier associated with this feature set.
        explicit CFeatureSet(IDType id) : id_(id) {}

        /// @brief Copy a feature set, including its assigned or unassigned ID.
        CFeatureSet(const CFeatureSet &) = default;

        /// @brief Move a feature set, including its assigned or unassigned ID.
        CFeatureSet(CFeatureSet &&) = default;

        /// @brief Replace set contents only when an assigned ID remains the same.
        /// @param other Source set.
        /// @return This set.
        /// @throws std::logic_error If this set already has a different ID.
        auto operator=(const CFeatureSet &other) -> CFeatureSet &
        {
            if (this != &other)
            {
                checkAssignableID(other);
                keypoints_ = other.keypoints_;
                pointer_to_next_ = other.pointer_to_next_;
                id_ = other.id_;
                is_full_ = other.is_full_;
            }
            return *this;
        }

        /// @brief Move set contents only when an assigned ID remains the same.
        /// @param other Source set.
        /// @return This set.
        /// @throws std::logic_error If this set already has a different ID.
        auto operator=(CFeatureSet &&other) -> CFeatureSet &
        {
            if (this != &other)
            {
                checkAssignableID(other);
                keypoints_ = std::move(other.keypoints_);
                pointer_to_next_ = other.pointer_to_next_;
                id_ = other.id_;
                is_full_ = other.is_full_;
            }
            return *this;
        }

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
        auto getKeypoint(uint32_t idx) const -> const LocT &
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
        /// @return Assigned identifier in this set's ID domain.
        /// @throws std::logic_error If no ID has been assigned.
        [[nodiscard]] auto getID() const -> IDType
        {
            if (!id_.has_value())
            {
                throw std::logic_error("CFeatureSet::getID: ID is unassigned");
            }
            return *id_;
        }

        /// @brief Assign the feature-set identifier after external allocation.
        /// @param id Unique identifier associated with this feature set.
        /// @throws std::logic_error If an ID is already assigned.
        void setID(IDType id)
        {
            if (id_.has_value())
            {
                throw std::logic_error("CFeatureSet::setID: ID is already assigned");
            }
            id_ = id;
        }

        /// @brief Get the current number of keypoints stored in the feature set.
        /// @return Number of valid keypoints.
        auto size() const -> uint32_t
        {
            return pointer_to_next_;
        }

        /// @brief Get the compile-time maximum keypoint capacity.
        /// @return Maximum number of keypoints that can be stored.
        static constexpr auto capacity() -> uint32_t
        {
            return MAX_SIZE;
        }

        /// @brief Check whether this feature set has an assigned ID.
        /// @return true after constructor, setID(), or bundle assignment.
        [[nodiscard]] auto isInitialized() const noexcept -> bool
        {
            return id_.has_value();
        }

        /// @brief Feature-set termination status required by BundleStorable.
        /// @return Always false; generic feature sets do not terminate.
        auto isTerminated() const -> bool
        {
            return false;
        }

      private:
        void checkAssignableID(const CFeatureSet &other) const
        {
            if (id_.has_value() && id_ != other.id_)
            {
                throw std::logic_error("CFeatureSet::operator=: assigned ID cannot change");
            }
        }

        // PRIVATE DATA MEMBERS
        std::array<LocT, MAX_SIZE> keypoints_{};
        uint32_t pointer_to_next_{0};
        std::optional<SetID> id_{};
        bool is_full_{false};
    };

} // namespace slam_primitives
