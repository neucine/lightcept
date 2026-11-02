# Native engine layout

The `src/cyna.toml` package builds the headless Cyna imaging engine. Modules
are grouped by the data they own. The maintained
[engine boundary](../../docs/architecture/lightcept-engine-boundary.md) defines
allowed imports; `scripts/check-boundaries.sh` enforces them in CI.

- `raw/dng/` and `raw/nef/` own format specific parsing, sensor decoding,
  normalization, source geometry, color characterization, baseline exposure,
  and orientation. Shared Bayer and lossless JPEG operations stay in `raw/`.
- `raw/camera_mosaic.cy` defines the common handoff: caller-owned, unrotated,
  camera-linear Bayer `f32` pixels plus checked metadata. A failed or cancelled
  decode invalidates the output. Adding a format should target this contract.
- `color/` owns camera and output color mathematics. DNG tag parsing lives in
  `raw/dng/dng_profile.cy`; `color/dng/` interprets those values and performs
  the DNG color transform. The Nikon Z8 profile lives in `color/nef/`.
  Shared RGB and XYZ transforms stay at the color component root.
- `develop/` owns adjustments and their bounds.
- `pipeline/` chooses the ordered stages, checks parameters and output bounds,
  and connects a prepared camera mosaic to the shared processing and rendering
  components. Its `dng/` and `nef/` subfolders adapt format sources to that
  shared sequence. It does not parse containers or decode sensor strips.
- `render/` owns output pixel kernels and buffers. DNG-specific pixel and
  preview buffer operations live in `render/dng/`; the qualified legacy DNG
  preview is composed by `pipeline/dng/dng_legacy_preview_pipeline.cy`.
- `tiff/` owns bounded TIFF packaging. `core/` owns shared image bounds.

The stage names describe operations across formats. Each stage has one owner:

| Stage | Input → output | Owner |
| --- | --- | --- |
| Source inspection and sensor decode | Format bytes → stored sensor codes | `raw/dng/`, `raw/nef/` |
| Sensor normalization | Stored sensor codes → `CameraMosaic` and camera-linear samples | `raw/dng/`, `raw/nef/` |
| Demosaic | Camera mosaic → camera-linear RGB | `raw/bayer.cy` |
| Camera color and white balance | Camera-linear RGB → working RGB | `color/` |
| Develop adjustments | Working RGB → adjusted working RGB | `develop/` |
| Output rendering | Adjusted RGB → RGBA8 or RGB16 | `render/` |
| Composition and validation | Ordered stage calls and bounds | `pipeline/` |

Format pipeline modules adapt source bytes and output requests to that shared
sequence. The legacy DNG preview uses its own qualified, byte-backed Bayer
kernel; `raw/dng/dng_bayer.cy` owns that source-specific sampling.

`pipeline/develop_stage_manifest.cy` describes the logical develop capability
contract. `develop/edit_plan.cy` orders the diagnostic scalar edit executor.
The [develop family index](develop/README.md) groups all 60 declared
capabilities while retaining component ownership for their pixel domains.
The camera preview routes choose their own versioned render modes in
`pipeline/camera_mosaic_pipeline.cy`. These contracts have different scopes;
none is a complete manifest of every source decode and render operation.

The DNG and NEF source adapters are separate because their storage, metadata,
normalization, and camera characterization differ. Their RGBA8 preview routes
call `pipeline/camera_mosaic_pipeline.cy` after decoding. That shared entry
validates the mosaic, output geometry, edit controls, and an explicit render
mode before dispatching to the Bayer or spatial renderer. `baseline_bilinear_v1`
preserves the DNG diagnostic preview, `fitted_mhc_v1` preserves the Z8 preview
and RGB16 output, and `spatial_headroom_v5` preserves the Ricoh product preview.
The Ceiv DNG route prepares an oriented, preview-sized f64 scene-linear
Rec.2020/D65 working image after spatial reconstruction. Its exposure and
contrast renders reuse that image without repeating RAW decode, demosaic,
reconstruction, camera color, or resampling. The UI owns the cache lifetime;
the engine owns every pixel operation and remains callable without Ceiv.

The DNG spatial route and experimental NEF route still use different develop
sequences; those sequences are declared pipeline choices, not source decoder
behavior. New RAW adapters should provide `CameraMosaic` and call this entry.

The active Ceiv app imports the Cyna engine package directly. The engine no
longer exports `lc_cyna_img_*` C symbols; its former numeric entry points are
internal implementation functions. The C boundary belongs to Ceiv's native
host for file access, cancellation, and frame publication, and to the few C
math helpers used by imaging components. New engine callers should use typed
Cyna slices and structs at public module boundaries. The sibling
`lightcept-rust-reference` checkout retains its own Cyna sources and C ABI for
historical comparison; it does not link this package.

Engine pixels, dimensions, status values, and mathematical controls use Cyna
types (`u8`, `u16`, `u32`, `usize`, `i32`, `f32`, `f64`). Stages take a Cyna
`fn(usize): bool` cancellation callback and caller-owned opaque context. A
true poll returns status 7; the caller discards partial output. The remaining
`c_*` types belong to direct C math and rounding imports. The old contract, desktop, intent, and project C export
modules live only in `lightcept-rust-reference`.

Keep these as modules in one Cyna package unless a concrete independent
consumer or release boundary justifies another package. A component owns its
pixel math; the pipeline composes components and validates their order.
