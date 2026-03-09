#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if ! command -v apt-get >/dev/null 2>&1; then
  echo "custom-setup.sh: apt-get not found, skipping package install."
  exit 0
fi

apt-get update
apt-get upgrade -y
apt-get install -y \
  build-essential \
  cmake \
  git \
  curl \
  wget \
  nano \
  pkg-config \
  gdb \
  python3 \
  python3-pip \
  libssl-dev \
  libffi-dev \
  software-properties-common \
  sudo \
  unzip \
  zip \
  man

apt-get install -y \
  gcc \
  g++ \
  gfortran \
  clang \
  gcc-mingw-w64

apt-get install -y \
  libboost-all-dev \
  libeigen3-dev \
  libsdl2-dev

os_id=""
os_version=""
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  os_id="${ID:-}"
  os_version="${VERSION_ID:-}"
fi

if [[ "$os_id" == "ubuntu" && ( "$os_version" == "18.04" || "$os_version" == "20.04" ) ]]; then
  apt-get install -y qt5-default
else
  apt-get install -y qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
