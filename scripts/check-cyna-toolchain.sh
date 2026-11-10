#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/cyna-toolchain.lock"
compiler="${1:-${LIGHTCEPT_CYNA_COMPILER:-$root/target/cyna-toolchain/cyna/zig-out/bin/cyna}}"
receipt="$root/target/cyna-toolchain/receipt"
if [[ ! -x "$compiler" || ! -f "$receipt" ]]; then
  echo "Pinned Cyna compiler is missing; run scripts/setup-cyna-toolchain.sh" >&2
  exit 1
fi
expected_binary="$(awk -F= '$1 == "compiler_sha256" {print $2}' "$receipt")"
actual_binary="$(shasum -a 256 "$compiler")"
actual_binary="${actual_binary%% *}"
if [[ "$actual_binary" != "$expected_binary" ]]; then
  echo "Cyna compiler checksum differs from the setup receipt" >&2
  exit 1
fi
for key in cyna_commit zig_libraries_commit zig_version; do
  recorded="$(awk -F= -v key="$key" '$1 == key {print $2}' "$receipt")"
  if [[ "$recorded" != "${!key}" ]]; then
    echo "Cyna setup receipt is stale: $key" >&2
    exit 1
  fi
done
version="$("$compiler" version 2>&1)"
if [[ "$version" != "cyna $cyna_version" ]]; then
  echo "Cyna version mismatch: $version" >&2
  exit 1
fi
