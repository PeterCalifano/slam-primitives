#include <catch2/catch_test_macros.hpp>
#include "slam_primitives/bundle/CFeatureSetBundle.h"
#include "slam_primitives/feature_sets/CFeatureTrack.h"
#include "slam_primitives/types/SFeatureLocation2D.h"

using namespace slam_primitives;
using Track = CFeatureTrack<SFeatureLocation2D, 4>;
using Bundle = CFeatureSetBundle<Track, 8>;

TEST_CASE("CFeatureSetBundle allocate and get", "[bundle]")
{
    Bundle b;
    Track t(0);
    t.addKeypointToTrack({1.0, 2.0}, 10);

    auto id = b.allocate(std::move(t));
    REQUIRE(b.contains(id));
    REQUIRE(b.activeCount() == 1);

    auto& ref = b.get(id);
    REQUIRE(ref.getTrackLength() == 1);
}

TEST_CASE("CFeatureSetBundle allocate multiple independent", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track(0));
    auto id2 = b.allocate(Track(0));

    REQUIRE(id1 != id2);
    REQUIRE(b.activeCount() == 2);
    REQUIRE(b.contains(id1));
    REQUIRE(b.contains(id2));
}

TEST_CASE("CFeatureSetBundle free decrements activeCount", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track(0));
    REQUIRE(b.activeCount() == 1);

    b.free(id);
    REQUIRE(b.activeCount() == 0);
    REQUIRE_FALSE(b.contains(id));
}

TEST_CASE("CFeatureSetBundle reuse freed slot", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track(0));
    b.free(id1);

    auto id2 = b.allocate(Track(0));
    REQUIRE(id2 != id1); // IDs are monotonic, never reused
    REQUIRE(b.activeCount() == 1);
}

TEST_CASE("CFeatureSetBundle get on freed ID throws", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track(0));
    b.free(id);

    REQUIRE_THROWS_AS(b.get(id), std::out_of_range);
}

TEST_CASE("CFeatureSetBundle contains true/false", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track(0));
    REQUIRE(b.contains(id));
    REQUIRE_FALSE(b.contains(id + 100));
}

TEST_CASE("CFeatureSetBundle getTerminatedIDs", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track(0));
    auto id2 = b.allocate(Track(0));
    auto id3 = b.allocate(Track(0));

    b.get(id1).terminate();
    b.get(id3).terminate();

    auto terminated = b.getTerminatedIDs();
    REQUIRE(terminated.size() == 2);

    // Both id1 and id3 should be in the list
    bool has_id1 = std::find(terminated.begin(), terminated.end(), id1) != terminated.end();
    bool has_id3 = std::find(terminated.begin(), terminated.end(), id3) != terminated.end();
    bool has_id2 = std::find(terminated.begin(), terminated.end(), id2) != terminated.end();
    REQUIRE(has_id1);
    REQUIRE(has_id3);
    REQUIRE_FALSE(has_id2);
}

TEST_CASE("CFeatureSetBundle forEachActive", "[bundle]")
{
    Bundle b;
    [[maybe_unused]] auto id1 = b.allocate(Track(0));
    [[maybe_unused]] auto id2 = b.allocate(Track(0));

    int count = 0;
    b.forEachActive([&](SetID id, Track& t) {
        (void)id;
        (void)t;
        ++count;
    });
    REQUIRE(count == 2);
}

TEST_CASE("CFeatureSetBundle clearInactive keeps specified IDs", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track(0));
    auto id2 = b.allocate(Track(0));
    auto id3 = b.allocate(Track(0));

    std::vector<SetID> keep = {id1, id3};
    b.clearInactive(keep);

    REQUIRE(b.activeCount() == 2);
    REQUIRE(b.contains(id1));
    REQUIRE_FALSE(b.contains(id2));
    REQUIRE(b.contains(id3));
}

TEST_CASE("CFeatureSetBundle clearInactive with empty keep removes all", "[bundle]")
{
    Bundle b;
    b.allocate(Track(0));
    b.allocate(Track(0));

    std::vector<SetID> keep = {};
    b.clearInactive(keep);

    REQUIRE(b.activeCount() == 0);
}

TEST_CASE("CFeatureSetBundle full pool throws", "[bundle]")
{
    CFeatureSetBundle<Track, 2> b;
    [[maybe_unused]] auto id1 = b.allocate(Track(0));
    [[maybe_unused]] auto id2 = b.allocate(Track(0));

    REQUIRE_THROWS(b.allocate(Track(0)));
}

TEST_CASE("CFeatureSetBundle empty pool operations", "[bundle]")
{
    Bundle b;
    REQUIRE(b.activeCount() == 0);
    REQUIRE(b.getTerminatedIDs().empty());

    int count = 0;
    b.forEachActive([&](SetID, Track&) { ++count; });
    REQUIRE(count == 0);
}

TEST_CASE("CFeatureSetBundle free unknown ID throws", "[bundle]")
{
    Bundle b;
    REQUIRE_THROWS_AS(b.free(999), std::out_of_range);
}

TEST_CASE("CFeatureSetBundle const get", "[bundle]")
{
    Bundle b;
    Track t(0);
    t.addKeypointToTrack({1.0, 2.0}, 5);
    auto id = b.allocate(std::move(t));

    const auto& cb = b;
    REQUIRE(cb.get(id).getTrackLength() == 1);
}
