#!/usr/bin/env bash
# Created by Pietro Califano and GPT-5.2 Codex, Dec 2025
set -euo pipefail

# Get paths to files
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVCONTAINER_DIR="${ROOT_DIR}/.devcontainer"
DEVCONTAINER_JSON="${DEVCONTAINER_DIR}/devcontainer.json"
DOCKERFILE="${DEVCONTAINER_DIR}/Dockerfile"
DEVCONTAINER_JSON_WRITER="${DEVCONTAINER_DIR}/update_devcontainer_json.py"

# Define supported options
BASE_OPTIONS=("ubuntu-24.04" "ubuntu-22.04" "ubuntu-20.04" "ubuntu-18.04" "debian-12" "debian-11" "custom")
ROS1_DISTROS=("noetic" "melodic")
ROS2_DISTROS=("humble" "iron" "jazzy" "rolling")
ROS_PROFILES=("ros-base" "desktop" "desktop-full")
ROS2_PROFILES=("ros-base" "desktop")

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "Dockerfile not found at: $DOCKERFILE"
  exit 1
fi
if [[ ! -f "$DEVCONTAINER_JSON_WRITER" ]]; then
  echo "Devcontainer JSON writer not found at: $DEVCONTAINER_JSON_WRITER"
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: ./configure_devcontainer.sh [options]

Options:
  --cuda               Enable CUDA support.
  --base <name>        Base image tag (ubuntu-24.04, ubuntu-22.04, ubuntu-20.04, ubuntu-18.04, debian-12, debian-11, custom).
  --base-image <img>   Full base image name (overrides --base).
  --ros <distro>       Install ROS 1 with selected distro (noetic, melodic).
  --ros2 <distro>      Install ROS 2 with selected distro (humble, iron, jazzy, rolling).
  --ros-profile <p>    ROS package profile (ros-base, desktop, desktop-full).
  --non-interactive    Fail if required options are missing instead of prompting.
  -h, --help           Show this help.

Examples:
  ./configure_devcontainer.sh --cuda --base ubuntu-24.04 --ros2 jazzy
  ./configure_devcontainer.sh --no-cuda --base debian-12
  ./configure_devcontainer.sh --base-image ubuntu:20.04 --ros noetic

Note:
  CUDA is off by default (use --cuda to enable).
  ROS 1 supports Ubuntu 18.04/20.04; ROS 2 supports Ubuntu 22.04+.
EOF
}

# Auxiliary functions
contains_value() {
  local value="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done
  return 1
}

file_contains() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file"
  else
    grep -q "$pattern" "$file"
  fi
}

prompt_bool() {
  local prompt="$1"
  local default="$2"
  local answer
  while true; do
    read -r -p "${prompt} [y/n] (default: ${default}) " answer
    if [[ -z "$answer" ]]; then
      answer="$default"
    fi
    case "$answer" in
      y|Y) echo "on"; return 0 ;;
      n|N) echo "off"; return 0 ;;
      *) echo "Please enter y or n." ;;
    esac
  done
}

prompt_select() {
  local prompt="$1"
  local default="$2"
  shift 2
  local -a options=("$@")
  local i=1
  echo "$prompt" >&2
  for opt in "${options[@]}"; do
    if [[ "$opt" == "$default" ]]; then
      printf "  %d) %s (default)\n" "$i" "$opt" >&2
    else
      printf "  %d) %s\n" "$i" "$opt" >&2
    fi
    ((i++))
  done
  while true; do
    read -r -p "> " choice
    if [[ -z "$choice" ]]; then
      echo "$default"
      return 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#options[@]} )); then
      echo "${options[choice-1]}"
      return 0
    fi
    for opt in "${options[@]}"; do
      if [[ "$choice" == "$opt" ]]; then
        echo "$opt"
        return 0
      fi
    done
    echo "Invalid selection." >&2
  done
}

prompt_text() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    read -r -p "${prompt} (default: ${default}) " value
    if [[ -z "$value" ]]; then
      value="$default"
    fi
    if [[ -n "$value" ]]; then
      echo "$value"
      return 0
    fi
    echo "Value cannot be empty."
  done
}

detect_ubuntu_version() {
  local value="$1"
  case "$value" in
    *ubuntu-24.04*|*ubuntu:24.04*) echo "24.04" ;;
    *ubuntu-22.04*|*ubuntu:22.04*) echo "22.04" ;;
    *ubuntu-20.04*|*ubuntu:20.04*) echo "20.04" ;;
    *ubuntu-18.04*|*ubuntu:18.04*) echo "18.04" ;;
    *) echo "" ;;
  esac
}

