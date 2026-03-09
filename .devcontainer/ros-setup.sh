#!/usr/bin/env bash
set -Eo pipefail
set +u

ros_mode="${ROS_MODE:-none}"
ros_distro="${ROS_DISTRO:-}"
ros_profile="${ROS_PROFILE:-${ROS_INSTALL_TYPE:-ros-base}}"

# Exit early if ROS installation is not requested or incorrect setting
if [[ "$ros_mode" == "none" ]]; then
  exit 0
fi

if [[ -z "$ros_distro" ]]; then
  echo "ros-setup.sh: ROS_DISTRO is required when ROS_MODE is set."
  exit 1
fi

case "$ros_profile" in
  ros-base|desktop|desktop-full) ;;
  *)
    echo "ros-setup.sh: Invalid ROS_PROFILE '${ros_profile}'. Use ros-base, desktop, or desktop-full."
    exit 1
    ;;
esac

if [[ ! -r /etc/os-release ]]; then
  echo "ros-setup.sh: /etc/os-release not found. Cannot proceed."
  exit 1
fi

# Source OS info
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "ros-setup.sh: ROS automated installation requires Ubuntu. Cannot proceed."
  exit 1
fi

# Execute ROS installation
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y curl gnupg lsb-release ca-certificates software-properties-common

# Add ROS repository and keys
keyring="/usr/share/keyrings/ros-archive-keyring.gpg"
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | gpg --dearmor -o "$keyring"

arch="$(dpkg --print-architecture)"

# Configure ROS repository based on distro and environment
if [[ "$ros_mode" == "ros" ]]; then
  repo_url="http://packages.ros.org/ros/ubuntu"
  list_file="/etc/apt/sources.list.d/ros.list"
  
  ros_package="ros-${ros_distro}-${ros_profile}"

elif [[ "$ros_mode" == "ros2" ]]; then
  repo_url="http://packages.ros.org/ros2/ubuntu"
  list_file="/etc/apt/sources.list.d/ros2.list"
  if [[ "$ros_profile" == "desktop-full" ]]; then
    echo "ros-setup.sh: ROS 2 does not provide 'desktop-full'. Falling back to 'desktop'..."
    ros_profile="desktop"
  fi
  ros_package="ros-${ros_distro}-${ros_profile}"

else
  echo "ros-setup.sh: Unknown ROS_MODE '$ros_mode'."
  exit 1
fi

# Get deb package
echo "deb [arch=${arch} signed-by=${keyring}] ${repo_url} ${UBUNTU_CODENAME} main" > "$list_file"

# Install ROS dev tools
apt-get update
apt-get install -y "$ros_package" python3-rosdep
apt-get install ros-dev-tools -y

# Install additional packages for ROS 2
if [[ "$ros_mode" == "ros2" ]]; then
  apt-get install -y python3-colcon-common-extensions
fi

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

# Source the ROS setup file
echo "source /opt/ros/${ros_distro}/setup.bash" >> ~/.bashrc
source /opt/ros/${ros_distro}/setup.bash
rosdep init
rosdep update

set -eu