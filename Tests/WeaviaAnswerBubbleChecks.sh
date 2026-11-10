#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
P="$PWD"
TMP=$(mktemp -d /tmp/weavia-answer-bubble.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
python3 - "$P" "$TMP" <<'PYSOURCE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); tmp=Path(sys.argv[2]); source=(p/'Sources/MouseCompanion/main.swift').read_text()
source=source[:source.index('private let app = NSApplication.shared')]
a=source.index('private final class AgentAnswerController {'); b=source.index('private final class InspirationController:',a)
answer=source[a:b]
assert answer.count('panel.orderFrontRegardless()') == 1
# Test-only suppression of the sole window-ordering statement. All render/Stop logic is real.
answer=answer.replace('panel.orderFrontRegardless()', 'precondition(!panel.isVisible)')
source=source[:a]+answer+source[b:]
assert 'agentAnswer.onStop = { [weak self] in self?.stopAgentGeneration() }' in source
assert 'agentRequest?.cancel(); agentRequest = nil\n        conversationGeneration = UUID()' in source
(tmp/'main.swift').write_text(source+(p/'Tests/WeaviaAnswerBubbleChecks.swift').read_text())
(tmp/'BundleModule.swift').write_text('import Foundation\nextension Bundle { static var module: Bundle { Bundle.main } }\n')
PYSOURCE
FILES=()
for f in Sources/MouseCompanion/*.swift; do [[ "$f" == */main.swift ]] || FILES+=("$f"); done
swiftc -module-cache-path "$P/.build/arm64-apple-macosx/release/ModuleCache" "${FILES[@]}" "$TMP/BundleModule.swift" "$TMP/main.swift" -o "$TMP/check"
"$TMP/check"
