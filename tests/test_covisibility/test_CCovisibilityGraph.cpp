#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/covisibility/CCovisibilityGraph.h"
#include "slam_primitives/types/type_aliases.h"

using namespace slam_primitives;
using Graph = CCovisibilityGraph<4>;

TEST_CASE("CCovisibilityGraph push single frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(100);
    REQUIRE(g.frameCount() == 1);
}

TEST_CASE("CCovisibilityGraph add visibility and query", "[covisibility]")
{
    Graph g;
    g.pushFrame(100);

    std::vector<SetID> features = {1, 2, 3};
    g.addVisibilityLinks(100, features);

    auto vis = g.getVisibleFeatures(100);
    REQUIRE(vis.size() == 3);
    REQUIRE(vis[0] == 1);
    REQUIRE(vis[1] == 2);
    REQUIRE(vis[2] == 3);
}

TEST_CASE("CCovisibilityGraph getLastFrameVisibility", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);
    std::vector<SetID> f1 = {10, 20};
    g.addVisibilityLinks(1, f1);

    g.pushFrame(2);
    std::vector<SetID> f2 = {30, 40, 50};
    g.addVisibilityLinks(2, f2);

    auto last = g.getLastFrameVisibility();
    REQUIRE(last.size() == 3);
    REQUIRE(last[0] == 30);
}

TEST_CASE("CCovisibilityGraph covisible features intersection", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);
    g.pushFrame(2);

    std::vector<SetID> f1 = {10, 20, 30};
    std::vector<SetID> f2 = {20, 30, 40};
    g.addVisibilityLinks(1, f1);
    g.addVisibilityLinks(2, f2);

    auto covis = g.getCovisibleFeatures(1, 2);
    REQUIRE(covis.size() == 2);
    REQUIRE(covis[0] == 20);
    REQUIRE(covis[1] == 30);
}

TEST_CASE("CCovisibilityGraph no covisible features", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);
    g.pushFrame(2);

    std::vector<SetID> f1 = {10, 20};
    std::vector<SetID> f2 = {30, 40};
    g.addVisibilityLinks(1, f1);
    g.addVisibilityLinks(2, f2);

    auto covis = g.getCovisibleFeatures(1, 2);
    REQUIRE(covis.empty());
}

TEST_CASE("CCovisibilityGraph ring buffer wrap-around", "[covisibility]")
{
    Graph g; // MAX_FRAMES = 4
    g.pushFrame(1);
    g.pushFrame(2);
    g.pushFrame(3);
    g.pushFrame(4);

    std::vector<SetID> f = {100};
    g.addVisibilityLinks(1, f);

    REQUIRE(g.frameCount() == 4);

    // Push 5th frame, evicts frame 1
    g.pushFrame(5);
    REQUIRE(g.frameCount() == 4);

    // Frame 1 should no longer be findable
    auto vis = g.getVisibleFeatures(1);
    REQUIRE(vis.empty());

    // Frame 5 should exist
    std::vector<SetID> f5 = {200};
    g.addVisibilityLinks(5, f5);
    auto vis5 = g.getVisibleFeatures(5);
    REQUIRE(vis5.size() == 1);
    REQUIRE(vis5[0] == 200);
}

TEST_CASE("CCovisibilityGraph cleanup removes stale features", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);
    std::vector<SetID> features = {10, 20, 30};
    g.addVisibilityLinks(1, features);

    // Only feature 20 is still active
    std::vector<SetID> active = {20};
    g.cleanup(active);

    auto vis = g.getVisibleFeatures(1);
    REQUIRE(vis.size() == 1);
    REQUIRE(vis[0] == 20);
}

TEST_CASE("CCovisibilityGraph cleanup with empty active set", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);
    std::vector<SetID> features = {10, 20};
    g.addVisibilityLinks(1, features);

    std::vector<SetID> empty;
    g.cleanup(empty);

    auto vis = g.getVisibleFeatures(1);
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph push frame with no features", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);

    auto vis = g.getVisibleFeatures(1);
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph query non-existent frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);

    auto vis = g.getVisibleFeatures(999);
    REQUIRE(vis.empty());
}

TEST_CASE("CCovisibilityGraph getCovisibleFeatures non-existent frame", "[covisibility]")
{
    Graph g;
    g.pushFrame(1);

    auto covis = g.getCovisibleFeatures(1, 999);
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
    g.pushFrame(1);

    // Add same feature twice - should deduplicate
    std::vector<SetID> features = {10, 10, 20};
    g.addVisibilityLinks(1, features);

    auto vis = g.getVisibleFeatures(1);
    REQUIRE(vis.size() == 2); // deduplicated
    REQUIRE(vis[0] == 10);
    REQUIRE(vis[1] == 20);
}
