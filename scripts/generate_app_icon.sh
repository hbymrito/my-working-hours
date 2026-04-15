#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE_DIR="$ROOT_DIR/.build/ModuleCache.noindex"

mkdir -p "$MODULE_CACHE_DIR"

xcrun swift \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/scripts/generate_app_icon.swift"
