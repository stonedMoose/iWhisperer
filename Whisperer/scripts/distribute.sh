#!/bin/bash
# Distribute MacWhisperer via Fastlane
# Usage:
#   bash scripts/distribute.sh                  # build + DMG (quick, no notarize)
#   bash scripts/distribute.sh notarize         # build + notarize + DMG
#   bash scripts/distribute.sh release          # full release (build + notarize + DMG + GitHub draft)
#   bash scripts/distribute.sh release --live   # full release (not draft)
#   bash scripts/distribute.sh appstore         # build + sign + .pkg for App Store
#   bash scripts/distribute.sh appstore --upload # also upload to App Store Connect
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LANE="${1:-distribute}"
shift 2>/dev/null || true

case "$LANE" in
  build)
    fastlane build
    ;;
  notarize)
    fastlane build
    fastlane notarize_app "$@"
    ;;
  dmg)
    fastlane dmg
    ;;
  distribute)
    fastlane distribute
    ;;
  release)
    EXTRA_ARGS="github:true"
    if [[ "${1:-}" == "--live" ]]; then
      EXTRA_ARGS="$EXTRA_ARGS draft:false"
      shift
    fi
    fastlane release $EXTRA_ARGS "$@"
    ;;
  appstore)
    if [[ "${1:-}" == "--upload" ]]; then
      fastlane appstore upload:true
    else
      fastlane appstore
    fi
    ;;
  *)
    echo "Unknown lane: $LANE"
    echo "Usage: distribute.sh [build|notarize|dmg|distribute|release [--live]|appstore [--upload]]"
    exit 1
    ;;
esac
