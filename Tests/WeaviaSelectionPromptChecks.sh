#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
P="$PWD"
TMP=$(mktemp -d /tmp/weavia-selection-prompt.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
python3 - "$P" "$TMP" <<'PYSOURCE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); tmp=Path(sys.argv[2]); source=(p/'Sources/MouseCompanion/main.swift').read_text()
source=source[:source.index('private let app = NSApplication.shared')]
a=source.index('private final class UserPromptController:'); b=source.index('private final class AnswerTextView:',a)
prompt=source[a:b]
# Only the temporary fixture simulates visibility; no window is ever ordered onscreen.
prompt=prompt.replace('panel.isVisible','true').replace('panel.makeKeyAndOrderFront(nil)', 'precondition(!panel.isVisible)').replace('NSApp.activate(ignoringOtherApps: true)', 'precondition(!panel.isVisible)')
source=source[:a]+prompt+source[b:]
assert 'guard attempts < 100 else { agentBusy = false;' in source
assert 'guard let visible = screen?.visibleFrame else { agentBusy = false; return }' in source
(tmp/'main.swift').write_text(source+(p/'Tests/WeaviaSelectionPromptChecks.swift').read_text())
(tmp/'BundleModule.swift').write_text('import Foundation\nextension Bundle { static var module: Bundle { Bundle.main } }\n')
PYSOURCE
FILES=()
for f in Sources/MouseCompanion/*.swift; do [[ "$f" == */main.swift ]] || FILES+=("$f"); done
swiftc -module-cache-path "$P/.build/arm64-apple-macosx/release/ModuleCache" "${FILES[@]}" "$TMP/BundleModule.swift" "$TMP/main.swift" -o "$TMP/check"
"$TMP/check"
