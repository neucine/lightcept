# Develop kernel families

All 60 planned photographic develop capabilities form one logical develop
catalog. The [stage manifest](../pipeline/develop_stage_manifest.cy) declares
their names, domains, and composition policy. The
`projects/lightcept/docs/investigations/2026-11-10-develop-kernel-audit.md`
record in the private `neucine/daydream` repository lists each stage's
implementation, tests, contract, and semantic review, grouped by the families
below.

| Family | Stages | Kernel owners |
| --- | ---: | --- |
| Capture color | 4 | `develop/`, `color/` |
| Tone | 8 | `develop/`, `analysis/` |
| Color | 8 | `develop/`, `color/` |
| Detail and atmosphere | 10 | `develop/` |
| Geometry and optics | 7 | `raw/`, `develop/` |
| Masks and local | 7 | `develop/`, `analysis/` |
| Output | 9 | `color/`, `render/` |
| Analysis | 7 | `analysis/` |

These are catalog families, not import or pixel-domain boundaries. Shared
kernels stay at their component roots as required by the
engine boundary in `projects/lightcept/docs/architecture/lightcept-engine-boundary.md`.
Format-specific modules stay in their format folders. The develop manifest
composes and validates stages; each component owns its own pixel math.
