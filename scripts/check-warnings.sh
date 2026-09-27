#!/usr/bin/env bash
#
# Fails when a build log contains compiler warnings for this repository's own sources.
#
# Usage: scripts/check-warnings.sh <xcodebuild-or-swift-build-log>
#
# A warning counts when its line contains "warning:" and a path inside App/, Packages/ or
# Tools/ of this repository (absolute, or relative to the repository root). Warnings from
# SwiftPM checkouts, SourcePackages, .spm, .build and DerivedData are ignored, as are
# warnings without a repository path (linker notes, Xcode destination notices). Every
# offending line is printed once; under GitHub Actions each also becomes an annotation.
#
# Exit status: 0 without repository warnings, 1 with warnings, 2 on usage errors.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <build-log>" >&2
    exit 2
fi

log_file="$1"
if [[ ! -f "$log_file" ]]; then
    echo "error: build log '$log_file' not found" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)"
# The physical path too, in case the checkout is reached through a symlink (/tmp on macOS).
physical_root="$(cd "$repo_root" && pwd -P)"

# awk (not a grep pipeline) so that a failing filter can never be mistaken for "no match".
matches="$(
    awk -v root="$repo_root" -v physical="$physical_root" '
        function mentions(base) {
            return index($0, base "/App/") || index($0, base "/Packages/") || index($0, base "/Tools/")
        }
        index($0, "warning:") == 0 { next }
        $0 ~ /\/(\.build|\.swiftpm|\.spm|SourcePackages|checkouts|DerivedData)\// { next }
        {
            ours = mentions(root) || mentions(physical)
            if (!ours && $0 ~ /(^|[[:space:]"'\''(=])(App|Packages|Tools)\//) { ours = 1 }
            if (ours && !seen[$0]++) { print }
        }
    ' "$log_file"
)"

if [[ -z "$matches" ]]; then
    echo "check-warnings: no warnings in App/, Packages/ or Tools/ sources."
    exit 0
fi

count="$(printf '%s\n' "$matches" | wc -l | tr -d '[:space:]')"
echo "check-warnings: ${count} warning(s) in repository sources (zero warnings are allowed):"
printf '%s\n' "$matches"

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    # "<path>:<line>:<column>: warning: <message>" becomes a GitHub annotation.
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([^:[:space:]][^:]*):([0-9]+):([0-9]+):[[:space:]]*warning:[[:space:]]*(.*)$ ]]; then
            file="${BASH_REMATCH[1]#"$repo_root"/}"
            file="${file#"$physical_root"/}"
            echo "::error file=${file},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[4]}"
        fi
    done <<<"$matches"
fi

exit 1
