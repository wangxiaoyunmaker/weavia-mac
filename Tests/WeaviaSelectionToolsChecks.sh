#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD";TMP=$(mktemp -d /tmp/weavia-selection-tools.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Fixture.bundle" "$TMP/data"
cp -R "${CANVAS_RESOURCES:-Sources/MouseCompanion/CuppaCanvas}" "$TMP/Fixture.bundle/CuppaCanvas"
printf 'import Foundation\nextension Bundle { static var module: Bundle { Bundle(path: "%s/Fixture.bundle")! } }\n' "$TMP" > "$TMP/BundleModule.swift"
python3 - "$TMP/MacWorkspaceCanvas.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/MouseCompanion/MacWorkspaceCanvas.swift').read_text()
s=s.replace('config.websiteDataStore = .default()', 'config.websiteDataStore = .nonPersistent()')
s=s.replace('    func userContentController(_ userContentController:', '    var fixtureMessages: [[String: Any]] = []\n    func userContentController(_ userContentController:')
s=s.replace('        switch action {', '        fixtureMessages.append(body)\n        switch action {')
Path(sys.argv[1]).write_text(s)
PY
S=Sources/MouseCompanion
swiftc -module-cache-path "$ROOT/.build/arm64-apple-macosx/release/ModuleCache" "$S/CompanionContext.swift" "$S/CompanionProjectStore.swift" "$S/DesignSuggestions.swift" "$S/DesignOCR.swift" "$S/MaterialPresentation.swift" "$S/MacWorkspaceStorage.swift" "$TMP/BundleModule.swift" "$TMP/MacWorkspaceCanvas.swift" Tests/WeaviaSelectionToolsChecks.swift -o "$TMP/check"
"$TMP/check" "$TMP/data"
