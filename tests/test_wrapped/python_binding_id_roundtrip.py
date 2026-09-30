"""Exercise generated Python identifier round trips and validated frame retention."""

from __future__ import annotations

import slam_primitives


def main() -> None:
    """Check exact IDs, vector conversion, resizing and rejected unsigned window inputs."""
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
    assert bundle.allocateTrackWithInitialObservationAndID(track_id, point, frame_id) == track_id
    assert bundle.getFrameIDs(track_id) == [frame_id]

    graph = slam_primitives.CCovisibilityGraphWrapper()
    graph.pushFrame(frame_id)
    graph.addVisibilityLinks(frame_id, [track_id])
    assert graph.getVisibleFeatures(frame_id) == [track_id]

    window_graph_ = slam_primitives.CCovisibilityGraphWrapper(2)
    assert window_graph_.getWindowSize() == 2
    for frame_ in range(3):
        window_graph_.pushFrame(frame_)
        window_graph_.addVisibilityLinks(frame_, [track_id])
    assert window_graph_.getVisibleFeatures(0) == []
    assert window_graph_.getCovisibleFeatures(1, 2) == [track_id]
    window_graph_.setWindowSize(1)
    assert window_graph_.frameCount() == 1
    assert window_graph_.getVisibleFeatures(1) == []
    assert window_graph_.getVisibleFeatures(2) == [track_id]
    window_graph_.setWindowSize(4)
    assert window_graph_.frameCount() == 1

    for invalid_size_ in (0, 65, (1 << 32) - 1):
        try:
            window_graph_.setWindowSize(invalid_size_)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid window setter was accepted")
        try:
            slam_primitives.CCovisibilityGraphWrapper(invalid_size_)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid window constructor was accepted")
        assert window_graph_.getWindowSize() == 4
        assert window_graph_.getVisibleFeatures(2) == [track_id]

    # Binding conversion must reject values that cannot be represented by uint32.
    for invalid_size_ in (-1, 1 << 32):
        try:
            window_graph_.setWindowSize(invalid_size_)
        except (TypeError, OverflowError):
            pass
        else:
            raise AssertionError("Unsigned window conversion accepted an out-of-range integer")
        assert window_graph_.getWindowSize() == 4


if __name__ == "__main__":
    main()
