/// @file test_CCovisibilityGraph.cpp
/// @brief Check typed visibility, runtime retention and reverse-index consistency.
#include <catch2/catch_test_macros.hpp>
#include "slam-primitives/covisibility/CCovisibilityGraph.h"
#include "slam-primitives/types/identifiers.h"
#include <algorithm>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <vector>

using namespace slam_primitives;
using Graph = CCovisibilityGraph<4>;
using TrackGraph = CCovisibilityGraph<4, CFeatureTrackID>;
/// @brief Test fixture exposing logical reverse slots without changing production visibility.
struct SInspectableGraph : Graph
{
    using Graph::Graph;

    /// @brief Copy a feature's reverse slots so tests can inspect eviction and trimming.
    [[nodiscard]] auto indexedSlots(SetID id) const -> std::vector<std::uint32_t>
    {
        auto it = feature_to_frame_slots_.find(id);
        return it == feature_to_frame_slots_.end() ? std::vector<std::uint32_t>{} : it->second;
    }
};
static_assert(std::is_same_v<decltype(TrackGraph::SFrameEntry{}.frame_id), CFrameID>);

TEST_CASE("Covisibility runtime windows retain newest frames and current reverse slots", "[covisibility][window]")
{
    REQUIRE(Graph{}.getWindowSize() == 4U);
    for (const auto limit : {1U, 2U, 4U})
    {
        SInspectableGraph graph{limit};
        for (std::uint32_t frame = 0U; frame < 20U; ++frame)
        {
            graph.pushFrame(CFrameID{frame});
            graph.addVisibilityLinks(CFrameID{frame}, std::vector<SetID>{42U, 100U + frame});
            const auto count = std::min(frame + 1U, limit);
            REQUIRE(graph.frameCount() == count);
            std::vector<std::uint32_t> expected_slots;
            for (std::uint32_t slot = 0U; slot < count; ++slot)
            {
                expected_slots.push_back(slot);
            }
            REQUIRE(graph.indexedSlots(42U) == expected_slots);
            REQUIRE(graph.indexedSlots(100U + frame) == std::vector<std::uint32_t>{count - 1U});
            if (frame >= limit)
            {
                REQUIRE(graph.getVisibleFeatures(CFrameID{frame - limit}).empty());
                REQUIRE(graph.indexedSlots(100U + frame - limit).empty());
            }
            if (count > 1U)
            {
                REQUIRE(graph.getCovisibleFeatures(CFrameID{frame - 1U}, CFrameID{frame}) == std::vector<SetID>{42U});
            }
        }
    }
}

TEST_CASE("Covisibility shrinking and growing preserve only retained history", "[covisibility][window]")
{
    SInspectableGraph graph;
    for (std::uint32_t frame = 1U; frame <= 4U; ++frame)
    {
        graph.pushFrame(CFrameID{frame});
        graph.addVisibilityLinks(CFrameID{frame}, std::vector<SetID>{7U, 100U + frame});
    }
    graph.setWindowSize(2U);
    REQUIRE(graph.getWindowSize() == 2U);
    REQUIRE(graph.frameCount() == 2U);
    REQUIRE(graph.getVisibleFeatures(CFrameID{1U}).empty());
    REQUIRE(graph.getVisibleFeatures(CFrameID{2U}).empty());
    REQUIRE(graph.indexedSlots(101U).empty());
    REQUIRE(graph.indexedSlots(102U).empty());
    REQUIRE(graph.indexedSlots(7U) == std::vector<std::uint32_t>{0U, 1U});
    REQUIRE(graph.getCovisibleFeatures(CFrameID{3U}, CFrameID{4U}) == std::vector<SetID>{7U});

    // Even the oldest frame is still live at validation time; duplicate rejection must not evict it.
    REQUIRE_THROWS_AS(graph.pushFrame(CFrameID{3U}), std::invalid_argument);
    REQUIRE(graph.frameCount() == 2U);
    REQUIRE_FALSE(graph.getVisibleFeatures(CFrameID{3U}).empty());
    REQUIRE(graph.indexedSlots(7U) == std::vector<std::uint32_t>{0U, 1U});

    graph.setWindowSize(4U);
    REQUIRE(graph.frameCount() == 2U);
    REQUIRE(graph.getVisibleFeatures(CFrameID{1U}).empty());
    graph.pushFrame(CFrameID{5U});
    graph.addVisibilityLinks(CFrameID{5U}, std::vector<SetID>{7U});
    REQUIRE(graph.frameCount() == 3U);
    REQUIRE(graph.indexedSlots(7U) == std::vector<std::uint32_t>{0U, 1U, 2U});
    graph.setWindowSize(1U);
    REQUIRE(graph.frameCount() == 1U);
    REQUIRE(graph.indexedSlots(7U) == std::vector<std::uint32_t>{0U});
    REQUIRE(graph.indexedSlots(104U).empty());
    graph.setWindowSize(1U);
    REQUIRE(graph.frameCount() == 1U);

    auto copy = graph;
    REQUIRE(copy.getWindowSize() == 1U);
    copy.pushFrame(CFrameID{6U});
    REQUIRE(copy.getVisibleFeatures(CFrameID{5U}).empty());
    REQUIRE_FALSE(graph.getVisibleFeatures(CFrameID{5U}).empty());
}

