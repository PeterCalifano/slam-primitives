#!/usr/bin/env bash
# Installs the CUDA toolkit from NVIDIA's apt repository for standalone
# (non-devcontainer) image builds. The devcontainer flow installs CUDA via the
# ghcr.io/devcontainers/features/nvidia-cuda feature instead, so this script
# is a no-op unless INSTALL_CUDA=on is passed as a build arg.
set -euo pipefail

install_cuda="${INSTALL_CUDA:-off}"
cuda_version="${CUDA_VERSION:-12.9}"

if [[ "$install_cuda" != "on" ]]; then
  echo "cuda-setup.sh: INSTALL_CUDA is not 'on', skipping CUDA toolkit install."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "cuda-setup.sh: apt-get not found, cannot install CUDA toolkit." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "cuda-setup.sh: /etc/os-release not found, cannot detect base OS." >&2
  exit 1
fi
source /etc/os-release

case "${ID:-}-${VERSION_ID:-}" in
  ubuntu-24.04) repo_tag="ubuntu2404" ;;
  ubuntu-22.04) repo_tag="ubuntu2204" ;;
  ubuntu-20.04) repo_tag="ubuntu2004" ;;
  debian-12)    repo_tag="debian12" ;;
  *)
    echo "cuda-setup.sh: no CUDA apt repo mapping for base OS '${ID:-?} ${VERSION_ID:-?}'." >&2
    exit 1
    ;;
esac

arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) repo_arch="x86_64" ;;
  arm64) repo_arch="sbsa" ;;
  *)
    echo "cuda-setup.sh: unsupported architecture '${arch}'." >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

keyring_deb="/tmp/cuda-keyring.deb"
curl -fsSL \
  "https://developer.download.nvidia.com/compute/cuda/repos/${repo_tag}/${repo_arch}/cuda-keyring_1.1-1_all.deb" \
  -o "$keyring_deb"
dpkg -i "$keyring_deb"
rm -f "$keyring_deb"

# e.g. 12.9 -> cuda-toolkit-12-9
cuda_pkg="cuda-toolkit-${cuda_version//./-}"
apt-get update
apt-get install -y --no-install-recommends "$cuda_pkg"

apt-get clean
rm -rf /var/lib/apt/lists/*