#######################################
# Main script 
#######################################

# Get current settings from file
current_base="ubuntu-24.04"
current_from=""
if [[ -f "$DOCKERFILE" ]]; then
  current_from="$(sed -n 's/^FROM[[:space:]]\+\([^[:space:]]\+\).*/\1/p' "$DOCKERFILE" | head -n1)"
  detected_base="$(sed -n 's/^FROM .*devcontainers\/cpp:1-\([a-z0-9.\-]*\).*/\1/p' "$DOCKERFILE" | head -n1)"
  if [[ -n "$detected_base" ]]; then
    current_base="$detected_base"
  fi
fi

cuda_default="off"
if [[ -f "$DEVCONTAINER_JSON" ]] && file_contains "nvidia-cuda" "$DEVCONTAINER_JSON"; then
  cuda_default="on"
fi

ros_mode_default="none"
ros_distro_default=""
ros_profile_default="ros-base"
if [[ -f "$DEVCONTAINER_JSON" ]]; then
  ros_mode_detected="$(sed -n 's/.*"ROS_MODE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DEVCONTAINER_JSON" | head -n1)"
  ros_distro_detected="$(sed -n 's/.*"ROS_DISTRO"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DEVCONTAINER_JSON" | head -n1)"
  ros_profile_detected="$(sed -n 's/.*"ROS_PROFILE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DEVCONTAINER_JSON" | head -n1)"
  if [[ -z "$ros_profile_detected" ]]; then
    ros_profile_detected="$(sed -n 's/.*"ROS_INSTALL_TYPE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DEVCONTAINER_JSON" | head -n1)"
  fi
  if [[ -n "$ros_mode_detected" ]]; then
    ros_mode_default="$ros_mode_detected"
  fi
  if [[ -n "$ros_distro_detected" ]]; then
    ros_distro_default="$ros_distro_detected"
  fi
  if [[ -n "$ros_profile_detected" ]]; then
    ros_profile_default="$ros_profile_detected"
  fi
fi

