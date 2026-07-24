"""Test target-specific ROS 2 manifest metadata synchronization.

The fixtures are temporary copies so synchronization tests never modify the
repository's tracked or untracked package manifests.
"""

from __future__ import annotations

import stat
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "ros2" / "tools"))

from sync_package_metadata import SynchronizePackageMetadata  # noqa: E402


@pytest.fixture(scope="session")
def project_version(
    tmp_path_factory: pytest.TempPathFactory,
) -> str:
    """Resolve the current strict project version from metadata-only CMake."""
    build_directory_ = tmp_path_factory.mktemp("project_metadata")
    subprocess.run(
        [
            "cmake",
            "-S",
            str(PROJECT_ROOT),
            "-B",
            str(build_directory_),
            "-DPROJECT_METADATA_ONLY=ON",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    cache_text_ = (build_directory_ / "CMakeCache.txt").read_text(
        encoding="utf-8"
    )
    prefix_ = "CMAKE_PROJECT_VERSION:STATIC="
    for line_ in cache_text_.splitlines():
        if line_.startswith(prefix_):
            return line_.removeprefix(prefix_)
    raise AssertionError("Metadata-only CMake did not export a project version")


def _Write_manifest(
    path_: Path,
    package_name_: str,
    description_: str = "stale description",
) -> None:
    """Write a minimal format-3 manifest with preserved target dependencies."""
    path_.parent.mkdir(parents=True, exist_ok=True)
    path_.write_text(
        f"""<?xml version="1.0"?>
<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
<package format="3">
  <name>{package_name_}</name>
  <version>0.0.1</version>
  <description>{description_}</description>
  <maintainer email="old@example.test">Old Maintainer</maintainer>
  <license>BSD-3-Clause</license>
  <depend>std_msgs</depend>
</package>
""",
        encoding="utf-8",
    )


def _Read_manifest(path_: Path) -> ET.Element:
    """Parse one fixture manifest root."""
    return ET.parse(path_).getroot()


def test_synchronizer_updates_two_package_overlay_and_preserves_contracts(
    tmp_path: Path,
    project_version: str,
) -> None:
    """Root metadata should update identity fields without changing ROS seams."""
    ros2_dir_ = tmp_path / "ros2"
    shim_manifest_ = ros2_dir_ / "slam_primitives" / "package.xml"
    interfaces_manifest_ = (
        ros2_dir_ / "slam_primitives_interfaces" / "package.xml"
    )
    _Write_manifest(shim_manifest_, "slam_primitives")
    _Write_manifest(interfaces_manifest_, "slam_primitives_interfaces")
    interfaces_manifest_.chmod(0o640)

    changed_count_ = SynchronizePackageMetadata(
        PROJECT_ROOT, ros2_dir_, project_version
    )

    assert changed_count_ == 2
    shim_root_ = _Read_manifest(shim_manifest_)
    interfaces_root_ = _Read_manifest(interfaces_manifest_)

    assert shim_root_.findtext("version") == project_version
    assert interfaces_root_.findtext("version") == project_version
    assert shim_root_.findtext("description", "").endswith(
        "ROS 2 colcon shim package."
    )
    assert interfaces_root_.findtext("description", "").endswith(
        "ROS 2 message interfaces."
    )
    assert interfaces_root_.findtext("depend") == "std_msgs"
    assert interfaces_root_.findtext("maintainer") == "Pietro Califano"
    assert (
        interfaces_root_.find("maintainer").get("email")
        == "petercalifano.gs@gmail.com"
    )
    assert interfaces_root_.findtext("license") == "MIT"
    assert interfaces_root_.find("url[@type='website']") is not None
    assert "<?xml-model " in interfaces_manifest_.read_text(encoding="utf-8")
    assert stat.S_IMODE(interfaces_manifest_.stat().st_mode) == 0o640


def test_synchronizer_is_idempotent_and_check_mode_detects_drift(
    tmp_path: Path,
    project_version: str,
) -> None:
    """Repeated synchronization should not rewrite stable manifests."""
    ros2_dir_ = tmp_path / "ros2"
    _Write_manifest(
        ros2_dir_ / "slam_primitives" / "package.xml",
        "slam_primitives",
    )
    _Write_manifest(
        ros2_dir_ / "slam_primitives_interfaces" / "package.xml",
        "slam_primitives_interfaces",
    )

    with pytest.raises(ValueError, match="out of date"):
        SynchronizePackageMetadata(
            PROJECT_ROOT, ros2_dir_, project_version, check_only_=True
        )

    assert SynchronizePackageMetadata(
        PROJECT_ROOT, ros2_dir_, project_version
    ) == 2
    mtimes_ = {
        path_: path_.stat().st_mtime_ns
        for path_ in ros2_dir_.glob("*/package.xml")
    }

    assert SynchronizePackageMetadata(
        PROJECT_ROOT, ros2_dir_, project_version
    ) == 0
    assert SynchronizePackageMetadata(
        PROJECT_ROOT, ros2_dir_, project_version, check_only_=True
    ) == 0
    assert {
        path_: path_.stat().st_mtime_ns
        for path_ in ros2_dir_.glob("*/package.xml")
    } == mtimes_


def test_synchronizer_rejects_invalid_version(tmp_path: Path) -> None:
    """ROS manifests require a strict three-component numeric version."""
    ros2_dir_ = tmp_path / "ros2"
    _Write_manifest(
        ros2_dir_ / "slam_primitives_interfaces" / "package.xml",
        "slam_primitives_interfaces",
    )

    with pytest.raises(ValueError, match="strict X.Y.Z"):
        SynchronizePackageMetadata(PROJECT_ROOT, ros2_dir_, "0.2.0-dev")


@pytest.mark.parametrize(
    "missing_tag",
    ["version", "description", "maintainer", "license"],
)
def test_synchronizer_rejects_missing_required_metadata(
    tmp_path: Path,
    project_version: str,
    missing_tag: str,
) -> None:
    """Required manifest identity fields must be present before replacement."""
    ros2_dir_ = tmp_path / "ros2"
    manifest_ = ros2_dir_ / "slam_primitives" / "package.xml"
    _Write_manifest(manifest_, "slam_primitives")

    tree_ = ET.parse(manifest_)
    root_ = tree_.getroot()
    missing_element_ = root_.find(missing_tag)
    assert missing_element_ is not None
    root_.remove(missing_element_)
    tree_.write(manifest_, encoding="unicode")

    with pytest.raises(ValueError, match=rf"Missing <{missing_tag}>"):
        SynchronizePackageMetadata(
            PROJECT_ROOT, ros2_dir_, project_version
        )


def test_synchronizer_rejects_duplicate_package_names(
    tmp_path: Path,
    project_version: str,
) -> None:
    """Two manifest paths must not claim the same ROS package identity."""
    ros2_dir_ = tmp_path / "ros2"
    _Write_manifest(ros2_dir_ / "first" / "package.xml", "duplicate")
    _Write_manifest(ros2_dir_ / "second" / "package.xml", "duplicate")

    with pytest.raises(ValueError, match="Duplicate ROS package names"):
        SynchronizePackageMetadata(
            PROJECT_ROOT, ros2_dir_, project_version
        )


def test_synchronizer_rejects_malformed_xml(
    tmp_path: Path,
    project_version: str,
) -> None:
    """Malformed manifests must fail before any file is replaced."""
    ros2_dir_ = tmp_path / "ros2"
    valid_manifest_ = ros2_dir_ / "slam_primitives" / "package.xml"
    malformed_manifest_ = (
        ros2_dir_ / "slam_primitives_interfaces" / "package.xml"
    )
    _Write_manifest(valid_manifest_, "slam_primitives")
    malformed_manifest_.parent.mkdir(parents=True)
    malformed_manifest_.write_text("<package>", encoding="utf-8")
    original_valid_bytes_ = valid_manifest_.read_bytes()

    with pytest.raises(ET.ParseError):
        SynchronizePackageMetadata(
            PROJECT_ROOT, ros2_dir_, project_version
        )

    assert valid_manifest_.read_bytes() == original_valid_bytes_
