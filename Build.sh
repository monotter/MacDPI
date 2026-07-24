#!/bin/bash
set -e

cd "$(dirname "$0")"

SINGBOX_TAG="v1.13.14"
BYEDPI_REF="ba53229"

BYEDPI_DIR=".build-byedpi"
SINGBOX_DIR=".build-singbox"
BUILD_LOG="$(mktemp)"

cleanup() { rm -rf "$BYEDPI_DIR" "$SINGBOX_DIR" "$BUILD_LOG"; }
trap cleanup EXIT

ask() {
    printf '%s [y/N] ' "$1"
    read -r reply </dev/tty 2>/dev/null || read -r reply
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

brew_bin() {
    if command -v brew >/dev/null 2>&1; then command -v brew; return 0; fi
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && { echo "$b"; return 0; }
    done
    return 1
}

ensure_compiler() {
    if command -v cc >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
        return 0
    fi
    echo "byedpi needs the Xcode Command Line Tools (C compiler)."
    ask "Install them now with 'xcode-select --install'?" || { echo "Cancelled."; exit 1; }
    xcode-select --install 2>/dev/null || true
    echo "Finish the installer window that opened, then press Enter to continue."
    read -r _ </dev/tty 2>/dev/null || read -r _
    command -v cc >/dev/null 2>&1 || { echo "Compiler still not found. Aborting."; exit 1; }
}

ensure_go() {
    command -v go >/dev/null 2>&1 && return 0
    local brew
    if brew=$(brew_bin); then
        eval "$("$brew" shellenv)" 2>/dev/null || true
        command -v go >/dev/null 2>&1 && return 0
    fi
    echo "sing-box needs Go."
    if ! brew=$(brew_bin); then
        ask "Homebrew is not installed. Install it now?" || { echo "Cancelled."; exit 1; }
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew=$(brew_bin) || { echo "Homebrew install failed. Aborting."; exit 1; }
        eval "$("$brew" shellenv)"
    fi
    ask "Install Go now with 'brew install go'?" || { echo "Cancelled."; exit 1; }
    "$brew" install go
    eval "$("$brew" shellenv)" 2>/dev/null || true
    command -v go >/dev/null 2>&1 || { echo "Go still not found. Aborting."; exit 1; }
}

ensure_compiler
ensure_go

echo "Building byedpi ($BYEDPI_REF)..."
rm -rf "$BYEDPI_DIR"
git clone --quiet https://github.com/hufrea/byedpi.git "$BYEDPI_DIR"
git -c advice.detachedHead=false -C "$BYEDPI_DIR" checkout --quiet "$BYEDPI_REF"
if ! make -C "$BYEDPI_DIR" >"$BUILD_LOG" 2>&1; then cat "$BUILD_LOG"; exit 1; fi
cp "$BYEDPI_DIR/ciadpi" ./ciadpi

echo "Building sing-box ($SINGBOX_TAG)..."
rm -rf "$SINGBOX_DIR"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$SINGBOX_TAG" \
    https://github.com/SagerNet/sing-box.git "$SINGBOX_DIR"
export GOTOOLCHAIN=local
if ! CGO_ENABLED=1 go build -C "$SINGBOX_DIR" -trimpath \
    -tags "$(cat "$SINGBOX_DIR/release/DEFAULT_BUILD_TAGS")" \
    -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${SINGBOX_TAG#v}' $(cat "$SINGBOX_DIR/release/LDFLAGS") -s -w -buildid=" \
    -o ../sing-box ./cmd/sing-box >"$BUILD_LOG" 2>&1; then cat "$BUILD_LOG"; exit 1; fi

echo "Done."
./ciadpi --version
./sing-box version | head -1
