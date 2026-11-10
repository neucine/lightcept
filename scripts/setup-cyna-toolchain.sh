#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/cyna-toolchain.lock"
zig_bin="${LIGHTCEPT_ZIG_017:-zig}"
if [[ "$("$zig_bin" version)" != "$zig_version" ]]; then
  echo "Lightcept requires Zig $zig_version; set LIGHTCEPT_ZIG_017" >&2
  exit 1
fi
checkout="$root/target/cyna-toolchain"
mkdir -p "$checkout"
fetch_pinned() {
  local directory="$1" repository="$2" commit="$3"
  if [[ "${LIGHTCEPT_CYNA_PRECHECKED_OUT:-}" == "1" ]]; then
    if [[ ! -d "$directory/.git" ]]; then
      echo "Prechecked Cyna source is missing: $directory" >&2
      exit 1
    fi
    if [[ "$(git -C "$directory" rev-parse HEAD)" != "$commit" ]]; then
      echo "Prechecked Cyna source is missing or at the wrong commit: $directory" >&2
      exit 1
    fi
    return
  fi
  if [[ ! -d "$directory/.git" ]]; then
    git init -q "$directory"
    git -C "$directory" remote add origin "$repository"
  fi
  git -C "$directory" fetch -q --depth 1 origin "$commit"
  git -C "$directory" checkout -q --detach FETCH_HEAD
  if [[ "$(git -C "$directory" rev-parse HEAD)" != "$commit" ]]; then
    echo "Unexpected checkout revision: $directory" >&2
    exit 1
  fi
}
fetch_pinned "$checkout/zig-libs" "$zig_libraries_repository" "$zig_libraries_commit"
fetch_pinned "$checkout/cyna" "$cyna_repository" "$cyna_commit"
git -C "$checkout/cyna" reset -q --hard "$cyna_commit"
(cd "$checkout/cyna" && "$zig_bin" build)
compiler="$checkout/cyna/zig-out/bin/cyna"
if [[ "$("$compiler" version 2>&1)" != "cyna $cyna_version" ]]; then
  echo "Built Cyna version mismatch" >&2
  exit 1
fi
binary_hash="$(shasum -a 256 "$compiler")"
binary_hash="${binary_hash%% *}"
cat > "$checkout/receipt" <<RECEIPT
cyna_commit=$cyna_commit
zig_libraries_commit=$zig_libraries_commit
zig_version=$zig_version
compiler_sha256=$binary_hash
RECEIPT
"$root/scripts/check-cyna-toolchain.sh" "$compiler"
