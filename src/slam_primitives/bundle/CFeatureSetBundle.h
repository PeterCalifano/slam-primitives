/// @file CFeatureSetBundle.h
/// @brief Defines fixed-capacity storage keyed by each set's own ID domain.

#pragma once
#include "slam-primitives/types/identifiers.h"
#include <bitset>
#include <concepts>
#include <cstdint>
#include <limits>
#include <optional>
#include <span>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace slam_primitives
{

    /// @brief Static contract for independently owned objects stored in a bundle.
    /// Requires a typed stable ID, one-time assignment, and a termination query.
    template <typename T>
    concept BundleStorable =
        std::movable<T> && requires(T object, const T constant, typename T::IDType id) {
            requires BundleIdentifier<typename T::IDType>;
            { object.setID(id) } -> std::same_as<void>;
            { constant.getID() } -> std::same_as<typename T::IDType>;
            { constant.isInitialized() } -> std::convertible_to<bool>;
            { constant.isTerminated() } -> std::convertible_to<bool>;
        };

    /// @brief Pool allocator and manager for feature sets/tracks.
    ///
    /// Manages feature sets or tracks with O(1) lookup by their declared ID type.
    /// Uses a bitset to track slot occupancy and a monotonically increasing
    /// automatic ID counter. Provides bulk operations for querying
    /// terminated tracks and clearing inactive entries.
    /// Stored objects must keep an assigned ID stable during in-place updates.
    /// CFeatureSet and CFeatureTrack enforce that rule when assigned through a
    /// bundle reference.
    ///
    /// Typical usage: the frontend allocates a new track per detected feature,
    /// appends observations each frame, and eventually frees terminated tracks
    /// after the backend has consumed them.
    ///
    /// @tparam SetT       Feature set/track type (must satisfy BundleStorable).
    /// @tparam MAX_SLOTS  Maximum number of simultaneously active sets.
    template <BundleStorable SetT, uint32_t MAX_SLOTS = 512> class CFeatureSetBundle
    {
      public:
        using IDType = typename SetT::IDType; ///< Identifier domain of stored objects.

        /// @brief Construct an empty fixed-capacity bundle.
        CFeatureSetBundle()
        {
            slots_.reserve(MAX_SLOTS);
        }

        /// @brief Store a set under its ID, assigning one if it is uninitialized.
        /// @param set Feature set/track to move into the pool.
        /// @return ID of the stored object in its declared domain.
        /// @throws std::runtime_error If the pool is full.
        /// @throws std::invalid_argument If the supplied ID is already active.
        /// @throws std::overflow_error If no automatic ID remains.
        [[nodiscard]] auto allocate(SetT &&set) -> IDType
        {
            const bool has_id = set.isInitialized();
            if (!has_id && automatic_ids_exhausted_)
            {
                throw std::overflow_error("CFeatureSetBundle: automatic ID range exhausted");
            }
            const IDType id = has_id ? set.getID() : IDType{next_id_};
            if (id_to_slot_.contains(id))
            {
                throw std::invalid_argument("CFeatureSetBundle::allocate: duplicate active ID");
            }
            const uint32_t slot = findFreeSlot();

            // Reserve the mapping before moving the set; erase it if storage fails.
            id_to_slot_.emplace(id, slot);
            try
            {
                if (slot >= slots_.size())
                {
                    slots_.emplace_back(std::in_place, std::move(set));
                }
                else
                {
                    slots_[slot].emplace(std::move(set));
                }
                if (!has_id)
                {
                    slots_[slot]->setID(id);
                }
            }
            catch (...)
            {
                if (slot < slots_.size())
                {
                    slots_[slot].reset();
                }
                id_to_slot_.erase(id);
                throw;
            }
            occupied_.set(slot);
            ++active_count_; // Increase active count of allocated sets
            const SetID numeric_id = idValue(id);
            if (!automatic_ids_exhausted_ && numeric_id >= next_id_)
            {
                if (numeric_id == std::numeric_limits<SetID>::max())
                {
                    automatic_ids_exhausted_ = true;
                }
                else
                {
                    next_id_ = numeric_id + 1U;
                }
            }
            return id;
        }

        /**
         * @brief Free the slot associated with the given typed ID, making it
         * available for future allocations. After this call, get() rejects the
         * ID and contains() returns false.
         * References previously returned by get() are invalidated.
         *
         * @param id ID of the feature set or track to release.
         * @throws std::out_of_range if id is unknown.
         */
        void free(IDType id)
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::free: unknown ID");
            }
            slots_[it->second].reset();
            occupied_.reset(it->second);
            id_to_slot_.erase(it);
            --active_count_; // Decrease active count of allocated sets
        }

        /**
         * @brief Access the feature set associated with the given typed ID.
         * Provides mutable access for in-place updates.
         *
         * @param id ID to look up.
         * @return SetT& Mutable reference, valid until this ID is freed.
         * @throws std::out_of_range if id is unknown (never allocated or freed).
         */
        auto get(IDType id) -> SetT &
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::get: unknown ID");
            }
            return *slots_[it->second];
        }

        /**
         * @brief Access the feature set associated with the given typed ID.
         * Provides read-only access.
         *
         * @param id ID to look up.
         * @return const SetT& Const reference, valid until this ID is freed.
         * @throws std::out_of_range if id is unknown (never allocated or freed).
         */
        auto get(IDType id) const -> const SetT &
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::get: unknown ID");
            }
            return *slots_[it->second];
        }

        /**
         * @brief Check whether the bundle contains a feature set with the given typed ID.
         *
         * @param id ID to query.
         * @return true if id is currently allocated and active, false otherwise.
         */
        auto contains(IDType id) const -> bool
        {
            return id_to_slot_.count(id) > 0;
        }

        /**
         * @brief Get the current number of active (allocated, not freed) feature sets.
         * @return Number of occupied slots.
         */
        auto activeCount() const -> uint32_t
        {
            return active_count_;
        }

        /**
         * @brief Collect the IDs of all active sets whose isTerminated() returns true.
         * @return Vector of typed IDs that are marked as terminated but not yet freed.
         */
        auto getTerminatedIDs() const -> std::vector<IDType>
        {
            std::vector<IDType> result;
            for (const auto &[id, slot] : id_to_slot_)
            {
                if (slots_[slot]->isTerminated())
                {
                    result.push_back(id);
                }
            }
            return result;
        }

        /**
         * @brief Apply a callable to each active feature set in the bundle.
         *
         * @param fn Callable with signature `void(IDType, SetT&)`. Invoked once
         *           per occupied slot with the entry's ID and mutable reference.
         */
        void forEachActive(auto &&fn)
        {
            for (auto &[id, slot] : id_to_slot_)
            {
                fn(id, *slots_[slot]);
            }
        }

        /**
         * @brief Free all feature sets whose ID is absent from the keep list.
         *
         * Useful for bulk cleanup: pass the currently active feature IDs and
         * all terminated / stale entries are freed in one call.
         *
         * @param keep_ids Span of typed IDs to retain. IDs not currently allocated
         *                 are silently ignored.
         */
        void clearInactive(std::span<const IDType> keep_ids)
        {
            // Build set of IDs to keep
            std::unordered_map<IDType, bool> keep_set;
            for (auto id : keep_ids)
            {
                keep_set[id] = true;
            }

            // Collect IDs to remove
            std::vector<IDType> to_remove;
            for (const auto &[id, slot] : id_to_slot_)
            {
                if (keep_set.count(id) == 0)
                {
                    to_remove.push_back(id);
                }
            }

            for (auto id : to_remove)
            {
                free(id);
            }
        }

      protected:
        // PROTECTED METHODS
        [[nodiscard]] static constexpr auto idValue(IDType id) noexcept -> SetID
        {
            if constexpr (std::same_as<IDType, SetID>)
            {
                return id;
            }
            else
            {
                return id.value();
            }
        }

        auto findFreeSlot() const -> uint32_t
        {
            // Find first unset bit
            for (uint32_t i = 0; i < MAX_SLOTS; ++i)
            {
                if (!occupied_.test(i))
                {
                    return i;
                }
            }
            throw std::runtime_error("CFeatureSetBundle: pool is full");
        }

        // PROTECTED DATA MEMBERS
        std::vector<std::optional<SetT>>
            slots_; // Empty slots can be re-emplaced without changing an assigned ID
        std::unordered_map<IDType, uint32_t> id_to_slot_; // Maps typed ID to slot index
        std::bitset<MAX_SLOTS> occupied_; // Tracks which slots in the pool are currently occupied
        uint32_t active_count_{0};
        SetID next_id_{1};
        bool automatic_ids_exhausted_{false};
    };

} // namespace slam_primitives
