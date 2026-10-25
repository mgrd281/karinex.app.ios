#!/usr/bin/env bash
#
# Installs the pinned versions of SwiftFormat, SwiftLint and XcodeGen from their GitHub
# releases into a local directory, verifying every download against a SHA-256 checksum.
# CI uses this script, so developers get byte-identical formatter and linter behaviour.
#
# Usage: scripts/install-tools.sh [--dir <directory>] [swiftformat] [swiftlint] [xcodegen]
#
#   --dir   installation directory (default: build/tools); binaries land in <dir>/bin
#   tools   which tools to install (default: every tool available for this platform;
#           XcodeGen ships macOS binaries only)
#
# The last line of output is the absolute bin directory, e.g. for `>> "$GITHUB_PATH"`.
#
# Note: on Linux, SwiftLint loads SourceKit from the Swift toolchain found on PATH (or
# LINUX_SOURCEKIT_LIB_PATH); custom rules are skipped without it.

set -euo pipefail

SWIFTFORMAT_VERSION="0.63.0"
SWIFTLINT_VERSION="0.65.1"
XCODEGEN_VERSION="2.46.0"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
install_dir="$repo_root/build/tools"
requested=()

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dir)
        [[ $# -ge 2 ]] || {
            echo "error: --dir needs a value" >&2
            exit 2
        }
        install_dir="$2"
        shift 2
        ;;
    swiftformat | swiftlint | xcodegen)
        requested+=("$1")
        shift
        ;;
    -h | --help)
        sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "error: unknown argument '$1'" >&2
        exit 2
        ;;
    esac
done

os="$(uname -s)"
arch="$(uname -m)"

# Prints "<url> <sha256> <binary-inside-zip>" for a tool on this platform, or nothing.
release_asset() {
    local tool="$1"
    case "$tool/$os/$arch" in
    swiftformat/Darwin/*)
        echo "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" \
            "28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f" "swiftformat"
        ;;
    swiftformat/Linux/x86_64)
        echo "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat_linux.zip" \
            "b4a3cbb8c852a0baaf9adf853e221ff1dabf921a3d8957a602e0bda3af8470f1" "swiftformat_linux"
        ;;
    swiftformat/Linux/aarch64 | swiftformat/Linux/arm64)
        echo "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat_linux_aarch64.zip" \
            "b0335af32e2c5944a17b3e6d916ff4552eb757ed88f68b80fd19415824850717" "swiftformat_linux_aarch64"
        ;;
    swiftlint/Darwin/*)
        echo "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
            "c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0" "swiftlint"
        ;;
    swiftlint/Linux/x86_64)
        echo "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/swiftlint_linux_amd64.zip" \
            "caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d" "swiftlint"
        ;;
    swiftlint/Linux/aarch64 | swiftlint/Linux/arm64)
        echo "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/swiftlint_linux_arm64.zip" \
            "9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8" "swiftlint"
        ;;
    xcodegen/Darwin/*)
        echo "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
            "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806" "xcodegen/bin/xcodegen"
        ;;
    esac
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

install_tool() {
    local tool="$1" asset url checksum member actual work
    asset="$(release_asset "$tool")"
    if [[ -z "$asset" ]]; then
        echo "error: no $tool release binary for $os/$arch" >&2
        return 1
    fi
    read -r url checksum member <<<"$asset"

    work="$(mktemp -d "${TMPDIR:-/tmp}/kx-tools.XXXXXX")"
    echo "Downloading $tool from $url" >&2
    curl --fail --silent --show-error --location --retry 3 --output "$work/asset.zip" "$url"
    actual="$(sha256_of "$work/asset.zip")"
    if [[ "$actual" != "$checksum" ]]; then
        echo "error: checksum mismatch for $tool: expected $checksum, got $actual" >&2
        rm -rf "$work"
        return 1
    fi
    unzip -q -o "$work/asset.zip" -d "$work/unpacked"
    mkdir -p "$install_dir/bin"
    if [[ "$tool" == "xcodegen" ]]; then
        # XcodeGen finds its SettingPresets relative to the executable, so keep the release
        # layout and put a small launcher on the bin directory.
        rm -rf "$install_dir/libexec/xcodegen"
        mkdir -p "$install_dir/libexec"
        mv "$work/unpacked/xcodegen" "$install_dir/libexec/xcodegen"
        printf '#!/bin/sh\nexec "%s" "$@"\n' "$install_dir/libexec/xcodegen/bin/xcodegen" >"$install_dir/bin/xcodegen"
        chmod 0755 "$install_dir/bin/xcodegen" "$install_dir/libexec/xcodegen/bin/xcodegen"
    else
        install -m 0755 "$work/unpacked/$member" "$install_dir/bin/$tool"
    fi
    rm -rf "$work"
    echo "Installed $tool: $("$install_dir/bin/$tool" --version 2>/dev/null || "$install_dir/bin/$tool" version)" >&2
}

if [[ ${#requested[@]} -eq 0 ]]; then
    requested=(swiftformat swiftlint)
    if [[ "$os" == "Darwin" ]]; then
        requested+=(xcodegen)
    fi
fi

mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd -P)"
for tool in "${requested[@]}"; do
    install_tool "$tool"
done
echo "$install_dir/bin"