TEST_CASE("Covisibility invalid window sizes do not mutate the graph", "[covisibility][window][validation]")
{
    SInspectableGraph graph{2U};
    graph.pushFrame(CFrameID{0U});
    graph.addVisibilityLinks(CFrameID{0U}, std::vector<SetID>{9U});
    for (const auto invalid : {0U, 5U, std::numeric_limits<std::uint32_t>::max()})
    {
        REQUIRE_THROWS_AS(Graph{invalid}, std::invalid_argument);
        REQUIRE_THROWS_AS(graph.setWindowSize(invalid), std::invalid_argument);
        REQUIRE(graph.getWindowSize() == 2U);
        REQUIRE(graph.frameCount() == 1U);
        REQUIRE(graph.getVisibleFeatures(CFrameID{0U}).front() == 9U);
        REQUIRE(graph.indexedSlots(9U) == std::vector<std::uint32_t>{0U});
    }
}

TEST_CASE("Covisibility capacity one preserves typed IDs through runtime eviction", "[covisibility][window]")
{
    CCovisibilityGraph<1, CFeatureTrackID> graph{1U};
    const auto last_frame = CFrameID{std::numeric_limits<std::uint32_t>::max()};
    const std::vector<CFeatureTrackID> ids{CFeatureTrackID{(std::uint64_t{1} << 63U) + 17U}};
    graph.pushFrame(CFrameID{0U});
    graph.addVisibilityLinks(CFrameID{0U}, ids);
    graph.pushFrame(last_frame);
    REQUIRE(graph.getVisibleFeatures(CFrameID{0U}).empty());
    graph.addVisibilityLinks(last_frame, ids);
    REQUIRE(graph.frameCount() == 1U);
    REQUIRE(graph.getLastFrameVisibility().front() == ids.front());
    REQUIRE_THROWS_AS(graph.pushFrame(last_frame), std::invalid_argument);
    REQUIRE(graph.getLastFrameVisibility().front() == ids.front());
}

TEST_CASE("Covisibility reverse slots stay unique and current after eviction", "[covisibility]")
{
    SInspectableGraph graph;
    for (std::uint32_t frame = 1U; frame <= 4U; ++frame)
    {
        graph.pushFrame(CFrameID{frame});
    }
    const std::vector<SetID> duplicate{10U, 10U};
    graph.addVisibilityLinks(CFrameID{2U}, duplicate);
    graph.addVisibilityLinks(CFrameID{2U}, duplicate);
    graph.addVisibilityLinks(CFrameID{4U}, duplicate);
    REQUIRE(graph.indexedSlots(10U) == std::vector<std::uint32_t>{1U, 3U});

    graph.pushFrame(CFrameID{5U});
    REQUIRE(graph.indexedSlots(10U) == std::vector<std::uint32_t>{0U, 2U});
    graph.pushFrame(CFrameID{6U});
    REQUIRE(graph.indexedSlots(10U) == std::vector<std::uint32_t>{1U});
    graph.clearInactiveFeatures(std::vector<SetID>{10U});
    REQUIRE(graph.indexedSlots(10U) == std::vector<std::uint32_t>{1U});
}

