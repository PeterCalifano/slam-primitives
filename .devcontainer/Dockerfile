FROM mcr.microsoft.com/devcontainers/cpp:1-ubuntu-24.04

ARG REINSTALL_CMAKE_VERSION_FROM_SOURCE="none"
#"3.28.1"
ARG ROS_MODE="none"
ARG ROS_DISTRO=""
ARG ROS_PROFILE="ros-base"

# Optionally install the cmake for vcpkg
COPY ./reinstall-cmake.sh /tmp/

RUN if [ "${REINSTALL_CMAKE_VERSION_FROM_SOURCE}" != "none" ]; then \
        chmod +x /tmp/reinstall-cmake.sh && /tmp/reinstall-cmake.sh ${REINSTALL_CMAKE_VERSION_FROM_SOURCE}; \
    fi \
    && rm -f /tmp/reinstall-cmake.sh

# Default package setup (edit .devcontainer/custom-setup.sh for your needs).
# Valgrind is built from source by default; disable with
# --build-arg INSTALL_VALGRIND=false, or pin via --build-arg VALGRIND_VERSION=x.y.z.
ARG INSTALL_VALGRIND="on"
ARG VALGRIND_VERSION="3.27.1"
COPY ./custom-setup.sh /tmp/custom-setup.sh
RUN chmod +x /tmp/custom-setup.sh \
    && INSTALL_VALGRIND="${INSTALL_VALGRIND}" VALGRIND_VERSION="${VALGRIND_VERSION}" /tmp/custom-setup.sh \
    && rm -f /tmp/custom-setup.sh

# Optional ROS/ROS 2 install (configured by build args).
COPY ./ros-setup.sh /tmp/ros-setup.sh
RUN chmod +x /tmp/ros-setup.sh \
    && ROS_MODE="${ROS_MODE}" ROS_DISTRO="${ROS_DISTRO}" ROS_PROFILE="${ROS_PROFILE}" /tmp/ros-setup.sh \
    && rm -f /tmp/ros-setup.sh

# Optional CUDA toolkit for standalone (non-devcontainer) builds.
# The devcontainer flow installs CUDA via the nvidia-cuda feature instead.
# Enable with: docker build --build-arg INSTALL_CUDA=on .devcontainer
ARG INSTALL_CUDA="off"
ARG CUDA_VERSION="12.9"
COPY ./cuda-setup.sh /tmp/cuda-setup.sh
RUN chmod +x /tmp/cuda-setup.sh \
    && INSTALL_CUDA="${INSTALL_CUDA}" CUDA_VERSION="${CUDA_VERSION}" /tmp/cuda-setup.sh \
    && rm -f /tmp/cuda-setup.sh

# CUDA environment for standalone use (harmless when CUDA is absent; the
# devcontainer remoteEnv sets the same values for the editor environment).
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

# Add export for gpg authentication to bashrc (system-wide; image builds as root)
RUN echo "export GPG_TTY=\$(tty)" >> /etc/bash.bashrc

# [Optional] Uncomment this section to install additional vcpkg ports.
# RUN su vscode -c "${VCPKG_ROOT}/vcpkg install <your-port-name-here>"

# [Optional] Uncomment this section to install additional packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>
