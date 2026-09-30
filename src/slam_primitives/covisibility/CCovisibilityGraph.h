/// @file CCovisibilityGraph.h
/// @brief Defines a frame window of visible typed feature identifiers.

#pragma once
#include "slam-primitives/containers/CCircularBuffer.h"
#include "slam-primitives/types/identifiers.h"
#include <algorithm>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace slam_primitives
{

    /// @brief Sliding-window covisibility graph for feature visibility tracking.
    ///
    /// Maintains a circular buffer of at most getWindowSize() frames, each storing
    /// the sorted set of feature IDs visible in that frame. Provides queries for
    /// per-frame visibility, pairwise covisibility (set intersection), and a
    /// reverse index from feature ID to frame slots.
    ///
    /// The runtime window defaults to the fixed MAX_FRAMES storage capacity.
    /// When the window is full, pushFrame() evicts the oldest frame and its
    /// index entries. clearInactiveFeatures() removes stale feature IDs that are
    /// no longer active in the bundle.
    ///
    /// @tparam MAX_FRAMES Fixed storage capacity and maximum runtime window size.
    /// @tparam FeatureIDT  Identifier domain of visible features.
    template <uint32_t MAX_FRAMES = 64, BundleIdentifier FeatureIDT = SetID>
    class CCovisibilityGraph
    {
      public:
        using IDType = FeatureIDT; ///< Identifier domain indexed by the graph.

        /// @brief Per-frame record of visible feature IDs (kept sorted for fast intersection).
        struct SFrameEntry
        {
            /// @brief Frame identifier associated with this entry.
            CFrameID frame_id{};

            /// @brief Sorted list of feature IDs visible in @ref frame_id.
            std::vector<IDType> visible_features;
        };

        /// @brief Construct an empty graph retaining up to MAX_FRAMES frames.
        CCovisibilityGraph() = default;

        /// @brief Construct an empty graph with a runtime retention limit.
        /// @param window_size Number of frames to retain, from 1 through MAX_FRAMES.
        /// @throws std::invalid_argument For a limit outside the fixed capacity.
        explicit CCovisibilityGraph(uint32_t window_size)
        {
            setWindowSize(window_size);
        }

        /// @brief Change retention, immediately removing oldest excess frames.
        /// Increasing the limit preserves retained frames without restoring evicted
        /// history. Trimming invalidates spans into removed frames and rebuilds logical
        /// reverse-index slots once; references to this graph remain valid.
        /// @param window_size Number of frames to retain, from 1 through MAX_FRAMES.
        /// @throws std::invalid_argument Without mutation for an invalid limit.
        void setWindowSize(uint32_t window_size)
        {
            if (window_size == 0U || window_size > MAX_FRAMES)
            {
                throw std::invalid_argument("CCovisibilityGraph: window size must be within fixed capacity");
            }
            const bool trimming = frames_.size() > window_size;
            while (frames_.size() > window_size)
            {
                frames_.pop_front();
            }
            window_size_ = window_size;
            if (trimming)
            {
                rebuildReverseIndex();
            }
        }

        /// @brief Return the configured frame-retention limit, independent of frameCount().
        [[nodiscard]] auto getWindowSize() const noexcept -> uint32_t
        {
            return window_size_;
        }

        /// @brief Register a new frame in the sliding window.
        ///
        /// If the internal window is full, the oldest frame entry is evicted and
        /// its reverse-index mappings are removed. Spans into that frame become invalid.
        /// @param id Frame identifier to append.
        /// @throws std::invalid_argument Without mutation if @p id is already live,
        /// including when that frame would otherwise be evicted by this insertion.
        void pushFrame(CFrameID id)
        {
            if (findFrameSlot(id))
            {
                throw std::invalid_argument("CCovisibilityGraph: duplicate live frame ID");
            }
            const bool evicting = frames_.size() == window_size_;
            if (evicting)
            {
                frames_.pop_front();
            }
            SFrameEntry entry;
            entry.frame_id = id;
            frames_.push_back(std::move(entry));
            if (evicting)
            {
                // Removing the oldest frame shifts every retained logical slot.
                rebuildReverseIndex();
            }
        }

        /// @brief Add frame-to-feature visibility links for an existing frame.
        ///
        /// Input feature IDs are inserted in sorted order and duplicates are ignored
        /// in the per-frame list. If @p frame is not present in the current window,
        /// the method performs no operation.
        /// @param frame Frame identifier that receives visibility links.
        /// @param features Feature IDs to mark as visible in @p frame.
        void addVisibilityLinks(CFrameID frame, std::span<const IDType> features)
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
                    auto &slots = feature_to_frame_slots_[fid];
                    slots.insert(std::lower_bound(slots.begin(), slots.end(), *slot), *slot);
                }
            }
        }

        /// @brief Get features visible in a specific frame.
        /// @param frame Frame identifier to query.
        /// @return Span over the frame's visible feature IDs, or an empty span if
        ///         the frame is not in the current window.
        auto getVisibleFeatures(CFrameID frame) const -> std::span<const IDType>
        {
            auto slot = findFrameSlot(frame);
            if (!slot.has_value())
            {
                return {};
            }
            return std::span<const IDType>(frames_[*slot].visible_features);
        }

        /// @brief Get visibility list for the most recently pushed frame.
        /// @return Span over the newest frame's visible features, or an empty span
        ///         if the graph contains no frames.
        auto getLastFrameVisibility() const -> std::span<const IDType>
        {
            if (frames_.empty())
            {
                return {};
            }
            return std::span<const IDType>(frames_.back().visible_features);
        }

        /// @brief Compute pairwise covisibility between two frames.
        ///
        /// The result is the sorted intersection of the two per-frame visibility
        /// lists. If either frame is missing from the window, an empty vector is
        /// returned.
        /// @param a First frame identifier.
        /// @param b Second frame identifier.
        /// @return Sorted vector of feature IDs visible in both frames.
        auto getCovisibleFeatures(CFrameID a, CFrameID b) const -> std::vector<IDType>
        {
            auto slot_a = findFrameSlot(a);
            auto slot_b = findFrameSlot(b);
            if (!slot_a.has_value() || !slot_b.has_value())
            {
                return {};
            }

            const auto &va = frames_[*slot_a].visible_features;
            const auto &vb = frames_[*slot_b].visible_features;

            std::vector<IDType> result;
            std::set_intersection(va.begin(), va.end(), vb.begin(), vb.end(),
                                  std::back_inserter(result));
            return result;
        }

        /// @brief Remove visibility entries for features no longer active.
        ///
        /// Prunes stale feature IDs from all frame visibility lists, then rebuilds
        /// the reverse index feature_to_frame_slots_.
        /// @param active_feature_ids Feature IDs that should be retained.
        void clearInactiveFeatures(std::span<const IDType> active_feature_ids)
        {
            // Build active set for fast lookup
            std::unordered_map<IDType, bool> active_set;
            for (auto id : active_feature_ids)
            {
                active_set[id] = true;
            }

            // Remove stale features from all frame entries and rebuild index.
            for (uint32_t i = 0; i < frames_.size(); ++i)
            {
                auto &features = frames_[i].visible_features;
                std::erase_if(features, [&](IDType fid) { return active_set.count(fid) == 0; });
            }
            rebuildReverseIndex();
        }

        /// @brief Get the number of frames currently retained in the window.
        /// @return Number of frame entries in the graph.
        auto frameCount() const -> uint32_t
        {
            return frames_.size();
        }

      protected:
        // PROTECTED MEMBER FUNCTIONS

        /// @brief Locate the slot index of a frame in the circular window.
        /// @param frame Frame identifier to locate.
        /// @return Slot index if found, std::nullopt otherwise.
        auto findFrameSlot(CFrameID frame) const -> std::optional<uint32_t>
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

        /// @brief Rebuild reverse links using current logical ring positions.
        void rebuildReverseIndex()
        {
            feature_to_frame_slots_.clear();
            for (uint32_t slot = 0; slot < frames_.size(); ++slot)
            {
                for (auto fid : frames_[slot].visible_features)
                {
                    feature_to_frame_slots_[fid].push_back(slot);
                }
            }
        }

      protected:
        // PROTECTED DATA MEMBERS
        CCircularBuffer<SFrameEntry, MAX_FRAMES> frames_;
        std::unordered_map<IDType, std::vector<uint32_t>> feature_to_frame_slots_;

      private:
        uint32_t window_size_{MAX_FRAMES};
    };

} // namespace slam_primitives
