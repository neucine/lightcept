# Lightcept terminology

This is the canonical vocabulary for current Lightcept documentation, public
contracts, and new code names. A definition describes meaning, not delivery
status. Consult the execution plan and qualification index in the private
`neucine/daydream` repository under `projects/lightcept/` before claiming a
term's full workflow is implemented or a source is supported. Existing API
identifiers can retain their names until a deliberate migration; use these
meanings when documenting them.

## Product and edit state

| Term | Definition and usage |
| --- | --- |
| **Source photograph** | The immutable input bytes selected by a person. Decode, previews, edits, and exports must not rewrite them. Use **source** only when the input identity and its scope are clear. |
| **Source variant** | A specific camera, container, compression, sensor layout, and metadata combination that needs its own support evidence. A decoder accepting a file does not establish support for every variant of that format. |
| **Document** | One editor session's source, committed edit state, workflow state, and displayed frame. A Neiv window owns a bounded document slot; a saved project is a separate durable representation. |
| **Project** | The durable product record that replays accepted edits against an identified source. Neiv saves versioned recipes for qualified RAW previews and verifies the source identity before reopening. |
| **Edit request** | A proposed change from a manual control or interpreted intent, expressed in typed product terms. It has no pixel effect until validated and accepted. |
| **Semantic edit recipe** | Portable accepted control values, masks, resolved automatic values, and asset references. It describes *what* the edit means, without engine nodes, cache keys, or device choices. **Recipe** is acceptable after this meaning is established. |
| **Edit history** | The sequence of accepted state changes used for Undo and redo. Submission order is not photographic processing order. A **history revision** identifies a state in that sequence. |
| **Render contract** | The product's pinned source, profile, route, edit, and output identity needed to reproduce an accepted look or return a typed replay failure. Saved projects record this identity for qualified routes. |

## Image data and color domains

A typical RAW path is **container parsing → sensor decode → normalization →
sensor corrections → demosaic → camera color and white balance → scene-linear
working RGB → develop → view/output transform → encoded pixels**. A route may
place a particular operation elsewhere when its versioned contract says so.
The arrows name changes in data meaning; they do not imply every operation is
present in every current route.

| Term | Definition and usage |
| --- | --- |
| **Sensor codes** | Stored, camera-native sample values before black-level correction and normalization. Attach the source bit depth, black and white references, and layout. |
| **Normalized camera mosaic** | CFA samples after format-specific normalization, with a stated scale and preserved highlight headroom. It is still a mosaic, not RGB. `CameraMosaic` is the checked Cyna metadata and caller-owned camera-linear Bayer sample handoff; specify its sample type and geometry at the API. |
| **Camera-linear RGB** | Demosaiced RGB whose samples remain linear with scene light in the camera's characterized channel basis. It precedes the conversion to the declared working primaries and white point. |
| **Scene-linear working RGB** | RGB linear with scene light in explicit working primaries and white point. Current prepared preview work uses Rec.2020/D65; signed values and values above one are valid where the stage contract allows them. **Working frame** means a typed image buffer in this domain with declared geometry, precision, scale, and provenance. |
| **View-referred RGB** | RGB after a declared viewing or tone transformation for a display or proof condition. It is distinct from scene-linear working RGB. |
| **Output-ready pixels** | Samples after the declared output color, transfer, gamut, and quantization decisions, ready for display publication or file encoding. Name the format, such as opaque RGBA8 sRGB or RGB16, at the boundary. |
| **Preview** | A render intended for interactive review under a declared size, quality, and output policy. The word does not identify an image domain or a distinct pixel kernel. An **export** is an output request for a file destination; both should derive from the same resolved photographic plan with explicit output branches when that target is implemented. |

## RAW and ISP operations

**ISP** means image signal processing: the operations that turn sensor data
into an image suitable for photographic editing and output. In this repository,
the **RAW engine** includes those operations plus develop, analysis, and output
components. A RAW file is a container and set of encoded samples, not an RGB
image or a single uniform format.

