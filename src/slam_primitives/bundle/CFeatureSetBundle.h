#pragma once
#include "slam_primitives/types/concepts.h"
#include "slam_primitives/types/type_aliases.h"
#include <bitset>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace slam_primitives
{

    /// @brief Pool allocator and manager for feature sets/tracks.
    ///
    /// Manages a collection of feature sets (or tracks) with O(1) lookup by SetID.
    /// Uses a bitset to track slot occupancy and a monotonically increasing ID
    /// counter (IDs are never reused). Provides bulk operations for querying
    /// terminated tracks and clearing inactive entries.
    ///
    /// Typical usage: the frontend allocates a new track per detected feature,
    /// appends observations each frame, and eventually frees terminated tracks
    /// after the backend has consumed them.
    ///
    /// @tparam SetT       Feature set/track type (must satisfy FeatureSetLike).
    /// @tparam MAX_SLOTS  Maximum number of simultaneously active sets.
    template <FeatureSetLike SetT, uint32_t MAX_SLOTS = 512>
    class CFeatureSetBundle
    {
      public:
        CFeatureSetBundle()
        {
            slots_.reserve(MAX_SLOTS);
        }

        /// @brief Allocate a slot for the given set and return its unique SetID.
        /// @param set Feature set/track to move into the pool.
        /// @return Unique, monotonically increasing SetID assigned to this entry.
        /// @throws std::runtime_error if the pool is full.
        auto allocate(SetT &&set) -> SetID
        {
            uint32_t slot = findFreeSlot();
            SetID id = next_id_++;

            if (slot >= slots_.size())
            {
                slots_.push_back(std::move(set));
            }
            else
            {
                slots_[slot] = std::move(set);
            }

            occupied_.set(slot);
            id_to_slot_[id] = slot;
            ++active_count_; // Increase active count of allocated sets
            return id;
        }

        /**
         * @brief Free the slot associated with the given SetID, making it
         * available for future allocations. After this call, the SetID is
         * invalid and should not be used for get() or contains() queries.
         *
         * @param id SetID of the feature set to release.
         * @throws std::out_of_range if id is unknown.
         */
        void free(SetID id)
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::free: unknown SetID");
            }
            occupied_.reset(it->second);
            id_to_slot_.erase(it);
            --active_count_; // Decrease active count of allocated sets
        }

        /**
         * @brief Access the feature set associated with the given SetID.
         * Provides mutable access for in-place updates.
         *
         * @param id SetID to look up.
         * @return SetT& Mutable reference to the stored feature set.
         * @throws std::out_of_range if id is unknown (never allocated or freed).
         */
        auto get(SetID id) -> SetT &
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::get: unknown SetID");
            }
            return slots_[it->second];
        }

        /**
         * @brief Access the feature set associated with the given SetID.
         * Provides read-only access.
         *
         * @param id SetID to look up.
         * @return const SetT& Const reference to the stored feature set.
         * @throws std::out_of_range if id is unknown (never allocated or freed).
         */
        auto get(SetID id) const -> const SetT &
        {
            auto it = id_to_slot_.find(id);
            if (it == id_to_slot_.end())
            {
                throw std::out_of_range("CFeatureSetBundle::get: unknown SetID");
            }
            return slots_[it->second];
        }

        /**
         * @brief Check whether the bundle contains a feature set with the given SetID.
         *
         * @param id SetID to query.
         * @return true if id is currently allocated and active, false otherwise.
         */
        auto contains(SetID id) const -> bool
        {
            return id_to_slot_.count(id) > 0;
        }

        /**
         * @brief Get the current number of active (allocated, not freed) feature sets.
         * @return Number of occupied slots.
         */
        auto activeCount() const -> uint32_t { return active_count_; }

        /**
         * @brief Collect the SetIDs of all active sets whose isTerminated() returns true.
         * @return Vector of SetIDs that are marked as terminated but not yet freed.
         */
        auto getTerminatedIDs() const -> std::vector<SetID>
        {
            std::vector<SetID> result;
            for (const auto &[id, slot] : id_to_slot_)
            {
                if (slots_[slot].isTerminated())
                {
                    result.push_back(id);
                }
            }
            return result;
        }

        /**
         * @brief Apply a callable to each active feature set in the bundle.
         *
         * @param fn Callable with signature `void(SetID, SetT&)`. Invoked once
         *           per occupied slot with the entry's ID and mutable reference.
         */
        void forEachActive(auto &&fn)
        {
            for (auto &[id, slot] : id_to_slot_)
            {
                fn(id, slots_[slot]);
            }
        }

        /**
         * @brief Free all feature sets whose SetID is NOT in the keep list.
         *
         * Useful for bulk cleanup: pass the currently active feature IDs and
         * all terminated / stale entries are freed in one call.
         *
         * @param keep_ids Span of SetIDs to retain. IDs not currently allocated
         *                 are silently ignored.
         */
        void clearInactive(std::span<const SetID> keep_ids)
        {
            // Build set of IDs to keep
            std::unordered_map<SetID, bool> keep_set;
            for (auto id : keep_ids)
            {
                keep_set[id] = true;
            }

            // Collect IDs to remove
            std::vector<SetID> to_remove;
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
        std::vector<SetT> slots_; // Storage for feature sets/tracks
        std::unordered_map<SetID, uint32_t> id_to_slot_; // Maps SetID to slot index in slots_ vector
        std::bitset<MAX_SLOTS> occupied_; // Tracks which slots in the pool are currently occupied
        uint32_t active_count_{0};
        SetID next_id_{1};
    };

} // namespace slam_primitives
