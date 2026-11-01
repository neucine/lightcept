# Lightcept documentation

Use the documents below for current decisions and implementation work. The
[archive](archive/README.md) preserves experiments, first variants, reviews, and
superseded migration notes as historical evidence. A document in the archive
does not define current routing, support, or acceptance policy.

## Architecture and delivery

| Document | Maintained purpose |
| --- | --- |
| [Native RAW editor architecture](architecture/lightcept-native-editor.md) | Product-wide document and editing model; Rust diagrams are historical. |
| [Native RAW engine architecture](architecture/lightcept-native-raw-engine.md) | Imaging domains, stage ownership, safety and qualification; Rust routing sections are historical. |
| [Engine boundary](architecture/lightcept-engine-boundary.md) | Current headless Cyna engine and Ceiv host boundary. |
| [Cyna-first layout](architecture/cyna-first-layout.md) | Current Cyna-only source and host layering. |
| [Native pipeline target](architecture/native-pipeline-target.md) | Semantic recipe, photographic plan, and execution plan. |
| [Develop capability contract](architecture/develop-capability-contract.md) | Proposed control and stage semantics; review status is stated in the document. |
| [Native engine execution plan](architecture/native-engine-execution-plan.md) | Living gates, current qualification scope, and next slices. |
| [Ceiv migration](architecture/ceiv-migration.md) | Desktop framework integration and migration gates. |
| [HNCS engine assessment](architecture/hncs-engine-assessment.md) | Research evidence and color-stage qualification decision. |

New camera, format, and processing work should follow the architecture, update
the execution plan and the relevant contract. Record exact-source qualification and reproducible
evidence under [qualification](../qualification/README.md). Move completed
experiments and one-off reviews to the archive after their conclusion is
reflected in a maintained document. Preserve their provenance and links.

## Product and qualification

- [Quiet Studio UX](product/quiet-studio-ux.md) — current product direction.
- [Qualification index](../qualification/README.md) — current source routing
  scope, evidence, and diagnostic candidates.
- [RAW support closure](../qualification/raw-support-closure.md) — required
  evidence for a new camera/format variant.

The current Nikon Z8 and shared working-stage candidate records remain under
`qualification/`. Diagnostic work does not imply product qualification.
Dated competitive research, completed milestones, stage notes, and historical
qualification reports are discoverable from the [archive](archive/README.md).
