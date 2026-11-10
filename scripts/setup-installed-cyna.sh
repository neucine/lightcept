#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/cyna-toolchain.lock"
installed="${LIGHTCEPT_INSTALLED_CYNA:-$(command -v cyna || true)}"
if [[ -z "$installed" || ! -x "$installed" ]]; then
  echo "Cyna is missing; install Cyna $cyna_version or set LIGHTCEPT_INSTALLED_CYNA" >&2
  exit 1
fi
if [[ "$("$installed" version 2>&1)" != "cyna $cyna_version" ]]; then
  echo "Lightcept requires Cyna $cyna_version" >&2
  exit 1
fi
compiler="$root/target/cyna-toolchain/cyna/zig-out/bin/cyna"
mkdir -p "$(dirname "$compiler")"
installed="$(realpath "$installed")"
if [[ "$installed" != "$compiler" ]]; then
  ln -sfn "$installed" "$compiler"
fi
binary_hash="$(shasum -a 256 "$compiler")"
binary_hash="${binary_hash%% *}"
cat > "$root/target/cyna-toolchain/receipt" <<RECEIPT
source_kind=installed
cyna_version=$cyna_version
compiler_sha256=$binary_hash
RECEIPT
"$root/scripts/check-cyna-toolchain.sh" "$compiler"
