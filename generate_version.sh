#!/usr/bin/env bash
# Generate VERSION file without building.
# Fallback chain: git tags --> existing VERSION file --> hardcoded default.
# ROS2_PROJECT_METADATA_SYNC=1

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/VERSION"

# Default version (last resort)
DEFAULT_MAJOR=0
DEFAULT_MINOR=0
DEFAULT_PATCH=0

# Helpers (matching build_lib.sh style)
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*" >&2; }
die() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage:
  ./generate_version.sh [options]

Options:
  --sync-ros2     Explicitly synchronize ros2/*/package.xml project metadata.
  --no-sync-ros2  Write VERSION without synchronizing ROS 2 package metadata.
  -h, --help      Show this help.

By default, ROS 2 package metadata is synchronized when the supported overlay
helper is present.
EOF
}

# Automatic mode keeps the standalone generator safe in non-ROS repositories,
# while enabling metadata synchronization when the complete helper is present.
sync_ros2=auto

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --sync-ros2)
                sync_ros2=true
                shift
                ;;
            --no-sync-ros2)
                sync_ros2=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

read_version_field() {
    local version_file_="$1"
    local field_name_="$2"
    [[ -f "$version_file_" ]] || return 1
    awk -F': ' -v key="${field_name_}" 'index($0, key ": ") == 1 { sub(/^[^:]+: /, "", $0); print; exit }' "$version_file_"
}
compose_full_version() {
    local version_core_="$1"
    local version_prerelease_="$2"
    local version_metadata_="$3"
    local full_version_="$version_core_"

    if [[ -n "$version_prerelease_" ]]; then
        full_version_+="-${version_prerelease_}"
    fi
    if [[ -n "$version_metadata_" ]]; then
        full_version_+="+${version_metadata_}"
    fi

    printf '%s\n' "$full_version_"
}
set_version_components() {
    version_major="$1"
    version_minor="$2"
    version_patch="$3"
    version_prerelease="$4"
    version_metadata="$5"
    version_core="${version_major}.${version_minor}.${version_patch}"
    full_version="$(compose_full_version "$version_core" "$version_prerelease" "$version_metadata")"
}

parse_args "$@"

version_major=""
version_minor=""
version_patch=""
version_core=""
version_prerelease=""
version_metadata=""
full_version=""
source=""

# 1. Try git
if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git_describe=$(git -C "$SCRIPT_DIR" describe --tags --long --dirty --always 2>/dev/null || true)

    # Strip leading 'v' and match semver
    clean_tag="${git_describe#v}"
    if [[ "$clean_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?-([0-9]+)-g([0-9a-f]+)(-dirty)?$ ]]; then
        version_prerelease_local="${BASH_REMATCH[5]}"
        version_distance_local="${BASH_REMATCH[6]}"
        version_hash_local="g${BASH_REMATCH[7]}"
        version_dirty_local="${BASH_REMATCH[8]}"
        version_metadata_parts=()

        if [[ "$version_distance_local" != "0" ]]; then
            version_metadata_parts+=("$version_distance_local")
        fi
        if [[ "$version_distance_local" != "0" || -n "$version_dirty_local" ]]; then
            version_metadata_parts+=("$version_hash_local")
        fi
        if [[ -n "$version_dirty_local" ]]; then
            version_metadata_parts+=("dirty")
        fi

        version_metadata_local=""
        if (( ${#version_metadata_parts[@]} > 0 )); then
            version_metadata_local="$(printf '%s.' "${version_metadata_parts[@]}")"
            version_metadata_local="${version_metadata_local%.}"
        fi

        set_version_components \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" \
            "$version_prerelease_local" \
            "$version_metadata_local"
        source="git describe"
    elif [[ "$clean_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?$ ]]; then
        set_version_components \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[5]}" \
            ""
        source="git tag"
    fi
fi

# 2. Try existing VERSION file
if [[ -z "$source" && -f "$VERSION_FILE" ]]; then
    version_core_local="$(read_version_field "$VERSION_FILE" "Project version core" || true)"
    if [[ -z "$version_core_local" ]]; then
        version_core_local="$(read_version_field "$VERSION_FILE" "Project version" || true)"
    fi

    if [[ "$version_core_local" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        version_prerelease_local="$(read_version_field "$VERSION_FILE" "Project version prerelease" || true)"
        version_metadata_local="$(read_version_field "$VERSION_FILE" "Project version metadata" || true)"

        if [[ "$version_prerelease_local" == "<none>" ]]; then
            version_prerelease_local=""
        fi
        if [[ "$version_metadata_local" == "<none>" ]]; then
            version_metadata_local=""
        fi

        set_version_components \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" \
            "$version_prerelease_local" \
            "$version_metadata_local"

        full_version_local="$(read_version_field "$VERSION_FILE" "Full version" || true)"
        if [[ -n "$full_version_local" ]]; then
            full_version="$full_version_local"
        fi
        source="VERSION file"
    else
        warn "VERSION file exists but could not be parsed"
    fi
fi

# 3. Fallback to hardcoded defaults
if [[ -z "$source" ]]; then
    set_version_components "$DEFAULT_MAJOR" "$DEFAULT_MINOR" "$DEFAULT_PATCH" "" ""
    source="hardcoded default"
    warn "No git tags or VERSION file found. Using default version: ${full_version}"
fi

# Write VERSION file
{
    echo "Project version: ${version_core}"
    echo "Project version core: ${version_core}"
    if [[ -n "$version_prerelease" ]]; then
        echo "Project version prerelease: ${version_prerelease}"
    else
        echo "Project version prerelease: <none>"
    fi
    if [[ -n "$version_metadata" ]]; then
        echo "Project version metadata: ${version_metadata}"
    else
        echo "Project version metadata: <none>"
    fi
    echo "Full version: ${full_version}"
} > "$VERSION_FILE"

info "Version ${full_version} (from ${source}) written to ${VERSION_FILE}"

sync_ros2_package_metadata() {
    if [[ "${sync_ros2}" == false ]]; then
        return
    fi

    local ros2_dir_="${SCRIPT_DIR}/ros2"
    if [[ ! -d "${ros2_dir_}" ]]; then
        if [[ "${sync_ros2}" == true ]]; then
            info "ROS 2 overlay not present; skipping package metadata sync"
        fi
        return
    fi

    if [[ "${source}" == "hardcoded default" ]]; then
        warn "Skipping ROS 2 package metadata sync because the version came from the hardcoded default"
        return
    fi

    if [[ ! "${version_core}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "Skipping ROS 2 package metadata sync because '${version_core}' is not strict X.Y.Z"
        return
    fi

    local metadata_helper_="${ros2_dir_}/tools/sync_package_metadata.py"
    if [[ ! -f "${metadata_helper_}" ]]; then
        if [[ "${sync_ros2}" == true ]]; then
            warn "ROS 2 package metadata helper is missing; skipping metadata sync"
        fi
        return
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 is unavailable; skipping ROS 2 package metadata sync"
        return
    fi

    python3 "${metadata_helper_}" \
        --project-root "${SCRIPT_DIR}" \
        --ros2-dir "${ros2_dir_}" \
        --version "${version_core}"
}

sync_ros2_package_metadata