TEST_CASE("Covisibility rejects a duplicate live frame without mutation", "[covisibility]")
{
    Graph graph;
    graph.pushFrame(CFrameID{1U});
    graph.addVisibilityLinks(CFrameID{1U}, std::vector<SetID>{9U});
    REQUIRE_THROWS_AS(graph.pushFrame(CFrameID{1U}), std::invalid_argument);
    REQUIRE(graph.frameCount() == 1U);
    REQUIRE(graph.getVisibleFeatures(CFrameID{1U})[0] == 9U);
}

TEST_CASE("Track covisibility accepts frame zero and the unsigned maximum", "[covisibility]")
{
    TrackGraph graph;
    const CFrameID last_frame{std::numeric_limits<std::uint32_t>::max()};
    graph.pushFrame(CFrameID{});
    graph.pushFrame(last_frame);
    const std::vector<CFeatureTrackID> ids{CFeatureTrackID{9U}};
    graph.addVisibilityLinks(CFrameID{}, ids);
    graph.addVisibilityLinks(last_frame, ids);
    REQUIRE(graph.getCovisibleFeatures(CFrameID{}, last_frame) == ids);
}

TEST_CASE("Track covisibility retains the track ID domain", "[covisibility]")
{
    TrackGraph graph;
    graph.pushFrame(CFrameID{1U});
    graph.pushFrame(CFrameID{2U});
    const std::vector<CFeatureTrackID> first{CFeatureTrackID{8U}, CFeatureTrackID{3U}};
    const std::vector<CFeatureTrackID> second{CFeatureTrackID{8U}};

    graph.addVisibilityLinks(CFrameID{1U}, first);
    graph.addVisibilityLinks(CFrameID{2U}, second);
    const auto visible = graph.getVisibleFeatures(CFrameID{1U});
    REQUIRE(visible.size() == 2U);
    REQUIRE(visible[0] == CFeatureTrackID{3U});
    REQUIRE(visible[1] == CFeatureTrackID{8U});
    REQUIRE(graph.getCovisibleFeatures(CFrameID{1U}, CFrameID{2U}) == second);
    graph.clearInactiveFeatures(second);
    const auto retained = graph.getVisibleFeatures(CFrameID{1U});
    REQUIRE(retained.size() == 1U);
    REQUIRE(retained.front() == CFeatureTrackID{8U});
}

TEST_CASE("CCovisibilityGraph push single frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{100U});
    REQUIRE(g.frameCount() == 1);
}

TEST_CASE("CCovisibilityGraph add visibility and query", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{100U});

    std::vector<SetID> features = {1, 2, 3};
    g.addVisibilityLinks(CFrameID{100U}, features);

    auto vis = g.getVisibleFeatures(CFrameID{100U});
    REQUIRE(vis.size() == 3);
    REQUIRE(vis[0] == 1);
    REQUIRE(vis[1] == 2);
    REQUIRE(vis[2] == 3);
}

TEST_CASE("CCovisibilityGraph getLastFrameVisibility", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});
    std::vector<SetID> f1 = {10, 20};
    g.addVisibilityLinks(CFrameID{1U}, f1);

    g.pushFrame(CFrameID{2U});
    std::vector<SetID> f2 = {30, 40, 50};
    g.addVisibilityLinks(CFrameID{2U}, f2);

    auto last = g.getLastFrameVisibility();
    REQUIRE(last.size() == 3);
    REQUIRE(last[0] == 30);
}

TEST_CASE("CCovisibilityGraph covisible features intersection", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});
    g.pushFrame(CFrameID{2U});

    std::vector<SetID> f1 = {10, 20, 30};
    std::vector<SetID> f2 = {20, 30, 40};
    g.addVisibilityLinks(CFrameID{1U}, f1);
    g.addVisibilityLinks(CFrameID{2U}, f2);

    auto covis = g.getCovisibleFeatures(CFrameID{1U}, CFrameID{2U});
    REQUIRE(covis.size() == 2);
    REQUIRE(covis[0] == 20);
    REQUIRE(covis[1] == 30);
}

