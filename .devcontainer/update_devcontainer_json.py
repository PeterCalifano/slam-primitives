#!/usr/bin/env python3
"""Regenerate .devcontainer/devcontainer.json from environment options.

Merge-preserve behaviour: the existing devcontainer.json (if any) is loaded
first and only the keys managed by this script are rewritten. Everything else
(remoteEnv extras, customizations settings, mounts, ...) is kept verbatim, so
re-running the configure script never wipes project-specific settings. The
default VS Code extension set (DEFAULT_EXTENSIONS) is seeded and guaranteed
present, while any extra extensions in the file are preserved. Output is plain
JSON (JSONC comments in the input are stripped).
"""
import json
import os
import re
import sys

DEFAULT_CUDA_VERSION = "12.9"
DEFAULT_GPU_RUNTIME = "docker"
SUPPORTED_GPU_RUNTIMES = ("docker", "podman")

# remoteEnv entries owned by the CUDA option.
CUDA_REMOTE_ENV = {
    "PATH": "/usr/local/cuda/bin:${containerEnv:PATH}",
    "LD_LIBRARY_PATH": "/usr/local/cuda/lib64:${containerEnv:LD_LIBRARY_PATH}",
    "CUDA_HOME": "/usr/local/cuda",
}

# containerEnv entries owned by the ROS option.
ROS_CONTAINER_ENV = {
    "ROS_LOCALHOST_ONLY": "1",
    "ROS_DOMAIN_ID": "42",
}

CUDA_FEATURE_KEY = "ghcr.io/devcontainers/features/nvidia-cuda:2"

# Default VS Code extensions seeded into customizations.vscode.extensions.
# Managed like the conda/python features: regeneration guarantees these are
# present (even from scratch), while any extra extensions already in the file
# are preserved. Edit this list to change the template's editor defaults.
DEFAULT_EXTENSIONS = [
    "ms-vscode.cpptools",
    "ms-vscode.cpptools-themes",
    "ms-vscode.cmake-tools",
    "twxs.cmake",
    "njpwerner.autodocstring",
    "ms-python.autopep8",
    "ms-python.vscode-pylance",
    "ms-vscode.cpp-devtools",
    "Anthropic.claude-code",
    "ms-python.debugpy",
    "openai.chatgpt",
    "Gruntfuggly.todo-tree",
    "ms-vscode.cpptools-extension-pack",
    "ms-python.python",
    "donjayamanne.python-extension-pack",
    "llvm-vs-code-extensions.vscode-clangd",
]

# GPU passthrough runArgs are selected by the configure script. Docker's
# standard NVIDIA Container Toolkit path uses --gpus all, while Podman uses CDI.
DOCKER_GPU_RUN_ARGS = ["--gpus", "all"]
PODMAN_GPU_RUN_ARGS = [
    "--device",
    "nvidia.com/gpu=all",
    "--security-opt=label=disable",
]


def _gpu_run_args(gpu_runtime: str) -> list[str]:
    """Return managed GPU runArgs for the requested container engine.

    Example:
        args_ = _gpu_run_args("docker")
        print(args_)
        # Output:
        # ['--gpus', 'all']
    """
    if gpu_runtime == "docker":
        return list(DOCKER_GPU_RUN_ARGS)
    if gpu_runtime == "podman":
        return list(PODMAN_GPU_RUN_ARGS)
    print(
        "update_devcontainer_json.py: DEVCONTAINER_GPU_RUNTIME must be one of: "
        + ", ".join(SUPPORTED_GPU_RUNTIMES),
        file=sys.stderr,
    )
    sys.exit(1)


def strip_gpu_run_args(args: list) -> list:
    """Drop managed GPU passthrough pairs, preserving unrelated runArgs.

    Removes Docker, CDI, and SELinux-label forms owned by this updater so
    toggling/regenerating stays idempotent and migrates old files. Other
    ``--device`` entries are left untouched.
    """
    out = []
    i = 0
    n = len(args)
    while i < n:
        cur = args[i]
        nxt = args[i + 1] if i + 1 < n else None
        if cur == "--gpus" and nxt == "all":
            i += 2
            continue
        if cur == "--gpus=all":
            i += 1
            continue
        if cur == "--device" and nxt == "nvidia.com/gpu=all":
            i += 2
            continue
        if cur == "--device=nvidia.com/gpu=all":
            i += 1
            continue
        if cur == "--security-opt" and nxt == "label=disable":
            i += 2
            continue
        if cur == "--security-opt=label=disable":
            i += 1
            continue
        out.append(cur)
        i += 1
    return out


