#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
app="$repo/ui/neiv"
"$repo/scripts/check-cyna-toolchain.sh"
PATH="$repo/target/cyna-toolchain/cyna/zig-out/bin:$PATH"
export PATH
SDKROOT=$(xcrun --show-sdk-path)
export SDKROOT
mkdir -p "$app/build"
for stale in \
    "$app/build/NeivApp.app" \
    "$app/build/NeivApp" \
    "$app/build/liblightcept_neiv.a" \
    "$app/build/liblightcept_neiv.a.cyna-link.toml"; do
    if [ -e "$stale" ]; then
        find "$stale" -depth -delete
    fi
done
cyna build "$repo/src/tools/export_tiff.cyna.toml" --output "$app/build/lightcept-export-tiff"
cyna build "$repo/src/tools/render_source_region.cyna.toml" --output "$app/build/lightcept-source-region"
cyna build "$repo/src/tools/render_fitted_preview.cyna.toml" --output "$app/build/lightcept-fitted-preview"
cp "$repo/src/engine/assets/sRGB2014.icc" "$app/build/sRGB2014.icc"
neiv_cli="${LIGHTCEPT_NEIV_CLI:-$repo/../neiv/packages/neiv/bin/neiv.mjs}"
if [ ! -f "$neiv_cli" ]; then
    echo "Neiv CLI not found: $neiv_cli (set LIGHTCEPT_NEIV_CLI)" >&2
    exit 1
fi
node "$neiv_cli" build "$app"
