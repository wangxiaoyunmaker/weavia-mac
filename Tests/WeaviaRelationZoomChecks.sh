#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d /tmp/weavia-relation-zoom.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
swiftc -parse-as-library -module-cache-path "$TMP/ModuleCache" Tests/WeaviaRelationZoomChecks.swift -o "$TMP/check"
"$TMP/check" "$ROOT/Sources/MouseCompanion/CuppaCanvas"
