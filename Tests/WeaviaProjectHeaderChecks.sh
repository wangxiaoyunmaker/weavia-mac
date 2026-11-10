#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP=$(mktemp -d /tmp/weavia-header-check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/WEAVIA 候选版.bundle" "$TMP/data"
cp -R "${CANVAS_RESOURCES:-Sources/MouseCompanion/CuppaCanvas}" "$TMP/WEAVIA 候选版.bundle/"
printf 'import Foundation\nextension Bundle { static var module: Bundle { Bundle(path: "%s/WEAVIA 候选版.bundle")! } }\n' "$TMP" > "$TMP/BundleModule.swift"
cp "${NATIVE_CONTROLLER:-Sources/MouseCompanion/MacWorkspaceCanvas.swift}" "$TMP/MacWorkspaceCanvas.swift"
# Keep WebKit storage isolated as well as project files.
python3 - "$TMP/MacWorkspaceCanvas.swift" <<'PYDATA'
from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text(p.read_text().replace('config.websiteDataStore = .default()', 'config.websiteDataStore = .nonPersistent()'))
PYDATA
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
swiftc -module-cache-path "$ROOT/.build/arm64-apple-macosx/release/ModuleCache" "$S/CompanionContext.swift" "$S/CompanionProjectStore.swift" "$S/DesignSuggestions.swift" "$S/DesignOCR.swift" "$S/MaterialPresentation.swift" "$S/MacWorkspaceStorage.swift" "$S/CanvasAttachments.swift" "$TMP/BundleModule.swift" "$TMP/MacWorkspaceCanvas.swift" Tests/WeaviaProjectHeaderChecks.swift -o "$TMP/WeaviaProjectHeaderChecks"
"$TMP/WeaviaProjectHeaderChecks" "$TMP/data" "${@:1}"
