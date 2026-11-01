#!/usr/bin/env bash
# The pinned Cyna test runner requires an executable manifest, even for library tests.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p target/g2-exposure-test
cat > target/g2-exposure-test/cyna.toml <<'MANIFEST'
name = "g2_exposure_test"
version = "0.1.0"
type = "exe"
src = "../../src"
entry = "../../src/lib.cy"
[build]
target = "native"
opt = "release"
MANIFEST
if [[ "$(uname -s)" == Darwin ]]; then
    cyna_sdk_root="$(xcrun --show-sdk-path)"
    SDKROOT="$cyna_sdk_root" target/cyna-toolchain/cyna/zig-out/bin/cyna test target/g2-exposure-test --filter exposure
else
    target/cyna-toolchain/cyna/zig-out/bin/cyna test target/g2-exposure-test --filter exposure
fi
