#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d /tmp/weavia-smart-tags.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
node Tests/WeaviaSmartTagsTests.js
# Compile the pure request contract directly from production source without starting NSApplication or a network client.
python3 - "$TMP/CanvasSmartTagInput.swift" <<'PY'
from pathlib import Path
import sys
source=Path('Sources/MouseCompanion/CanvasSmartTags.swift').read_text().split('final class CanvasSmartTagCoordinator')[0]
Path(sys.argv[1]).write_text(source)
PY
swiftc "$TMP/CanvasSmartTagInput.swift" Tests/WeaviaSmartTagInputChecks.swift -o "$TMP/check"
"$TMP/check"
node --check Sources/MouseCompanion/CuppaCanvas/smart-tags-ui.js
