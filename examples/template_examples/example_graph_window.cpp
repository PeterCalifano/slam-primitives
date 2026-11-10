/// @file example_graph_window.cpp
/// @brief Demonstrate bounded frame retention, immediate shrinking and later growth.
/// @details Expected output:
/// window=3 retained=3
/// window=1 retained=1 visible=2
/// window=4 retained=2
#include <slam-primitives/covisibility/CCovisibilityGraph.h>

#include <array>
#include <cstdint>
#include <iostream>

int main()
{
    slam_primitives::CCovisibilityGraph<4, slam_primitives::CFeatureTrackID> graph{3U};
    const std::array<slam_primitives::CFeatureTrackID, 2> ids{
        slam_primitives::CFeatureTrackID{11U}, slam_primitives::CFeatureTrackID{12U}};
    for (std::uint32_t frame = 0U; frame < 5U; ++frame)
    {
        graph.pushFrame(slam_primitives::CFrameID{frame});
        graph.addVisibilityLinks(slam_primitives::CFrameID{frame}, ids);
    }
    std::cout << "window=" << graph.getWindowSize() << " retained=" << graph.frameCount() << '\n';
    graph.setWindowSize(1U);
    std::cout << "window=" << graph.getWindowSize() << " retained=" << graph.frameCount()
              << " visible=" << graph.getLastFrameVisibility().size() << '\n';
    graph.setWindowSize(4U);
    graph.pushFrame(slam_primitives::CFrameID{5U});
    std::cout << "window=" << graph.getWindowSize() << " retained=" << graph.frameCount() << '\n';
    return 0;
}
