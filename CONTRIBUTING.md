# Contributing to Lightcept

Lightcept is implemented in Cyna with a Neiv desktop host and a Weiv page. The
active repository must stay free of Rust, Cargo, and the retired Rust adapters.

## Development setup

1. Install Node.js 22 and Cyna 0.5.0 from [cyna.dev](https://cyna.dev/).
2. Run `scripts/setup-installed-cyna.sh` to link the installed compiler. To
   reproduce the pinned compiler from source, install Zig 0.17.0 and run
   `scripts/setup-cyna-toolchain.sh` instead.
3. Keep a Neiv checkout at `../neiv`, or set `LIGHTCEPT_NEIV_CLI`.
4. Contributors with access to the private `neucine/daydream` repository should
   read `projects/lightcept/docs/architecture/lightcept-engine-boundary.md`
   before changing engine modules.

## Before opening a change

Run the focused tests for the code you touched, then the full repository checks:

```sh
scripts/check-boundaries.sh
target/cyna-toolchain/cyna/zig-out/bin/cyna fmt src --check
target/cyna-toolchain/cyna/zig-out/bin/cyna check .
python3 scripts/test-cyna-native.py
ui/neiv/build.sh
```

## Change rules

- Keep source photographs immutable; edits and exports are non-destructive.
- Keep pixel mathematics in the component that owns the operation. The
  `pipeline` module composes and validates stages; it does not collect unrelated
  kernels.
- Register a new RAW format in `scripts/check-engine-boundaries.py`; do not
  widen the checker with a broad exclusion.
- Give each stage explicit input/output meaning, units, bounds, errors,
  cancellation behavior, and algorithm version.
- Record a new camera or storage variant in the architecture repository's
  `qualification/` tree with exact source, profile, pipeline, and output
  identities.
- Record Cyna language, compiler, runtime, standard-library, and tooling gaps in
  the sibling Cyna repository's `docs/LANGUAGE_GAPS.md`, not here.
- Use canonical terms from [docs/terminology.md](docs/terminology.md).

## Scope

Architecture notes, diagnostic stage specifications, historical decisions, and
qualification evidence belong in the private `neucine/daydream` repository
under `projects/lightcept/`. Public user and API documentation belongs in
`docs/`.

Lightcept is licensed under the Mozilla Public License, version 2.0. By
contributing, you agree that your changes may be distributed under those terms.
