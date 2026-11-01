# Native engine layout

The `src/cyna.toml` package builds the headless Cyna imaging engine. Modules
are grouped by the data they own:

- `raw/dng/` and `raw/nef/` own format specific parsing, sensor decoding,
  normalization, source geometry, color characterization, baseline exposure,
  and orientation. Shared Bayer and lossless JPEG operations stay in `raw/`.
- `raw/camera_mosaic.cy` defines the common handoff: caller-owned, unrotated,
  camera-linear Bayer `f32` pixels plus checked metadata. A failed or cancelled
  decode invalidates the output. Adding a format should target this contract.
- `color/` owns camera and output color mathematics. RAW adapters call its
  characterization functions; they do not reimplement the pixel transforms.
- `develop/` owns adjustments and their bounds.
- `pipeline/` chooses the ordered stages, checks parameters and output bounds,
  and connects a prepared camera mosaic to the shared processing and rendering
  components. It does not parse containers or decode sensor strips.
- `render/` owns pixel rendering and output buffers.
- `tiff/` owns bounded TIFF packaging. `core/` owns shared image bounds.

The DNG and NEF source adapters are separate because their storage, metadata,
normalization, and camera characterization differ. Their RGBA8 preview routes
call the same Bayer renderer. The DNG spatial route and experimental NEF route
still use different develop sequences; those sequences are explicit pipeline
choices, not source decoder behavior.

Keep these as modules in one Cyna package unless a concrete independent
consumer or release boundary justifies another package. A component owns its
pixel math; the pipeline composes components and validates their order.
