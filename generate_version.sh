#!/usr/bin/env bash
# Generate VERSION file without building.
# Fallback chain: git tags --> existing VERSION file --> hardcoded default.

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

version_major=""
version_minor=""
version_patch=""
full_version=""
source=""

# 1. Try git
if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git_tag=$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || true)
    git_hash=$(git -C "$SCRIPT_DIR" rev-parse --short=7 HEAD 2>/dev/null || true)

    # Strip leading 'v' and match semver
    clean_tag="${git_tag#v}"
    if [[ "$clean_tag" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)? ]]; then
        version_major="${BASH_REMATCH[1]}"
        version_minor="${BASH_REMATCH[2]}"
        version_patch="${BASH_REMATCH[3]}"
        full_version="${version_major}.${version_minor}.${version_patch}+${git_hash}"
        source="git"
    fi
fi

# 2. Try existing VERSION file
if [[ -z "$source" && -f "$VERSION_FILE" ]]; then
    if grep -qP 'Project version: \d+\.\d+\.\d+' "$VERSION_FILE"; then
        line=$(grep -oP 'Project version: \K\d+\.\d+\.\d+' "$VERSION_FILE")
        IFS='.' read -r version_major version_minor version_patch <<< "$line"

        # Try to read full version line
        full_line=$(grep -oP 'Full version: \K.+' "$VERSION_FILE" 2>/dev/null || true)
        if [[ -n "$full_line" ]]; then
            full_version="$full_line"
        else
            full_version="${version_major}.${version_minor}.${version_patch}"
        fi
        source="VERSION file"
    else
        warn "VERSION file exists but could not be parsed"
    fi
fi

# 3. Fallback to hardcoded defaults
if [[ -z "$source" ]]; then
    version_major=$DEFAULT_MAJOR
    version_minor=$DEFAULT_MINOR
    version_patch=$DEFAULT_PATCH
    full_version="${version_major}.${version_minor}.${version_patch}"
    source="hardcoded default"
    warn "No git tags or VERSION file found. Using default version: ${full_version}"
fi

# Write VERSION file
version_string="${version_major}.${version_minor}.${version_patch}"
{
    echo "Project version: ${version_string}"
    echo "Full version: ${full_version}"
} > "$VERSION_FILE"

info "Version ${full_version} (from ${source}) written to ${VERSION_FILE}"
