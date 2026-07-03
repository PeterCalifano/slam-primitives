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

# Optional valgrind, built from source. Enabled by default; disabled only when INSTALL_VALGRIND is false/off/0/no. Fail-safe: a build failure logs a warning and the image build continues without valgrind. Pinned by VALGRIND_VERSION.
vg_opt="${INSTALL_VALGRIND:-on}"
case "${vg_opt,,}" in
  false | off | 0 | no | disabled) vg_build="no" ;;
  *) vg_build="yes" ;;
esac

if [[ "$vg_build" == "yes" ]]; then
  vg_version="${VALGRIND_VERSION:-3.27.1}"
  vg_url="https://sourceware.org/pub/valgrind/valgrind-${vg_version}.tar.bz2"
  vg_tmp="$(mktemp -d)"
  # Run the build with errexit scoped to a subshell so any failure is caught here instead of aborting the whole image build.
  set +e
  (
    set -e
    apt-get install -y bzip2 libc6-dbg
    curl -fsSL "$vg_url" -o "$vg_tmp/valgrind.tar.bz2"
    tar -xjf "$vg_tmp/valgrind.tar.bz2" -C "$vg_tmp"
    cd "$vg_tmp/valgrind-${vg_version}"
    ./configure --prefix=/usr/local
    make -j"$(nproc)"
    make install
  )
  vg_status=$?
  set -e
  rm -rf "$vg_tmp"
  if [[ "$vg_status" -ne 0 ]]; then
    echo "custom-setup.sh: WARNING: valgrind ${vg_version} build failed (exit ${vg_status}); continuing without it." >&2
  else
    echo "custom-setup.sh: valgrind ${vg_version} installed from source."
  fi
fi

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
