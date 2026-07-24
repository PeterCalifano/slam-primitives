#!/usr/bin/env python3
"""Synchronize optional ROS 2 manifests from root CMake project metadata.

Example:
    python3 ros2/tools/sync_package_metadata.py \
        --project-root . --ros2-dir ros2 --version 0.2.0

Output:
    Synchronized 2 ROS 2 package manifests.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Sequence


_STRICT_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


@dataclass(frozen=True)
class ProjectMetadata:
    """Project-owned values exported by metadata-only CMake configuration."""

    project_name: str
    version: str
    description: str
    homepage_url: str
    maintainer_name: str
    maintainer_email: str
    license: str


class PackageRole(Enum):
    """Description suffix owned by each supported overlay package role."""

    SHIM = "ROS 2 colcon shim package."
    INTERFACES = "ROS 2 message interfaces."
    GENERIC = "ROS 2 package."


@dataclass(frozen=True)
class ManifestDocument:
    """Parsed manifest with filesystem and outer-XML state."""

    path: Path
    mode: int
    original_bytes: bytes
    tree: ET.ElementTree
    leading_nodes: tuple[str, ...]
    trailing_nodes: tuple[str, ...]
    package_name: str


@dataclass(frozen=True)
class ManifestUpdate:
    """Prepared atomic replacement for one package manifest."""

    path: Path
    mode: int
    original_bytes: bytes
    updated_bytes: bytes


def _Read_cache_value(cache_text_: str, key_: str) -> str:
    """Read one non-empty field from CMakeCache.txt text."""
    prefix_ = f"{key_}:"
    for line_ in cache_text_.splitlines():
        if not line_.startswith(prefix_):
            continue
        _, separator_, value_ = line_.partition("=")
        if separator_ and value_:
            return value_
        break
    raise ValueError(f"Missing or empty CMake metadata field: {key_}")


def _Configure_project_metadata(
    project_root_: Path,
    version_: str,
) -> ProjectMetadata:
    """Configure root metadata without enabling compilers or dependencies."""
    if not _STRICT_VERSION_RE.fullmatch(version_):
        raise ValueError(
            f"ROS package version must be strict X.Y.Z, got {version_!r}"
        )

    cmake_executable_ = shutil.which("cmake")
    if cmake_executable_ is None:
        raise RuntimeError("cmake was not found on PATH")

    with tempfile.TemporaryDirectory(
        prefix="slam_primitives_ros2_metadata_"
    ) as build_directory_:
        result_ = subprocess.run(
            [
                cmake_executable_,
                "-S",
                str(project_root_),
                "-B",
                build_directory_,
                "-DPROJECT_METADATA_ONLY=ON",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result_.returncode != 0:
            raise RuntimeError(
                "Metadata-only CMake configure failed:\n"
                f"stdout:\n{result_.stdout}\n"
                f"stderr:\n{result_.stderr}"
            )
        cache_text_ = (
            Path(build_directory_) / "CMakeCache.txt"
        ).read_text(encoding="utf-8")

    cache_version_ = _Read_cache_value(
        cache_text_, "CMAKE_PROJECT_VERSION"
    )
    if cache_version_ != version_:
        raise ValueError(
            f"Resolved CMake version {cache_version_!r} does not match "
            f"requested ROS version {version_!r}"
        )

    metadata_ = ProjectMetadata(
        project_name=_Read_cache_value(
            cache_text_, "CMAKE_PROJECT_NAME"
        ),
        version=version_,
        description=_Read_cache_value(
            cache_text_, "CMAKE_PROJECT_DESCRIPTION"
        ),
        homepage_url=_Read_cache_value(
            cache_text_, "CMAKE_PROJECT_HOMEPAGE_URL"
        ),
        maintainer_name=_Read_cache_value(
            cache_text_, "PROJECT_MAINTAINER_NAME"
        ),
        maintainer_email=_Read_cache_value(
            cache_text_, "PROJECT_MAINTAINER_EMAIL"
        ),
        license=_Read_cache_value(cache_text_, "PROJECT_LICENSE"),
    )
    if "@" not in metadata_.maintainer_email:
        raise ValueError("PROJECT_MAINTAINER_EMAIL must contain '@'")
    return metadata_


def _Read_outer_xml_nodes(
    path_: Path,
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Capture comments and processing instructions outside the package root."""
    leading_nodes_: list[str] = []
    trailing_nodes_: list[str] = []
    depth_ = 0
    root_seen_ = False
    root_closed_ = False

    for event_, element_ in ET.iterparse(
        path_, events=("start", "end", "comment", "pi")
    ):
        if event_ == "start":
            root_seen_ = True
            depth_ += 1
        elif event_ == "end":
            depth_ -= 1
            if root_seen_ and depth_ == 0:
                root_closed_ = True
        elif depth_ == 0:
            serialized_node_ = ET.tostring(
                element_, encoding="unicode"
            )
            if root_closed_:
                trailing_nodes_.append(serialized_node_)
            elif not root_seen_:
                leading_nodes_.append(serialized_node_)

    return tuple(leading_nodes_), tuple(trailing_nodes_)


