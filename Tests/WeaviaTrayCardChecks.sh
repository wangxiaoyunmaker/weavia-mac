#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
P="$PWD"
TMP=$(mktemp -d /tmp/weavia-tray-check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p verification/tray-cards
python3 - "$P" "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); tmp=Path(sys.argv[2]); source=(p/'Sources/MouseCompanion/main.swift').read_text()
assert 'rows.addArrangedSubview(row)' not in source[source.index('@objc func showContents()'):source.index('    private func receive(')]
assert 'tray-contents-empty' in source and '先收集，不急着整理' in source
assert 'document.heightAnchor.constraint(equalToConstant: contentHeight)' in source
assert 'scroll.scrollerStyle = .overlay' in source
source=source[:source.index('private let app = NSApplication.shared')]+(p/'Tests/WeaviaTrayCardChecks.swift').read_text()
(tmp/'main.swift').write_text(source)
(tmp/'BundleModule.swift').write_text('import Foundation\nextension Bundle { static var module: Bundle { Bundle.main } }\n')
print('PASS: empty-state branch, fixed scrollbar lane, full-height document and no legacy row stack')
PY
FILES=()
for f in Sources/MouseCompanion/*.swift; do [[ "$f" == */main.swift ]] || FILES+=("$f"); done
swiftc -module-cache-path "$P/.build/arm64-apple-macosx/release/ModuleCache" "${FILES[@]}" "$TMP/BundleModule.swift" "$TMP/main.swift" -o "$TMP/check"
"$TMP/check" "$P/verification/tray-cards/synthetic-cards.png"
