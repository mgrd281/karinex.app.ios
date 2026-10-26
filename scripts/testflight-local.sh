#!/usr/bin/env bash
#
# Builds the signed App Store binary on this Mac and uploads it to TestFlight, the same
# `fastlane beta` lane the TestFlight workflow runs on GitHub, without waiting for a runner.
#
# Usage: scripts/testflight-local.sh
#
# Needs a Mac with Xcode and Homebrew. It asks for the App Store Connect API key (key ID,
# issuer ID, the .p8 file) and the Apple Developer team ID. The key stays on this Mac: it is
# read from the file into the environment of the build and never written anywhere else.
# The key ID, issuer ID and team ID are remembered in ~/.config/karinex/testflight.env
# (readable by you only); the .p8 file is never copied.
#
# Environment (each one skips its question): ASC_KEY_ID, ASC_ISSUER_ID, KX_APPLE_TEAM_ID,
# ASC_KEY_PATH.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
settings_dir="$HOME/.config/karinex"
settings_file="$settings_dir/testflight.env"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this script needs a Mac."
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is not installed or not selected (xcode-select)."
command -v brew >/dev/null 2>&1 || fail "Homebrew is required (https://brew.sh)."

# MARK: Tools

brew list --formula ruby >/dev/null 2>&1 || brew install ruby
# Homebrew's Ruby, because the Ruby of macOS is too old for fastlane.
export PATH="$(brew --prefix ruby)/bin:$PATH"

cd "$repo_root"
# An earlier run leaves its build number (agvtool) and the resolved packages in the generated
# project; the lane needs the committed project, so start from it again.
git checkout -- KARINEX.xcodeproj
# The pinned XcodeGen of CI: another version writes a different project file, and the lane
# stops when KARINEX.xcodeproj differs from what project.yml generates.
tools_path="$(scripts/install-tools.sh --dir "$HOME/.cache/karinex-tools" xcodegen | tail -n 1)"
export PATH="$tools_path:$PATH"
bundle config set --local path vendor/bundle >/dev/null
bundle install --quiet

# MARK: Settings

if [[ -f "$settings_file" ]]; then
    # shellcheck disable=SC1090
    source "$settings_file"
fi

ask() {
    local name="$1" prompt="$2" value="${!1:-}"
    if [[ -z "$value" ]]; then
        read -r -p "$prompt: " value
    fi
    [[ -n "$value" ]] || fail "$name is required."
    printf -v "$name" '%s' "$value"
}

ask ASC_KEY_ID "App Store Connect key ID (10 characters)"
ask ASC_ISSUER_ID "App Store Connect issuer ID"
ask KX_APPLE_TEAM_ID "Apple Developer team ID (10 characters)"
ask ASC_KEY_PATH "Path of the AuthKey .p8 file (drag it into this window)"

# Drag and drop adds quotes or backslashes for spaces.
ASC_KEY_PATH="${ASC_KEY_PATH//\\/}"
ASC_KEY_PATH="${ASC_KEY_PATH%\'}"
ASC_KEY_PATH="${ASC_KEY_PATH#\'}"
[[ -f "$ASC_KEY_PATH" ]] || fail "no file at $ASC_KEY_PATH."

mkdir -p "$settings_dir"
(
    umask 077
    {
        printf 'ASC_KEY_ID=%q\n' "$ASC_KEY_ID"
        printf 'ASC_ISSUER_ID=%q\n' "$ASC_ISSUER_ID"
        printf 'KX_APPLE_TEAM_ID=%q\n' "$KX_APPLE_TEAM_ID"
    } >"$settings_file"
)

# MARK: Build and upload

export ASC_KEY_ID ASC_ISSUER_ID KX_APPLE_TEAM_ID
ASC_KEY_CONTENT="$(cat "$ASC_KEY_PATH")"
export ASC_KEY_CONTENT
export FASTLANE_SKIP_UPDATE_CHECK=1
export FASTLANE_HIDE_CHANGELOG=1
export FASTLANE_OPT_OUT_USAGE=1
export FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT=120
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

bundle exec fastlane beta

echo
echo "Done. The build appears in TestFlight after Apple has processed it (usually 10 to 30 minutes)."