def _Read_manifest(path_: Path) -> ManifestDocument:
    """Parse one manifest while retaining outer nodes and file mode."""
    leading_nodes_, trailing_nodes_ = _Read_outer_xml_nodes(path_)
    parser_ = ET.XMLParser(
        target=ET.TreeBuilder(insert_comments=True, insert_pis=True)
    )
    tree_ = ET.parse(path_, parser=parser_)
    root_ = tree_.getroot()
    if root_.tag != "package":
        raise ValueError(f"Expected <package> root in {path_}")

    name_element_ = root_.find("name")
    package_name_ = (
        ""
        if name_element_ is None or name_element_.text is None
        else name_element_.text.strip()
    )
    if not package_name_:
        raise ValueError(f"Missing package name in {path_}")

    return ManifestDocument(
        path=path_,
        mode=stat.S_IMODE(path_.stat().st_mode),
        original_bytes=path_.read_bytes(),
        tree=tree_,
        leading_nodes=leading_nodes_,
        trailing_nodes=trailing_nodes_,
        package_name=package_name_,
    )


def _Package_roles(
    package_names_: frozenset[str],
) -> dict[str, PackageRole]:
    """Infer the shim/interfaces pair without changing package identity."""
    roles_: dict[str, PackageRole] = {}
    for package_name_ in package_names_:
        if package_name_.endswith("_interfaces"):
            roles_[package_name_] = PackageRole.INTERFACES
        elif f"{package_name_}_interfaces" in package_names_:
            roles_[package_name_] = PackageRole.SHIM
        else:
            roles_[package_name_] = PackageRole.GENERIC
    return roles_


def _Require_element(
    root_: ET.Element,
    tag_: str,
    path_: Path,
) -> ET.Element:
    """Return a required direct child element."""
    element_ = root_.find(tag_)
    if element_ is None:
        raise ValueError(f"Missing <{tag_}> in {path_}")
    return element_


def _Set_website_url(
    root_: ET.Element,
    homepage_url_: str,
    path_: Path,
) -> None:
    """Update website URLs or insert one without touching other URL types."""
    website_elements_ = [
        url_
        for url_ in root_.findall("url")
        if url_.get("type") == "website"
    ]
    if website_elements_:
        for website_element_ in website_elements_:
            website_element_.text = homepage_url_
        return

    license_element_ = _Require_element(root_, "license", path_)
    children_ = list(root_)
    insert_index_ = children_.index(license_element_) + 1
    website_element_ = ET.Element("url", {"type": "website"})
    website_element_.text = homepage_url_
    website_element_.tail = license_element_.tail
    license_element_.tail = "\n  "
    root_.insert(insert_index_, website_element_)


def _Serialize_manifest(document_: ManifestDocument) -> bytes:
    """Serialize one manifest with its outer XML nodes restored."""
    root_text_ = ET.tostring(
        document_.tree.getroot(), encoding="unicode"
    )
    sections_ = [
        '<?xml version="1.0"?>',
        *document_.leading_nodes,
        root_text_,
        *document_.trailing_nodes,
    ]
    return ("\n".join(sections_).rstrip() + "\n").encode("utf-8")


def _Build_update(
    document_: ManifestDocument,
    metadata_: ProjectMetadata,
    role_: PackageRole,
) -> ManifestUpdate:
    """Prepare one manifest update without changing ROS-owned dependencies."""
    root_ = document_.tree.getroot()
    _Require_element(
        root_, "version", document_.path
    ).text = metadata_.version
    description_base_ = metadata_.description.rstrip().removesuffix(".")
    _Require_element(
        root_, "description", document_.path
    ).text = f"{description_base_}: {role_.value}"

    maintainer_element_ = _Require_element(
        root_, "maintainer", document_.path
    )
    maintainer_element_.text = metadata_.maintainer_name
    maintainer_element_.set("email", metadata_.maintainer_email)
    _Require_element(
        root_, "license", document_.path
    ).text = metadata_.license
    _Set_website_url(root_, metadata_.homepage_url, document_.path)

    return ManifestUpdate(
        path=document_.path,
        mode=document_.mode,
        original_bytes=document_.original_bytes,
        updated_bytes=_Serialize_manifest(document_),
    )