| Term | Plain meaning and Lightcept usage |
| --- | --- |
| **Container parsing** | Read file structure and metadata, such as TIFF/DNG tags or NEF records, with bounds checks. Parsing locates encoded samples and source facts; it does not reconstruct final pixels. |
| **Sensor decode** | Decompress or unpack stored sensor samples into sensor codes. **Decode** without a qualifier can refer to the whole RAW ingest path, so name the narrower step when its boundary matters. |
| **Black level / white level** | Per-source sensor references: black level is the code corresponding to no useful light; white level is the declared saturation reference. Neither is the edit control **Blacks** or **Whites**, and white level is not the display white point. |
| **Active area / default crop / user crop** | The active area excludes stored sensor borders that are not intended as image pixels. A format's default crop selects its intended image region; a user crop is an accepted edit on the rendered image. Record their coordinate systems separately. |
| **Normalization** | Apply the declared black and white references and source calibration to express samples on a camera-linear scale. State the scale and headroom policy; normalization is not clipping every value to [0, 1]. |
| **CFA / Bayer mosaic** | A color filter array (CFA) records one filtered sample at each sensor site. Bayer is one CFA arrangement; do not call every RAW layout Bayer. **Mosaic** means these single-channel sites before RGB reconstruction. |
| **Demosaic** | Estimate missing color channels at CFA sites to form camera-linear RGB. The selected algorithm and its edge behavior are part of the route's pixel semantics. |
| **Sensor correction** | A named operation on sensor or mosaic data, such as defect handling, lens shading, chromatic aberration correction, or mosaic-domain noise reduction. Specify the operation and domain rather than using this umbrella term as a stage name. |
| **Highlight reconstruction** | Estimate information in clipped or partly clipped regions using declared sensor or image evidence. It is distinct from the **Highlights** develop control, which changes tonal appearance of existing working RGB. Reconstruction cannot recover information absent from every relevant channel. |
| **Camera characterization / profile** | Measured or specified mapping from camera channel responses toward a known color space. A **camera profile** is an identified characterization asset or metadata interpretation, not a display ICC profile. Name the format and transform when a generic **profile** would be ambiguous. |
| **White balance** | Correct the color cast of the capture illuminant relative to a chosen neutral. Camera as-shot neutral, sensor multipliers, and working-RGB gains are different representations; name which one an API accepts. **White point** is a color-space reference, such as D65, unless a specific edit control is named. |
| **Sampled White Point control** | Lightcept's named develop operation that samples a chosen image patch and derives working-RGB gains toward a target neutral. It does not redefine Rec.2020/D65 or the sensor white level. Use the full control name when distinguishing it from a color-space white point. |
| **Exposure** | A scene-linear brightness adjustment measured in stops or EV; +1 EV multiplies linear values by two. Camera baseline exposure and user exposure are separate inputs even when a kernel combines them. Exposure is not a display brightness adjustment. |
| **Baseline exposure / user exposure** | Baseline exposure is a source or route calibration offset that defines the neutral rendering reference. User exposure is the requested photographic edit relative to that reference. Name both values and their units when an API combines them. |
| **Reference white / display white / sensor white level** | Reference white is the numeric scale anchor for a linear image contract, often 1. Display white describes a viewing or output luminance and color condition. Sensor white level is a source code threshold. None alone specifies the other two. |
| **Tone / tonal adjustment** | A mapping of brightness relationships, including Blacks, Shadows, Contrast, Highlights, Whites, and curves. Name the specific control and its range; a **tone map** may also mean the view transform, so do not use it alone for both. |
| **Black point / Blacks control** | Black point is a declared tonal anchor or offset in an image domain. The **Blacks** control adjusts the dark tonal region under its versioned stage contract. Neither is the sensor black level used during normalization. |
| **Chroma / saturation / vibrance** | Chroma describes distance from neutral in a stated color model. Saturation is a particular measure or edit of colorfulness; vibrance is a selective adjustment with its own algorithm. Their controls are not interchangeable, and each needs its declared color model and bounds. |
| **RAW denoise / image denoise** | Noise reduction before demosaic on CFA samples versus after demosaic on RGB pixels. Specify the domain, model, detail-loss policy, and scale; generic **denoise** does not identify a stage. |
| **Sharpening / texture / clarity** | Sharpening emphasizes fine edges, texture targets local fine detail, and clarity changes broader local contrast. They differ in spatial scale and halo behavior; a shared **detail** heading does not make them the same operation. |
| **Orientation / crop / warp** | Orientation maps the source's recorded rotate/flip state; crop selects an output region; a warp resamples geometry for lens, perspective, or straighten correction. Each has distinct coordinates and mask-mapping consequences. |
| **Gamut mapping / clipping** | Gamut mapping handles colors outside a destination's reproducible range under a declared policy. Clipping clamps values to a bound and can discard color or highlight detail. State which operation occurs and in which color space. |
| **Transfer encoding / quantization** | Transfer encoding maps linear or view-referred values to a destination code curve such as sRGB. Quantization rounds them to a finite integer precision such as 8 or 16 bits. Neither is camera color conversion. |
| **Histogram / clipping map** | A histogram counts samples in bins for a stated image domain and channel definition. A clipping map marks samples meeting a declared clipping condition. A histogram of RGBA8 preview pixels cannot prove sensor clipping. |
| **Resampling / resizing** | Resampling computes samples on a new pixel grid, for example when fitting a preview or applying a warp. Resizing is the geometry change requested by a caller; state the filter, source and destination coordinates, and edge rule at a pixel boundary. |

