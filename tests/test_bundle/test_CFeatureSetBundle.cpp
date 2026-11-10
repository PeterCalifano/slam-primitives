#include <catch2/catch_test_macros.hpp>
#include "slam-primitives/bundle/CFeatureSetBundle.h"
#include "slam-primitives/feature_sets/CFeatureSet.h"
#include "slam-primitives/feature_sets/CFeatureTrack.h"
#include "slam-primitives/types/feature_types.h"

#include <cstdint>
#include <limits>
#include <type_traits>

using namespace slam_primitives;
using Track = CFeatureTrack<SFeatureLocation2D, 4>;
using Bundle = CFeatureSetBundle<Track, 8>;
using GenericSet = CFeatureSet<SFeatureLocation2D, 4>;
using GenericBundle = CFeatureSetBundle<GenericSet, 8>;

static_assert(std::is_same_v<Bundle::IDType, CFeatureTrackID>);
static_assert(std::is_same_v<GenericBundle::IDType, SetID>);

TEST_CASE("CFeatureSetBundle allocate and get", "[bundle]")
{
    Bundle b;
    Track t;
    t.addKeypointToTrack({1.0, 2.0}, CFrameID{10U});

    auto id = b.allocate(std::move(t));
    REQUIRE(b.contains(id));
    REQUIRE(b.activeCount() == 1);

    auto &ref = b.get(id);
    REQUIRE(ref.getID() == id);
    REQUIRE(ref.getTrackLength() == 1);
}

TEST_CASE("CFeatureSetBundle allocate multiple independent", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track{});
    auto id2 = b.allocate(Track{});

    REQUIRE(id1 != id2);
    REQUIRE(b.activeCount() == 2);
    REQUIRE(b.contains(id1));
    REQUIRE(b.contains(id2));
}

TEST_CASE("CFeatureSetBundle free decrements activeCount", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track{});
    REQUIRE(b.activeCount() == 1);

    b.free(id);
    REQUIRE(b.activeCount() == 0);
    REQUIRE_FALSE(b.contains(id));
}

TEST_CASE("CFeatureSetBundle reuse freed slot", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track{});
    b.free(id1);
    REQUIRE_FALSE(b.contains(id1));

    auto id2 = b.allocate(Track{});
    REQUIRE(id2 != id1); // IDs are monotonic, never reused
    REQUIRE(b.contains(id2));
    REQUIRE(b.activeCount() == 1);
}

TEST_CASE("CFeatureSetBundle get on freed ID throws", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track{});
    b.free(id);

    REQUIRE_THROWS_AS(b.get(id), std::out_of_range);
}

TEST_CASE("CFeatureSetBundle contains true/false", "[bundle]")
{
    Bundle b;
    auto id = b.allocate(Track{});
    REQUIRE(b.contains(id));
    REQUIRE_FALSE(b.contains(CFeatureTrackID{id.value() + 100U}));
}

TEST_CASE("CFeatureSetBundle getTerminatedIDs", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track{});
    auto id2 = b.allocate(Track{});
    auto id3 = b.allocate(Track{});

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
    [[maybe_unused]] auto id1 = b.allocate(Track{});
    [[maybe_unused]] auto id2 = b.allocate(Track{});

    int count = 0;
    b.forEachActive(
        [&](CFeatureTrackID id, Track &t)
        {
            (void)id;
            (void)t;
            ++count;
        });
    REQUIRE(count == 2);
}

TEST_CASE("CFeatureSetBundle clearInactive keeps specified IDs", "[bundle]")
{
    Bundle b;
    auto id1 = b.allocate(Track{});
    auto id2 = b.allocate(Track{});
    auto id3 = b.allocate(Track{});

    std::vector<CFeatureTrackID> keep = {id1, id3};
    b.clearInactive(keep);

    REQUIRE(b.activeCount() == 2);
    REQUIRE(b.contains(id1));
    REQUIRE_FALSE(b.contains(id2));
    REQUIRE(b.contains(id3));
}

TEST_CASE("CFeatureSetBundle clearInactive with empty keep removes all", "[bundle]")
{
    Bundle b;
    REQUIRE(b.allocate(Track{}) == CFeatureTrackID{1U});
    REQUIRE(b.allocate(Track{}) == CFeatureTrackID{2U});

    std::vector<CFeatureTrackID> keep = {};
    b.clearInactive(keep);

    REQUIRE(b.activeCount() == 0);
}