# Set default values from current configuration
CUDA="$cuda_default"
BASE="$current_base"
BASE_IMAGE=""
ROS_MODE="$ros_mode_default"
ROS_DISTRO="$ros_distro_default"
ROS_PROFILE="$ros_profile_default"
NON_INTERACTIVE="no"
CUDA_SET="no"
BASE_SET="no"
BASE_IMAGE_SET="no"
ROS_MODE_SET="no"
ROS_DISTRO_SET="no"
ROS_PROFILE_SET="no"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cuda)
      CUDA="on"
      CUDA_SET="yes"
      ;;
    --no-cuda)
      CUDA="off"
      CUDA_SET="yes"
      ;;
    --base)
      shift
      BASE="${1:-}"
      BASE_SET="yes"
      ;;
    --base-image)
      shift
      BASE_IMAGE="${1:-}"
      BASE_IMAGE_SET="yes"
      ;;
    --ros)
      ROS_MODE="ros"
      ROS_MODE_SET="yes"
      if [[ $# -ge 2 && "${2}" != -* ]]; then
        shift
        ROS_DISTRO="$1"
        ROS_DISTRO_SET="yes"
      fi
      ;;
    --ros2)
      ROS_MODE="ros2"
      ROS_MODE_SET="yes"
      if [[ $# -ge 2 && "${2}" != -* ]]; then
        shift
        ROS_DISTRO="$1"
        ROS_DISTRO_SET="yes"
      fi
      ;;
    --ros-profile)
      shift
      ROS_PROFILE="${1:-}"
      if [[ -n "$ROS_PROFILE" ]]; then
        ROS_PROFILE_SET="yes"
      fi
      ;;
    --non-interactive) NON_INTERACTIVE="yes" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# Pre-fill defaults for interactive prompts
if [[ "$NON_INTERACTIVE" != "yes" ]]; then
  if [[ "$ROS_MODE" == "ros" && -z "$ROS_DISTRO" ]]; then
    ROS_DISTRO="${ROS1_DISTROS[0]}"
  elif [[ "$ROS_MODE" == "ros2" && -z "$ROS_DISTRO" ]]; then
    ROS_DISTRO="${ROS2_DISTROS[0]}"
  fi
fi

# Prompt user for options
if [[ "$NON_INTERACTIVE" != "yes" ]]; then
  # Interactive mode
  # CUDA
  if [[ "$CUDA_SET" != "yes" ]]; then
    cuda_prompt_default="n"
    if [[ "$CUDA" == "on" ]]; then
      cuda_prompt_default="y"
    fi
    CUDA="$(prompt_bool "Enable CUDA support?" "$cuda_prompt_default")"
  fi

  echo "Selected CUDA support: $CUDA"

  # Base image
  if [[ -z "$BASE_IMAGE" && "$BASE_SET" != "yes" ]]; then
    if ! contains_value "$BASE" "${BASE_OPTIONS[@]}"; then
      BASE="${BASE_OPTIONS[0]}"
    fi
    echo "Current base image: $BASE"
    BASE="$(prompt_select "Select base image:" "$BASE" "${BASE_OPTIONS[@]}")"
  fi
  if [[ -z "$BASE_IMAGE" && "$BASE" != "custom" ]]; then
    if ! contains_value "$BASE" "${BASE_OPTIONS[@]}"; then
      echo "Invalid --base value: $BASE"
      exit 1
    fi
  fi
  if [[ -z "$BASE_IMAGE" && "$BASE" == "custom" ]]; then
    default_custom="${current_from:-mcr.microsoft.com/devcontainers/cpp:1-ubuntu-24.04}"
    BASE_IMAGE="$(prompt_text "Enter full base image" "$default_custom")"
  fi

  echo "Selected base image: $BASE"

  # ROS / ROS 2
  if [[ "$ROS_MODE_SET" != "yes" ]]; then
    ROS_MODE="$(prompt_select "Select ROS option:" "$ROS_MODE" "none" "ros" "ros2")"
  fi
  case "$ROS_MODE" in
    ros)
      if ! contains_value "$ROS_DISTRO" "${ROS1_DISTROS[@]}"; then
        if [[ "$ROS_DISTRO_SET" == "yes" ]]; then
          echo "Invalid --ros distro: $ROS_DISTRO"
          exit 1
        fi
        ROS_DISTRO="${ROS1_DISTROS[0]}"
      fi
      if [[ "$ROS_DISTRO_SET" != "yes" ]]; then
        ROS_DISTRO="$(prompt_select "Select ROS 1 distro:" "$ROS_DISTRO" "${ROS1_DISTROS[@]}")"
      fi
      ;;
    ros2)
      if ! contains_value "$ROS_DISTRO" "${ROS2_DISTROS[@]}"; then
        if [[ "$ROS_DISTRO_SET" == "yes" ]]; then
          echo "Invalid --ros2 distro: $ROS_DISTRO"
          exit 1
        fi
        ROS_DISTRO="${ROS2_DISTROS[0]}"
      fi
      if [[ "$ROS_DISTRO_SET" != "yes" ]]; then
        ROS_DISTRO="$(prompt_select "Select ROS 2 distro:" "$ROS_DISTRO" "${ROS2_DISTROS[@]}")"
      fi
      ;;
    none)
      ROS_DISTRO=""
      ;;
  esac

  echo "Selected ROS mode: $ROS_MODE"

  if [[ "$ROS_MODE" != "none" ]]; then
    if [[ "$ROS_MODE" == "ros2" ]]; then
      if ! contains_value "$ROS_PROFILE" "${ROS2_PROFILES[@]}"; then
        if [[ "$ROS_PROFILE_SET" == "yes" ]]; then
          echo "Invalid --ros-profile value for ROS 2: $ROS_PROFILE"
          exit 1
        fi
        ROS_PROFILE="${ROS2_PROFILES[0]}"
      fi
      if [[ "$ROS_PROFILE_SET" != "yes" ]]; then
        ROS_PROFILE="$(prompt_select "Select ROS 2 profile:" "$ROS_PROFILE" "${ROS2_PROFILES[@]}")"
      fi
    else
      if ! contains_value "$ROS_PROFILE" "${ROS_PROFILES[@]}"; then
        if [[ "$ROS_PROFILE_SET" == "yes" ]]; then
          echo "Invalid --ros-profile value: $ROS_PROFILE"
          exit 1
        fi
        ROS_PROFILE="${ROS_PROFILES[0]}"
      fi
      if [[ "$ROS_PROFILE_SET" != "yes" ]]; then
        ROS_PROFILE="$(prompt_select "Select ROS profile:" "$ROS_PROFILE" "${ROS_PROFILES[@]}")"
      fi
    fi
  fi
  