TEST_CASE("CCovisibilityGraph no covisible features", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});
    g.pushFrame(CFrameID{2U});

    std::vector<SetID> f1 = {10, 20};
    std::vector<SetID> f2 = {30, 40};
    g.addVisibilityLinks(CFrameID{1U}, f1);
    g.addVisibilityLinks(CFrameID{2U}, f2);

    auto covis = g.getCovisibleFeatures(CFrameID{1U}, CFrameID{2U});
    REQUIRE(covis.empty());
}

TEST_CASE("CCovisibilityGraph ring buffer wrap-around", "[covisibility]")
{
    Graph g; // MAX_FRAMES = 4
    g.pushFrame(CFrameID{1U});
    g.pushFrame(CFrameID{2U});
    g.pushFrame(CFrameID{3U});
    g.pushFrame(CFrameID{4U});

    std::vector<SetID> f = {100};
    g.addVisibilityLinks(CFrameID{1U}, f);

    REQUIRE(g.frameCount() == 4);

    // Push 5th frame, evicts frame 1
    g.pushFrame(CFrameID{5U});
    REQUIRE(g.frameCount() == 4);

    // Frame 1 should no longer be findable
    auto vis = g.getVisibleFeatures(CFrameID{1U});
    REQUIRE(vis.empty());

    // Frame 5 should exist
    std::vector<SetID> f5 = {200};
    g.addVisibilityLinks(CFrameID{5U}, f5);
    auto vis5 = g.getVisibleFeatures(CFrameID{5U});
    REQUIRE(vis5.size() == 1);
    REQUIRE(vis5[0] == 200);
}

TEST_CASE("CCovisibilityGraph clearInactiveFeatures removes stale features", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});
    std::vector<SetID> features = {10, 20, 30};
    g.addVisibilityLinks(CFrameID{1U}, features);

    // Only feature 20 is still active
    std::vector<SetID> active = {20};
    g.clearInactiveFeatures(active);

    auto vis = g.getVisibleFeatures(CFrameID{1U});
    REQUIRE(vis.size() == 1);
    REQUIRE(vis[0] == 20);
}

TEST_CASE("CCovisibilityGraph clearInactiveFeatures with empty active set", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});
    std::vector<SetID> features = {10, 20};
    g.addVisibilityLinks(CFrameID{1U}, features);

    std::vector<SetID> empty;
    g.clearInactiveFeatures(empty);

    auto vis = g.getVisibleFeatures(CFrameID{1U});
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph push frame with no features", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});

    auto vis = g.getVisibleFeatures(CFrameID{1U});
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph query non-existent frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});

    auto vis = g.getVisibleFeatures(CFrameID{999U});
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph add visibility to missing frame is no-op", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});

    std::vector<SetID> features = {10, 20};
    g.addVisibilityLinks(CFrameID{999U}, features);

    REQUIRE(g.getVisibleFeatures(CFrameID{1U}).empty());
    REQUIRE(g.frameCount() == 1);
}

TEST_CASE("CCovisibilityGraph getCovisibleFeatures non-existent frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});

    auto covis = g.getCovisibleFeatures(CFrameID{1U}, CFrameID{999U});
    REQUIRE(covis.empty());
}

TEST_CASE("CCovisibilityGraph empty graph", "[covisibility]")
{
    Graph g;
    REQUIRE(g.frameCount() == 0);
    auto vis = g.getLastFrameVisibility();
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph duplicate feature IDs in addVisibilityLinks", "[covisibility]")
{
    Graph g;
    g.pushFrame(CFrameID{1U});

    // Add same feature twice - should deduplicate
    std::vector<SetID> features = {10, 10, 20};
    g.addVisibilityLinks(CFrameID{1U}, features);

    auto vis = g.getVisibleFeatures(CFrameID{1U});
    REQUIRE(vis.size() == 2); // deduplicated
    REQUIRE(vis[0] == 10);
    REQUIRE(vis[1] == 20);
}
