#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d /tmp/weavia-snapshot-identity.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/"
# The pure store test never instantiates application, WebKit, or production storage.
printf 'import Foundation\nstruct CompanionProjectStore { init(directory: URL) {} }\n' > "$TMP/ProjectStoreStub.swift"
swiftc -module-cache-path "$TMP/ModuleCache" Sources/MouseCompanion/MacWorkspaceStorage.swift "$TMP/ProjectStoreStub.swift" Tests/WeaviaSnapshotIdentityChecks.swift -o "$TMP/checks"
"$TMP/checks"
swiftc -module-cache-path "$TMP/ModuleCache" Sources/MouseCompanion/MacWorkspaceStorage.swift "$TMP/ProjectStoreStub.swift" Tests/MacWorkspaceStorageChecks.swift -o "$TMP/legacy-checks"
"$TMP/legacy-checks"