## Processing and evidence

| Term | Definition and usage |
| --- | --- |
| **Stage** | A versioned operation with explicit input and output domains, parameters, units, bounds, errors, cancellation, and algorithm behavior. The owning component implements its pixel math. |
| **Route policy** | A versioned source route template fixing photographic stage slots, domain transitions, observation taps, and output branches. A **render mode** is a current pipeline selection for a specific reconstruction or preview path; it is not by itself the complete route policy. |
| **Photographic plan** | The validated, ordered pixel-affecting stages and resolved parameters for one source, recipe, route policy, and output branch. Its order is independent of edit history. Current routes have fixed compositions; the general plan builder is a target design. |
| **Execution plan** | Choices for tiles, caches, fusion, precision, CPU or GPU implementation, and scheduling that execute a photographic plan within a declared equivalence policy. This term also appears in the title of a delivery document; that document is a roadmap, not an instance of this data structure. |
| **Analysis observation** | Immutable measured evidence from a named image domain, route tap, region, scale, and producer version. A display-encoded histogram is an observation of the displayed preview, not of scene-linear exposure or sensor clipping. |
| **Automatic proposal** | A suggested edit value resolved from a named observation and explicit baseline. The concrete value and evidence identity must be accepted and pinned for replay; analysis alone does not change pixels. |
| **Mask** | Coverage or selection data with explicit coordinate system, extent, sample range, and provenance. **Semantic mask** describes portable intent; **raster mask** describes the aligned samples consumed by a pixel stage. A crop or warp must map or invalidate dependent masks. |
| **Candidate frame** | A completed render awaiting the document's current window, generation, and revision checks. **Committed frame** is the frame that passed those checks and is published. Failed, cancelled, or stale renders do not become committed frames. |
| **Qualified** | Backed by the evidence required for a specifically named stage, source variant, route, or product behavior. Always state the scope. **Supported source variant** means the full RAW support closure in `projects/lightcept/qualification/raw-support-closure.md` has been met; a diagnostic kernel or candidate route does not imply that status. |

## Naming rules

- Name image values by domain and representation when a boundary could be
  ambiguous: `camera_mosaic`, `scene_linear_working_rgb`, or `rgba8_srgb`.
  Document primaries, white point, transfer, scale, precision, geometry, and
  valid range alongside public image buffers.
- Use **decode** for reading stored data, **normalize** for mapping sensor codes
  into camera-linear samples, **demosaic** for reconstructing RGB, **develop**
  for photographic adjustments, **render** for producing destination pixels,
  and **publish** for making a completed frame visible.
- Distinguish **contract**, **implemented kernel**, **qualified route**, and
  **product support** in status claims. Give the exact source variant and route
  when reporting qualification.
- Preserve established identifiers in existing code until their callers and
  persisted meanings can be migrated together. New names should follow this
  glossary; document an unavoidable legacy alias at its boundary.

## Terms that are easily conflated

| Write this when you mean… | Avoid relying on… | Distinction |
| --- | --- | --- |
| **Sensor decode**, **RAW ingest**, or **demosaic** | **Decode** alone | Unpacking codes, preparing a camera mosaic, and reconstructing RGB are different steps. |
| **Sensor black/white level**, **Blacks/Whites control**, or **color-space white point** | **Black** or **white** alone | Sensor calibration, tonal edits, and color references have different units and owners. |
| **Sampled White Point control** | **White point** alone when discussing edits | The control changes working-RGB gains; a color-space white point identifies a color reference such as D65. |
| **Camera profile**, **working color space**, or **output ICC profile** | **Profile** alone | They describe different transforms or destinations. |
| **Scene-linear working frame**, **view-referred image**, or **RGBA8 preview** | **Image/frame** alone at an API boundary | Domain and representation determine valid operations. |
| **Photographic stage order**, **edit history**, or **execution schedule** | **Order** alone | Processing semantics, user event sequence, and computation scheduling are independent. |
| **Preview render**, **candidate frame**, or **committed frame** | **Preview** alone when discussing publication | Rendering, awaiting validation, and becoming visible are separate events. |
| **Implemented kernel**, **qualified route**, or **supported source variant** | **Supported** alone | Unit behavior, route evidence, and product acceptance have different evidence thresholds. |
