#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${INSOMNIA_BUILD_DIR:-$PROJECT_ROOT/.build}"
OUTPUT_DIR="${INSOMNIA_OUTPUT_DIR:-$PROJECT_ROOT/dist}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$PROJECT_ROOT/$BUILD_DIR" ;; esac
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR" ;; esac
VERSION="$(cat "$PROJECT_ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
mkdir -p "$BUILD_DIR/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
COMPILER=(xcrun swiftc -swift-version 5 -O -module-cache-path "$BUILD_DIR/module-cache")
HOST_TARGET="$(uname -m)-apple-macosx13.0"
