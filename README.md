# Lightcept

Lightcept is a native, intent-driven RAW editor. Photographic language is converted into typed,
reviewable edit plans; the source image remains untouched.

Start with the [documentation guide](docs/README.md) for maintained architecture,
product, and qualification documents; historical engineering notes are archived there.

The primary application is Ceiv: Weiv presents the desktop page, Cyna owns app
commands and workflow state, and native Cyna imaging components form the
RAW engine. The earlier Rust desktop applications and their validation baseline
are preserved in the sibling `lightcept-rust-reference` checkout.

## Workspace

- `src/cyna.toml` and `src/lib.cy` — the Cyna product and imaging package
- `src/project`, `src/intent`, `src/contract`, `src/desktop` — product decisions and workflow contracts
- `src/engine` — headless Cyna RAW engine and focused tests
- `src/ui/ceiv` — Ceiv desktop app with Weiv presentation, Cyna commands, and a native preview provider
- `scripts` — pinned Cyna toolchain, boundary, and qualification checks

The old Rust app, engine adapters, Cargo workspace, and Rust qualification tools
are preserved in the sibling `lightcept-rust-reference` checkout. Native source
coverage can grow independently of this separation.

## Run

```sh
src/ui/ceiv/build.sh
```

The packaged Ceiv app currently opens qualified DNGs, including the pinned
Ricoh GR III and GR IIIx captures, for preview with exposure and contrast edits.
Persistence, export, and other source formats are still being migrated.

## Verify

```sh
scripts/check-boundaries.sh
target/cyna-toolchain/cyna/zig-out/bin/cyna fmt src --check
target/cyna-toolchain/cyna/zig-out/bin/cyna check src
python3 scripts/test-cyna-native.py
```

Ceiv-specific build and behavior are documented in
[src/ui/ceiv/README.md](src/ui/ceiv/README.md).

The old Rust packaging script belongs to the sibling reference checkout.
