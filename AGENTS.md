# Lightcept contributor instructions

- This is the active Cyna and Ceiv repository. Keep the old Rust application,
  bridges, Cargo workspace, and Rust qualification tools in the sibling
  `lightcept-rust-reference` checkout. Do not reintroduce a Rust dependency
  into the active app or engine.
- Record Cyna language, compiler, runtime, standard-library, and tooling gaps
  only in the sibling Cyna repository's `docs/LANGUAGE_GAPS.md`, including the
  Lightcept compiler pin, minimal reproduction, affected stage, and workaround.
  `docs/cyna-gap-log.md` is historical evidence only.
- Keep source photographs immutable and edits non-destructive.
- Keep native imaging Cyna components usable by a headless caller without
  Lightcept project, planner, UI, or compatibility-backend types. Give each
  stage explicit input/output meaning, units, bounds, errors, cancellation
  behavior, and algorithm version.
- Keep pixel mathematics in the component that owns the operation. The Cyna
  `pipeline` module composes and validates stage order; it must not collect
  unrelated processing kernels.
- Before adding a decoder or processing stage, review relevant external
  engines and published methods. Record what they teach, then define
  Lightcept's own behavior, tests, and component owner. Compare matched
  inputs where useful; check licenses and provenance before using assets.
- Favor descriptive photographic names, direct control flow, focused
  functions, and concrete types. Document units, colour spaces, coordinate
  systems, and valid ranges on image data and public APIs.
- Keep the scalar CPU path straightforward. Test analytical vectors and
  representative images before adding parallel, SIMD, or GPU implementations.
  Profile before optimizing.
- Use checked arithmetic and explicit resource limits for source-derived
  values. Return contextual errors for expected failures.
- Run `scripts/check-boundaries.sh` after changing dependencies or engine-facing
  code. Format and check with the pinned Cyna compiler; run focused tests while
  iterating.
- Before committing, run `cyna fmt src --check`, `cyna check src`,
  `python3 scripts/test-cyna-native.py`, and `scripts/check-boundaries.sh` with
  the pinned compiler. On macOS, build `src/ui/ceiv/build.sh` after Ceiv changes.