def _strip_jsonc_comments(text: str) -> str:
    """Remove JSONC comments while preserving string contents.

    Example:
        cleaned_ = _strip_jsonc_comments('{"url": "https://example.invalid", // note\\n"x": 1}')
        print(cleaned_)
        # Output:
        # {"url": "https://example.invalid",
        # "x": 1}
    """
    output_: list[str] = []
    inString_ = False
    escapeNext_ = False
    index_ = 0
    textLength_ = len(text)

    while index_ < textLength_:
        char_ = text[index_]

        if inString_:
            output_.append(char_)
            if escapeNext_:
                escapeNext_ = False
            elif char_ == "\\":
                escapeNext_ = True
            elif char_ == '"':
                inString_ = False
            index_ += 1
            continue

        if char_ == '"':
            inString_ = True
            output_.append(char_)
            index_ += 1
            continue

        if char_ == "/" and index_ + 1 < textLength_:
            nextChar_ = text[index_ + 1]
            if nextChar_ == "/":
                index_ += 2
                while index_ < textLength_ and text[index_] not in "\r\n":
                    index_ += 1
                continue
            if nextChar_ == "*":
                index_ += 2
                while index_ + 1 < textLength_ and not (
                    text[index_] == "*" and text[index_ + 1] == "/"
                ):
                    if text[index_] in "\r\n":
                        output_.append(text[index_])
                    index_ += 1
                if index_ + 1 < textLength_:
                    index_ += 2
                continue

        output_.append(char_)
        index_ += 1

    return "".join(output_)


def load_existing(path: str) -> dict:
    """Load an existing devcontainer.json, tolerating JSONC comments."""
    if not os.path.isfile(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    text = _strip_jsonc_comments(text)
    # Strip trailing commas before } or ] left behind by comment removal.
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    text = text.strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        print(
            f"update_devcontainer_json.py: cannot parse existing {path}: {exc}",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> int:
    # Options come from the configure script via environment variables.
    cuda = os.environ.get("CUDA", "off")
    cuda_version = os.environ.get("CUDA_VERSION", DEFAULT_CUDA_VERSION)
    gpu_runtime = os.environ.get(
        "DEVCONTAINER_GPU_RUNTIME", DEFAULT_GPU_RUNTIME)
    ros_mode = os.environ.get("ROS_MODE", "none")
    ros_distro = os.environ.get("ROS_DISTRO", "")
    ros_profile = os.environ.get("ROS_PROFILE", "ros-base")
    existing_path = os.environ.get(
        "DEVCONTAINER_JSON_PATH",
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "devcontainer.json"),
    )

    data = load_existing(existing_path)

    data.setdefault("name", "C++")

    # Managed: build (dockerfile + ROS build args)
    build = data.get("build", {})
    if not isinstance(build, dict):
        build = {}
    build["dockerfile"] = "Dockerfile"
    if ros_mode != "none":
        build["args"] = {
            "ROS_MODE": ros_mode,
            "ROS_DISTRO": ros_distro,
            "ROS_PROFILE": ros_profile,
        }
    else:
        build.pop("args", None)
    data["build"] = build

    # Managed: features (conda + python always; nvidia-cuda when CUDA=on)
    features = data.get("features", {})
    if not isinstance(features, dict):
        features = {}
    features["ghcr.io/devcontainers/features/conda:1"] = {
        "addCondaForge": True,
        "version": "latest",
    }
    features["ghcr.io/devcontainers/features/python:1"] = {
        "installTools": True,
        "enableShared": True,
        "version": "3.12",
    }
    if cuda == "on":
        features[CUDA_FEATURE_KEY] = {
            "installCudnn": True,
            "installCudnnDev": True,
            "installNvtx": True,
            "installToolkit": True,
            "cudaVersion": cuda_version,
            "cudnnVersion": "automatic",
        }
    else:
        features.pop(CUDA_FEATURE_KEY, None)
    # Sorted for stable output regardless of option toggling history.
    data["features"] = dict(sorted(features.items()))

    # Managed: GPU passthrough runArg (CUDA only); other runArgs preserved.
    run_args = strip_gpu_run_args(data.get("runArgs", []))
    if cuda == "on":
        run_args = _gpu_run_args(gpu_runtime) + run_args
    if run_args:
        data["runArgs"] = run_args
    else:
        data.pop("runArgs", None)

    # Managed: CUDA entries in remoteEnv; unrelated entries preserved.
    remote_env = data.get("remoteEnv", {})
    if not isinstance(remote_env, dict):
        remote_env = {}
    if cuda == "on":
        remote_env.update(CUDA_REMOTE_ENV)
    else:
        for key in CUDA_REMOTE_ENV:
            remote_env.pop(key, None)
    if remote_env:
        data["remoteEnv"] = remote_env
    else:
        data.pop("remoteEnv", None)

    # Managed: ROS entries in containerEnv; unrelated entries preserved.
    container_env = data.get("containerEnv", {})
    if not isinstance(container_env, dict):
        container_env = {}
    if ros_mode != "none":
        container_env.update(ROS_CONTAINER_ENV)
    else:
        for key in ROS_CONTAINER_ENV:
            container_env.pop(key, None)
    if container_env:
        data["containerEnv"] = container_env
    else:
        data.pop("containerEnv", None)

    # Managed: default VS Code extensions. Ensures DEFAULT_EXTENSIONS are present (template editor defaults), preserving any extra extensions and other customizations (e.g. settings) already in the file.
    customizations = data.get("customizations", {})
    if not isinstance(customizations, dict):
        customizations = {}
    vscode = customizations.get("vscode", {})
    if not isinstance(vscode, dict):
        vscode = {}
    existing_ext = vscode.get("extensions", [])
    if not isinstance(existing_ext, list):
        existing_ext = []
    extras = [e for e in existing_ext if e not in DEFAULT_EXTENSIONS]
    vscode["extensions"] = list(DEFAULT_EXTENSIONS) + extras
    customizations["vscode"] = vscode
    data["customizations"] = customizations

    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