def _Write_update(update_: ManifestUpdate) -> bool:
    """Atomically replace a changed manifest while preserving its mode."""
    if update_.updated_bytes == update_.original_bytes:
        return False

    temporary_path_: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=f".{update_.path.name}.",
            dir=update_.path.parent,
            delete=False,
        ) as temporary_file_:
            temporary_file_.write(update_.updated_bytes)
            temporary_file_.flush()
            os.fsync(temporary_file_.fileno())
            temporary_path_ = Path(temporary_file_.name)

        os.chmod(temporary_path_, update_.mode)
        os.replace(temporary_path_, update_.path)
        temporary_path_ = None
    finally:
        if temporary_path_ is not None:
            temporary_path_.unlink(missing_ok=True)
    return True


def SynchronizePackageMetadata(
    project_root_: Path,
    ros2_directory_: Path,
    version_: str,
    *,
    check_only_: bool = False,
) -> int:
    """Synchronize immediate ROS package manifests from root CMake metadata.

    Args:
        project_root_: Repository root containing the owning CMake project.
        ros2_directory_: Directory containing immediate ROS package folders.
        version_: Strict X.Y.Z version expected from the root project.
        check_only_: Report drift without changing manifests.

    Returns:
        Number of changed manifests, or zero in a clean check.

    Raises:
        RuntimeError: If metadata-only CMake configuration fails.
        ValueError: If metadata or manifest structure is invalid, or check mode
            detects drift.
        xml.etree.ElementTree.ParseError: If a manifest is malformed.
    """
    metadata_ = _Configure_project_metadata(
        project_root_.resolve(), version_
    )
    manifest_paths_ = sorted(
        ros2_directory_.resolve().glob("*/package.xml")
    )
    if not manifest_paths_:
        raise ValueError(
            f"No immediate package.xml files found under {ros2_directory_}"
        )

    # Parse and prepare every replacement before writing any file so malformed
    # input cannot leave a partially synchronized overlay.
    documents_ = [_Read_manifest(path_) for path_ in manifest_paths_]
    package_names_ = frozenset(
        document_.package_name for document_ in documents_
    )
    if len(package_names_) != len(documents_):
        raise ValueError(
            "Duplicate ROS package names found in immediate manifests"
        )

    roles_ = _Package_roles(package_names_)
    updates_ = [
        _Build_update(
            document_, metadata_, roles_[document_.package_name]
        )
        for document_ in documents_
    ]
    changed_updates_ = [
        update_
        for update_ in updates_
        if update_.updated_bytes != update_.original_bytes
    ]

    if check_only_:
        if changed_updates_:
            changed_paths_ = ", ".join(
                str(update_.path) for update_ in changed_updates_
            )
            raise ValueError(
                "ROS 2 package metadata is out of date: "
                f"{changed_paths_}"
            )
        return 0

    return sum(_Write_update(update_) for update_ in changed_updates_)


def _Parse_arguments(
    arguments_: Sequence[str] | None,
) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser_ = argparse.ArgumentParser(description=__doc__)
    parser_.add_argument("--project-root", required=True, type=Path)
    parser_.add_argument("--ros2-dir", required=True, type=Path)
    parser_.add_argument("--version", required=True)
    parser_.add_argument(
        "--check",
        action="store_true",
        help="Fail when manifests differ without modifying them.",
    )
    return parser_.parse_args(arguments_)


def Main(arguments_: Sequence[str] | None = None) -> int:
    """Run metadata synchronization from the command line."""
    parsed_arguments_ = _Parse_arguments(arguments_)
    try:
        synchronized_count_ = SynchronizePackageMetadata(
            parsed_arguments_.project_root,
            parsed_arguments_.ros2_dir,
            parsed_arguments_.version,
            check_only_=parsed_arguments_.check,
        )
    except (
        ET.ParseError,
        OSError,
        RuntimeError,
        ValueError,
    ) as error_:
        print(f"[ERROR] {error_}", file=sys.stderr)
        return 1

    if parsed_arguments_.check:
        print("ROS 2 package metadata is synchronized.")
    else:
        print(
            "Synchronized "
            f"{synchronized_count_} ROS 2 package manifests."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(Main())
