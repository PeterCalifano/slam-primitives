cmake_minimum_required(VERSION 3.16)

project(slam_primitives_interfaces)

# Accept the workspace-wide core option so colcon can pass one CMake argument
# set to both packages without reporting an unused-variable warning.
option(
  SLAM_PRIMITIVES_ENABLE_CUDA
  "Accepted for workspace-wide build helper compatibility."
  OFF)

find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(std_msgs REQUIRED)

rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/FeatureObservation2D.msg"
  "msg/FeatureTrack2D.msg"
  "msg/FeatureTrackArray.msg"
  DEPENDENCIES
    std_msgs
)

ament_export_dependencies(rosidl_default_runtime)
ament_package()
