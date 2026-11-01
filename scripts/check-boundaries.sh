#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
for old in Cargo.toml Cargo.lock rustfmt.toml clippy.toml crates src/rust src/bridge; do
  if [[ -e "$root/$old" ]]; then
    echo "legacy Rust path in active Lightcept repo: $old" >&2
    exit 1
  fi
done

if find "$root/src" -type f -name '*.rs' -print -quit | grep -q .; then
  echo "Rust source remains in the active Cyna tree" >&2
  exit 1
fi

if grep -Eq 'cargo|liblightcept_ceiv_adapter|dlopen|dlsym|lc_ceiv_' \
  "$root/src/ui/ceiv/build.sh" "$root/src/ui/ceiv/app.json" "$root/src/ui/ceiv/native/preview_plugin.m"; then
  echo "Ceiv still references the retired Rust adapter" >&2
  exit 1
fi
