"""Public Python package entrypoint for slam_primitives.

The pure Python package is always importable. When the optional native wrapper
has been built, the generated extension module is imported and its public names
are re-exported here. Consumers can check ``HAS_WRAPPER`` before using the
native classes.
"""

from __future__ import annotations

from importlib import import_module, util
from pathlib import Path
import os
import sys
from types import ModuleType

HAS_WRAPPER = False
WRAPPER_IMPORT_ERROR: ImportError | None = None
_DLL_DIRECTORY_HANDLES: list[object] = []

# Python 3.8+ requires explicit DLL search directories on Windows. Retain each
# handle for the package lifetime so delay-loaded dependencies remain visible.
if os.name == "nt":
    _DLL_DIRECTORY_HANDLES.append(
        os.add_dll_directory(str(Path(__file__).resolve().parent))
    )


def _export_wrapper_module(module_: ModuleType) -> None:
    """Re-export generated wrapper symbols from the package namespace."""
    public_names_ = getattr(module_, "__all__", None)
    if public_names_ is None:
        public_names_ = [name_ for name_ in dir(module_) if not name_.startswith("_")]
    for name_ in public_names_:
        globals()[name_] = getattr(module_, name_)


def _import_build_linked_wrapper() -> ModuleType:
    """Load a wrapper extension from the active CMake build tree.

    CMake writes ``_wrapper_build.py`` into its staged build package when the
    wrapper target is built. This keeps generated metadata out of the source
    checkout while allowing direct imports without rebuilding a wheel.

    Returns:
        Loaded native wrapper module.

    Raises:
        ImportError: If metadata or its referenced native module is unavailable.
    """
    try:
        from . import _wrapper_build
    except ImportError as exc:
        raise ImportError("No build-linked wrapper metadata is available.") from exc

    module_path_ = Path(_wrapper_build.WRAPPER_MODULE_PATH)
    if not module_path_.is_file():
        raise ImportError(f"Build-linked wrapper module was not found at '{module_path_}'.")

    if os.name == "nt":
        runtime_paths_ = getattr(
            _wrapper_build,
            "WRAPPER_RUNTIME_LIBRARY_PATHS",
            [],
        )
        for runtime_path_ in runtime_paths_:
            dll_path_ = Path(runtime_path_).parent
            if dll_path_.is_dir():
                _DLL_DIRECTORY_HANDLES.append(
                    os.add_dll_directory(str(dll_path_))
                )

    package_name_ = __name__.split(".")[-1]
    module_name_ = f"{__name__}.{package_name_}"
    # Load the extension with the installed-package module name so pybind11
    # type registration behaves the same for build-tree and installed imports.
    spec_ = util.spec_from_file_location(module_name_, module_path_)
    if spec_ is None or spec_.loader is None:
        raise ImportError(f"Could not load build-linked wrapper spec from '{module_path_}'.")

    module_ = util.module_from_spec(spec_)
    sys.modules[module_name_] = module_
    spec_.loader.exec_module(module_)
    return module_


package_name_ = __name__.split(".")[-1]
wrapper_module_: ModuleType | None = None

try:
    wrapper_module_ = import_module(f".{package_name_}", __name__)
except ImportError:
    try:
        wrapper_module_ = _import_build_linked_wrapper()
    except ImportError as exc:
        WRAPPER_IMPORT_ERROR = exc

if wrapper_module_ is not None:
    _export_wrapper_module(wrapper_module_)
    HAS_WRAPPER = True
