#!/usr/bin/env python3
import json
import os
import sys

def main() -> int:
    # Get environment variables
    cuda = os.environ.get("CUDA", "off")
    ros_mode = os.environ.get("ROS_MODE", "none")
    ros_distro = os.environ.get("ROS_DISTRO", "")
    ros_profile = os.environ.get("ROS_PROFILE", "ros-base")

    # Define default features
    # LFS feature (commented out for now)
    # "ghcr.io/devcontainers/features/git-lfs:1": {
    #       "autoPull": True,
    #       "version": "latest",
    #   },
    features = {
        "ghcr.io/devcontainers/features/conda:1": {
            "addCondaForge": True,
            "version": "latest",
        },
        "ghcr.io/devcontainers/features/python:1": {
            "installTools": True,
            "enableShared": True,
            "version": "3.12",
        },
    }

    # Cuda features
    if cuda == "on":
        features["ghcr.io/devcontainers/features/nvidia-cuda:2"] = {
            "installCudnn": True,
            "installCudnnDev": True,
            "installNvtx": True,
            "installToolkit": True,
            "cudaVersion": "12.5",
            "cudnnVersion": "automatic",
        }

    # Use Dockerfile to build container
    build = {"dockerfile": "Dockerfile"}
    build_args = {}
    if ros_mode != "none":
        build_args["ROS_MODE"] = ros_mode
        build_args["ROS_DISTRO"] = ros_distro
        build_args["ROS_PROFILE"] = ros_profile
    
    # Store build args if any
    if build_args:
        build["args"] = build_args

    # Write out devcontainer.json content
    data = {
        "name": "C++",
        "build": build,
        "features": features,
    }

    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
