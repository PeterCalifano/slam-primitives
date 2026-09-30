"""Exercise generated Python track and frame ID round trips."""

from __future__ import annotations

import slam_primitives


def main() -> None:
    """Check large IDs, unsigned frames, and vector return conversion."""
    assert slam_primitives.HAS_WRAPPER
    track_id = 1 << 40
    frame_id = (1 << 32) - 1

    point = slam_primitives.SFeatureLocation2D()
    point.u = 1.0
    point.v = 2.0

    track = slam_primitives.CFeatureTrack2D(track_id)
    assert track.getID() == track_id
    assert not track.addKeypointToTrack(point, frame_id)
    assert track.getFrameIDs() == [frame_id]
    assert track.hasKeypointAtFrame(frame_id)

    bundle = slam_primitives.CFeatureTrackBundle2D()
    assert (
        bundle.allocateTrackWithInitialObservationAndID(track_id, point, frame_id)
        == track_id
    )
    assert bundle.getFrameIDs(track_id) == [frame_id]

    graph = slam_primitives.CCovisibilityGraphWrapper()
    graph.pushFrame(frame_id)
    graph.addVisibilityLinks(frame_id, [track_id])
    assert graph.getVisibleFeatures(frame_id) == [track_id]


if __name__ == "__main__":
    main()
