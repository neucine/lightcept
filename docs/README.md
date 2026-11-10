# Lightcept documentation

This directory contains the public documentation that ships with the Lightcept
application and engine. Internal architecture records, decision history,
diagnostic stage specifications, and native RAW qualification evidence live in
the private `neucine/daydream` engineering repository under `projects/lightcept/`.

## Public documents

- [Terminology](terminology.md) — canonical product, imaging, and support
  vocabulary.
- [Quiet Studio UX](product/quiet-studio-ux.md) — long-term intention editing
  direction and interaction rules.

## Architecture and qualification

The maintained engineering records are available to project contributors in
the private `neucine/daydream` repository:

- `projects/lightcept/docs/README.md` — architecture index
- `projects/lightcept/docs/architecture/lightcept-engine-boundary.md` — engine boundary
- `projects/lightcept/docs/architecture/native-pipeline-target.md` — native pipeline target
- `projects/lightcept/docs/architecture/develop-capability-contract.md` — develop capability contract
- `projects/lightcept/docs/plans/2026-11-10-native-engine-execution-plan.md` — native engine execution plan
- `projects/lightcept/qualification/README.md` — qualification index
- `projects/lightcept/qualification/raw-support-closure.md` — RAW support closure

## Documentation rules

State implemented behavior and qualification scope separately from a term's
definition. Link to the exact source variant and evidence when claiming
support. A diagnostic kernel or candidate route does not imply product
qualification.

New camera, format, and processing work should update the relevant contract,
the execution plan, and the qualification record together. Completed
experiments and superseded plans belong in the architecture repository's
archive.
