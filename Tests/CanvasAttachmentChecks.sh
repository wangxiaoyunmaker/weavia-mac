#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"; TMP=$(mktemp -d /tmp/weavia-attachments.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
printf 'import Foundation\nextension Bundle { static var module: Bundle { Bundle.main } }\n' > "$TMP/BundleModule.swift"
S=Sources/MouseCompanion
swiftc -module-cache-path "$ROOT/.build/arm64-apple-macosx/release/ModuleCache" "$S/CompanionContext.swift" "$S/CompanionProjectStore.swift" "$S/DesignSuggestions.swift" "$S/DesignOCR.swift" "$S/MaterialPresentation.swift" "$S/MacWorkspaceStorage.swift" "$S/CanvasAttachments.swift" "$TMP/BundleModule.swift" Tests/CanvasAttachmentChecks.swift -o "$TMP/check"
"$TMP/check"