else
  # Validate options in non-interactive mode
  if [[ -z "$BASE_IMAGE" ]]; then
    if ! contains_value "$BASE" "${BASE_OPTIONS[@]}"; then
      echo "Invalid --base value: $BASE"
      exit 1
    fi
    if [[ "$BASE" == "custom" ]]; then
      echo "Use --base-image to specify a custom image in non-interactive mode."
      exit 1
    fi
  fi
  if [[ "$ROS_MODE" == "ros" ]]; then
    if ! contains_value "$ROS_DISTRO" "${ROS1_DISTROS[@]}"; then
      echo "Invalid --ros distro: $ROS_DISTRO"
      exit 1
    fi
    if ! contains_value "$ROS_PROFILE" "${ROS_PROFILES[@]}"; then
      echo "Invalid --ros-profile value: $ROS_PROFILE"
      exit 1
    fi
  elif [[ "$ROS_MODE" == "ros2" ]]; then
    if ! contains_value "$ROS_DISTRO" "${ROS2_DISTROS[@]}"; then
      echo "Invalid --ros2 distro: $ROS_DISTRO"
      exit 1
    fi
    if ! contains_value "$ROS_PROFILE" "${ROS2_PROFILES[@]}"; then
      echo "Invalid --ros-profile value for ROS 2: $ROS_PROFILE"
      exit 1
    fi
  elif [[ "$ROS_MODE" != "none" ]]; then
    echo "Invalid ROS mode: $ROS_MODE"
    exit 1
  fi
fi

effective_base="$BASE"
if [[ -n "$BASE_IMAGE" ]]; then
  effective_base="$BASE_IMAGE"
fi
ubuntu_version="$(detect_ubuntu_version "$effective_base")"

if [[ "$ROS_MODE" != "none" ]]; then
  if [[ -n "$ubuntu_version" ]]; then
    if [[ "$ROS_MODE" == "ros2" ]]; then
      if [[ "$ubuntu_version" != "22.04" && "$ubuntu_version" != "24.04" ]]; then
        echo "ROS 2 requires Ubuntu 22.04 or newer (detected ${ubuntu_version})."
        exit 1
      fi
    else
      if [[ "$ubuntu_version" != "18.04" && "$ubuntu_version" != "20.04" ]]; then
        echo "ROS 1 requires Ubuntu 18.04 or 20.04 (detected ${ubuntu_version})."
        exit 1
      fi
      if [[ "$ROS_DISTRO" == "noetic" && "$ubuntu_version" != "20.04" ]]; then
        echo "ROS 1 noetic requires Ubuntu 20.04 (detected ${ubuntu_version})."
        exit 1
      fi
      if [[ "$ROS_DISTRO" == "melodic" && "$ubuntu_version" != "18.04" ]]; then
        echo "ROS 1 melodic requires Ubuntu 18.04 (detected ${ubuntu_version})."
        exit 1
      fi
    fi
  else
    if [[ "$effective_base" == *debian* ]]; then
      echo "ROS requires Ubuntu 18.04/20.04 (ROS 1) or 22.04+ (ROS 2); Debian base selected."
      exit 1
    fi
    echo "Warning: Could not detect Ubuntu version for base image; ROS compatibility not enforced." >&2
  fi
fi

# Backup existing file
timestamp="$(date +%Y%m%d%H%M%S)"
if [[ -f "$DEVCONTAINER_JSON" ]]; then
  cp "$DEVCONTAINER_JSON" "${DEVCONTAINER_JSON}.bak.${timestamp}"
fi
if [[ -f "$DOCKERFILE" ]]; then
  cp "$DOCKERFILE" "${DOCKERFILE}.bak.${timestamp}"
fi

# Write updated Dockerfile
tmp_dockerfile="$(mktemp)"
if [[ -n "$BASE_IMAGE" ]]; then
  new_from="FROM ${BASE_IMAGE}"
else
  new_from="FROM mcr.microsoft.com/devcontainers/cpp:1-${BASE}"
fi

if ! awk -v new_from="$new_from" '
  BEGIN { replaced=0 }
  /^FROM[[:space:]]+/ && replaced==0 {
    print new_from
    replaced=1
    next
  }
  { print }
  END { if (replaced==0) exit 1 }
' "$DOCKERFILE" > "$tmp_dockerfile"; then
  rm -f "$tmp_dockerfile"
  echo "Failed to update Dockerfile base image."
  exit 1
fi
mv "$tmp_dockerfile" "$DOCKERFILE"

# Write updated devcontainer.json using python script
CUDA="$CUDA" ROS_MODE="$ROS_MODE" ROS_DISTRO="$ROS_DISTRO" ROS_PROFILE="$ROS_PROFILE" \
  python3 "$DEVCONTAINER_JSON_WRITER" > "$DEVCONTAINER_JSON"

echo "Updated:"
echo "  - ${DOCKERFILE}"
echo "  - ${DEVCONTAINER_JSON}"
