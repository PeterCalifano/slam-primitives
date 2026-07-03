"""Setup helpers for the source Python package."""

from __future__ import annotations

from importlib import util
from pathlib import Path
import shutil

from setuptools import Distribution, setup
from setuptools.command.build_py import build_py


def _discover_package_name() -> str:
    project_root_ = Path(__file__).resolve().parent
    for candidate_ in sorted(project_root_.iterdir()):
        if candidate_.is_dir() and (candidate_ / "__init__.py").is_file():
            return candidate_.name
    raise RuntimeError("Could not discover the Python package directory next to setup.py.")


PACKAGE_NAME = _discover_package_name()


class BinaryDistribution(Distribution):
    """Mark wheel as platform-specific when a linked wrapper is present."""

    def has_ext_modules(self) -> bool:
        return True


class LinkedWrapperBuildPy(build_py):
    """Copy the latest linked wrapper build into the installable package, if present."""

    def run(self) -> None:
        super().run()

        package_dir_ = Path(__file__).resolve().parent / PACKAGE_NAME
        wrapper_link_file_ = package_dir_ / "_wrapper_build.py"
        if not wrapper_link_file_.is_file():
            return

        spec_ = util.spec_from_file_location(f"{PACKAGE_NAME}._wrapper_build", wrapper_link_file_)
        if spec_ is None or spec_.loader is None:
            raise RuntimeError(f"Could not load wrapper link metadata from '{wrapper_link_file_}'.")

        wrapper_link_module_ = util.module_from_spec(spec_)
        spec_.loader.exec_module(wrapper_link_module_)

        wrapper_module_path_ = Path(wrapper_link_module_.WRAPPER_MODULE_PATH)
        if not wrapper_module_path_.is_file():
            raise RuntimeError(
                "The linked wrapper build is stale or missing. "
                f"Expected '{wrapper_module_path_}'. Rebuild with Python wrapping before installing."
            )

        destination_dir_ = Path(self.build_lib) / PACKAGE_NAME
        destination_dir_.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wrapper_module_path_, destination_dir_ / wrapper_module_path_.name)


setup(
    cmdclass={"build_py": LinkedWrapperBuildPy},
    distclass=BinaryDistribution,
    zip_safe=False,
)
