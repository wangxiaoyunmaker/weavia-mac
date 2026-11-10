#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d /tmp/weavia-native-check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/WEAVIA 候选版.bundle" "$TMP/data"
cp -R "${CANVAS_RESOURCES:-Sources/MouseCompanion/CuppaCanvas}" "$TMP/WEAVIA 候选版.bundle/"
printf 'import Foundation\nextension Bundle { static var module: Bundle { Bundle(path: "%s/WEAVIA 候选版.bundle")! } }\n' "$TMP" > "$TMP/BundleModule.swift"
cp "${NATIVE_CONTROLLER:-Sources/MouseCompanion/MacWorkspaceCanvas.swift}" "$TMP/MacWorkspaceCanvas.swift"
# Only the disposable test copy uses ephemeral web storage; production files are untouched.
python3 - "$TMP/MacWorkspaceCanvas.swift" <<'PYTEST'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text()
assert 'config.websiteDataStore = websiteDataStore' in t
t=t.replace('config.websiteDataStore = websiteDataStore', 'config.websiteDataStore = .nonPersistent()\n        config.userContentController.addUserScript(WKUserScript(source: "window.requestAnimationFrame = function(){ window.fixtureFrameRequests=(window.fixtureFrameRequests||0)+1; return 1; };", injectionTime: .atDocumentStart, forMainFrameOnly: true))')
p.write_text(t)
PYTEST
if [[ "${INSTRUMENT_NATIVE:-0}" == 1 ]]; then
python3 - "$TMP/MacWorkspaceCanvas.swift" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(); needle='        guard message.frameInfo.isMainFrame, isTrusted(message.frameInfo.request.url),'
t=t.replace(needle, '        print("NATIVE_MESSAGE: main=\\(message.frameInfo.isMainFrame) url=\\(String(describing: message.frameInfo.request.url)) trusted=\\(isTrusted(message.frameInfo.request.url)) root=\\(String(describing: resourceRoot)) type=\\(type(of: message.body))")\n'+needle)
p.write_text(t)
PY
fi
S=Sources/MouseCompanion
swiftc -module-cache-path "$ROOT/.build/arm64-apple-macosx/release/ModuleCache" "$S/CompanionContext.swift" "$S/CompanionProjectStore.swift" "$S/DesignSuggestions.swift" "$S/DesignOCR.swift" "$S/MaterialPresentation.swift" "$S/MacWorkspaceStorage.swift" "$S/CanvasAttachments.swift" "$TMP/BundleModule.swift" "$TMP/MacWorkspaceCanvas.swift" Tests/WeaviaSnapshotHydrationChecks.swift -o "$TMP/WeaviaSnapshotHydrationChecks"
"$TMP/WeaviaSnapshotHydrationChecks" "$TMP/data" "${@:1}"
