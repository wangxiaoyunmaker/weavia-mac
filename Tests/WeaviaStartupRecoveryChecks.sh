#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SOURCE_ROOT="${STARTUP_SOURCE_ROOT:-$ROOT}"
TMP=$(mktemp -d /tmp/weavia-native-check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/WEAVIA 候选版.bundle" "$TMP/data"
cp -R "${CANVAS_RESOURCES:-$SOURCE_ROOT/Sources/MouseCompanion/CuppaCanvas}" "$TMP/WEAVIA 候选版.bundle/"
printf 'import Foundation\nextension Bundle { static var module: Bundle { Bundle(path: "%s/WEAVIA 候选版.bundle")! } }\n' "$TMP" > "$TMP/BundleModule.swift"
cp "${NATIVE_CONTROLLER:-$SOURCE_ROOT/Sources/MouseCompanion/MacWorkspaceCanvas.swift}" "$TMP/MacWorkspaceCanvas.swift"
# Test-only document-start seeding; production initializer receives shared ephemeral store.
python3 - "$TMP/MacWorkspaceCanvas.swift" <<'PYTEST'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();needle='config.websiteDataStore = websiteDataStore'
assert needle in s
s=s.replace(needle,needle+'\n        precondition(!websiteDataStore.isPersistent)\n        config.userContentController.addUserScript(WKUserScript(source: StartupFixture.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))')
s=s.replace('window.mouseCompanionMac && window.mouseCompanionMac.\\(method)(\\(json));', 'if (\\"\\(method)\\" === \\"receiveSnapshot\\") window.fixtureNativeHydrating=true; window.mouseCompanionMac && window.mouseCompanionMac.\\(method)(\\(json));')
p.write_text(s)
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
S="$SOURCE_ROOT/Sources/MouseCompanion"
swiftc -module-cache-path "$TMP/module-cache" "$S/CompanionContext.swift" "$S/CompanionProjectStore.swift" "$S/DesignSuggestions.swift" "$S/DesignOCR.swift" "$S/MaterialPresentation.swift" "$S/MacWorkspaceStorage.swift" "$S/CanvasAttachments.swift" "$TMP/BundleModule.swift" "$TMP/MacWorkspaceCanvas.swift" Tests/WeaviaStartupRecoveryChecks.swift -o "$TMP/WeaviaStartupRecoveryChecks"
"$TMP/WeaviaStartupRecoveryChecks" "$TMP/data" "${@:1}"
