#pragma once
#include "slam_primitives/containers/CCircularBuffer.h"
#include "slam_primitives/types/type_aliases.h"
#include <algorithm>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace slam_primitives
{

    /// @brief Sliding-window covisibility graph for feature visibility tracking.
    ///
    /// Maintains a circular buffer of the last MAX_FRAMES frames, each storing
    /// the sorted set of feature IDs visible in that frame. Provides queries for
    /// per-frame visibility, pairwise covisibility (set intersection), and a
    /// reverse index from feature ID to frame slots.
    ///
    /// When the window is full, pushFrame() evicts the oldest frame and its
    /// index entries. cleanup() removes stale feature IDs that are no longer
    /// active in the bundle.
    ///
    /// @tparam MAX_FRAMES  Sliding window size (number of frames retained).
    template <uint32_t MAX_FRAMES = 64>
    class CCovisibilityGraph
    {
      public:
        /// @brief Per-frame record of visible feature IDs (kept sorted for fast intersection).
        struct SFrameEntry
        {
            /// @brief Frame identifier associated with this entry.
            FrameID frame_id{-1};

            /// @brief Sorted list of feature IDs visible in @ref frame_id.
            std::vector<SetID> visible_features;
        };

        /// @brief Construct an empty covisibility graph.
        CCovisibilityGraph() = default;

        /// @brief Register a new frame in the sliding window.
        ///
        /// If the internal window is full, the oldest frame entry is evicted and
        /// its reverse-index mappings are removed.
        /// @param id Frame identifier to append.
        void pushFrame(FrameID id)
        {
            if (frames_.full())
            {
                // Remove feature-to-slot mappings for the oldest frame being evicted
                removeFrameFromIndex(0);
            }

            SFrameEntry entry;
            entry.frame_id = id;
            frames_.push_back(std::move(entry));
        }

        /// @brief Add frame-to-feature visibility links for an existing frame.
        ///
        /// Input feature IDs are inserted in sorted order and duplicates are ignored
        /// in the per-frame list. If @p frame is not present in the current window,
        /// the method performs no operation.
        /// @param frame Frame identifier that receives visibility links.
        /// @param features Feature IDs to mark as visible in @p frame.
        void addVisibilityLinks(FrameID frame, std::span<const SetID> features)
        {
            auto slot = findFrameSlot(frame);
            if (!slot.has_value())
            {
                return;
            }

            auto &entry = frames_[*slot];
            for (auto fid : features)
            {
                // Insert sorted
                auto pos = std::lower_bound(entry.visible_features.begin(),
                                            entry.visible_features.end(), fid);
                if (pos == entry.visible_features.end() || *pos != fid)
                {
                    entry.visible_features.insert(pos, fid);
                }

                // Update feature-to-frame index
                feature_to_frame_slots_[fid].push_back(*slot);
            }
        }

        /// @brief Get features visible in a specific frame.
        /// @param frame Frame identifier to query.
        /// @return Span over the frame's visible feature IDs, or an empty span if
        ///         the frame is not in the current window.
        auto getVisibleFeatures(FrameID frame) const -> std::span<const SetID>
        {
            auto slot = findFrameSlot(frame);
            if (!slot.has_value())
            {
                return {};
            }
            return std::span<const SetID>(frames_[*slot].visible_features);
        }

        /// @brief Get visibility list for the most recently pushed frame.
        /// @return Span over the newest frame's visible features, or an empty span
        ///         if the graph contains no frames.
        auto getLastFrameVisibility() const -> std::span<const SetID>
        {
            if (frames_.empty())
            {
                return {};
            }
            return std::span<const SetID>(frames_.back().visible_features);
        }

        /// @brief Compute pairwise covisibility between two frames.
        ///
        /// The result is the sorted intersection of the two per-frame visibility
        /// lists. If either frame is missing from the window, an empty vector is
        /// returned.
        /// @param a First frame identifier.
        /// @param b Second frame identifier.
        /// @return Sorted vector of feature IDs visible in both frames.
        auto getCovisibleFeatures(FrameID a, FrameID b) const -> std::vector<SetID>
        {
            auto slot_a = findFrameSlot(a);
            auto slot_b = findFrameSlot(b);
            if (!slot_a.has_value() || !slot_b.has_value())
            {
                return {};
            }

            const auto &va = frames_[*slot_a].visible_features;
            const auto &vb = frames_[*slot_b].visible_features;

            std::vector<SetID> result;
            std::set_intersection(va.begin(), va.end(),
                                  vb.begin(), vb.end(),
                                  std::back_inserter(result));
            return result;
        }

        /// @brief Remove visibility entries for features no longer active.
        ///
        /// Prunes stale feature IDs from all frame visibility lists, then rebuilds
        /// the reverse index feature_to_frame_slots_.
        /// @param active_feature_ids Feature IDs that should be retained.
        void cleanup(std::span<const SetID> active_feature_ids)
        {
            // Build active set for fast lookup
            std::unordered_map<SetID, bool> active_set;
            for (auto id : active_feature_ids)
            {
                active_set[id] = true;
            }

            // Remove stale features from all frame entries and rebuild index
            feature_to_frame_slots_.clear();

            for (uint32_t i = 0; i < frames_.size(); ++i)
            {
                auto &features = frames_[i].visible_features;
                std::erase_if(features, [&](SetID fid)
                              { return active_set.count(fid) == 0; });

                for (auto fid : features)
                {
                    feature_to_frame_slots_[fid].push_back(i);
                }
            }
        }

        /// @brief Get the number of frames currently retained in the window.
        /// @return Number of frame entries in the graph.
        auto frameCount() const -> uint32_t { return frames_.size(); }

      protected:
        // PROTECTED MEMBER FUNCTIONS

        /// @brief Locate the slot index of a frame in the circular window.
        /// @param frame Frame identifier to locate.
        /// @return Slot index if found, std::nullopt otherwise.
        auto findFrameSlot(FrameID frame) const -> std::optional<uint32_t>
        {
            for (uint32_t i = 0; i < frames_.size(); ++i)
            {
                if (frames_[i].frame_id == frame)
                {
                    return i;
                }
            }
            return std::nullopt;
        }

        /// @brief Remove reverse-index links associated with a frame slot.
        /// @param slot Slot index to remove from feature_to_frame_slots_.
        void removeFrameFromIndex(uint32_t slot)
        {
            const auto &features = frames_[slot].visible_features;
            for (auto fid : features)
            {
                auto it = feature_to_frame_slots_.find(fid);
                if (it != feature_to_frame_slots_.end())
                {
                    auto &slots = it->second;
                    std::erase(slots, slot);
                    if (slots.empty())
                    {
                        feature_to_frame_slots_.erase(it);
                    }
                }
            }
        }

      protected:
        // PROTECTED DATA MEMBERS
        CCircularBuffer<SFrameEntry, MAX_FRAMES> frames_;
        std::unordered_map<SetID, std::vector<uint32_t>> feature_to_frame_slots_;
    };

} // namespace slam_primitives