TEST_CASE("CFeatureSetBundle full pool throws", "[bundle]")
{
    CFeatureSetBundle<Track, 2> b;
    [[maybe_unused]] auto id1 = b.allocate(Track{});
    [[maybe_unused]] auto id2 = b.allocate(Track{});

    REQUIRE_THROWS(b.allocate(Track{}));
}

TEST_CASE("Bundle reports an active duplicate even when all slots are full", "[bundle]")
{
    CFeatureSetBundle<Track, 1> bundle;
    const CFeatureTrackID id{7U};
    REQUIRE(bundle.allocate(Track{id}) == id);
    REQUIRE_THROWS_AS(bundle.allocate(Track{id}), std::invalid_argument);
}

TEST_CASE("CFeatureSetBundle empty pool operations", "[bundle]")
{
    Bundle b;
    REQUIRE(b.activeCount() == 0);
    REQUIRE(b.getTerminatedIDs().empty());

    int count = 0;
    b.forEachActive([&](CFeatureTrackID, Track &) { ++count; });
    REQUIRE(count == 0);
}

TEST_CASE("CFeatureSetBundle free unknown ID throws", "[bundle]")
{
    Bundle b;
    REQUIRE_THROWS_AS(b.free(CFeatureTrackID{999U}), std::out_of_range);
}

TEST_CASE("CFeatureSetBundle const get", "[bundle]")
{
    Bundle b;
    Track t;
    t.addKeypointToTrack({1.0, 2.0}, CFrameID{5U});
    auto id = b.allocate(std::move(t));

    const auto &cb = b;
    REQUIRE(cb.get(id).getTrackLength() == 1);
}

TEST_CASE("Generic sets and tracks keep separate bundle ID domains", "[bundle]")
{
    GenericBundle sets;
    Bundle tracks;

    const SetID set_id = sets.allocate(GenericSet{});
    const CFeatureTrackID track_id = tracks.allocate(Track{});

    REQUIRE(set_id == 1U);
    REQUIRE(track_id == CFeatureTrackID{1U});
    REQUIRE(sets.get(set_id).getID() == set_id);
    REQUIRE(tracks.get(track_id).getID() == track_id);
}

TEST_CASE("Bundle preserves explicit track IDs and advances automatic IDs", "[bundle]")
{
    Bundle bundle;
    const CFeatureTrackID explicit_id{100U};

    REQUIRE(bundle.allocate(Track{explicit_id}) == explicit_id);
    REQUIRE(bundle.allocate(Track{CFeatureTrackID{5U}}) == CFeatureTrackID{5U});
    REQUIRE(bundle.allocate(Track{}) == CFeatureTrackID{101U});
    REQUIRE(bundle.get(explicit_id).getID() == explicit_id);
}

TEST_CASE("Bundle rejects active duplicates and accepts caller reuse after free", "[bundle]")
{
    Bundle bundle;
    const CFeatureTrackID id{50U};
    REQUIRE(bundle.allocate(Track{id}) == id);

    REQUIRE_THROWS_AS(bundle.allocate(Track{id}), std::invalid_argument);
    REQUIRE(bundle.activeCount() == 1U);
    bundle.free(id);
    REQUIRE(bundle.allocate(Track{id}) == id);
}

TEST_CASE("Mutable bundle access cannot replace an active track ID", "[bundle]")
{
    Bundle bundle;
    const CFeatureTrackID first{1U};
    const CFeatureTrackID second{2U};
    Track initial{first};
    initial.addKeypointToTrack({1.0, 2.0}, CFrameID{3U});
    REQUIRE(bundle.allocate(std::move(initial)) == first);

    REQUIRE_THROWS_AS((bundle.get(first) = Track{second}), std::logic_error);
    REQUIRE(bundle.get(first).getID() == first);
    REQUIRE(bundle.get(first).getFrameIDs().size() == 1U);
    REQUIRE(bundle.get(first).getKeypoints().size() == 1U);
    REQUIRE(bundle.get(first).getFrameIDs()[0] == CFrameID{3U});
    REQUIRE(bundle.allocate(Track{second}) == second);
    REQUIRE(bundle.activeCount() == 2U);
}

TEST_CASE("Automatic ID allocation fails after the 64-bit range is exhausted", "[bundle]")
{
    Bundle bundle;
    const CFeatureTrackID last_id{std::numeric_limits<SetID>::max()};
    REQUIRE(bundle.allocate(Track{last_id}) == last_id);
    REQUIRE_THROWS_AS(bundle.allocate(Track{}), std::overflow_error);
    REQUIRE(bundle.activeCount() == 1U);
}
