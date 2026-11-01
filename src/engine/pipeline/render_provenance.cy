// The typed, versioned render-provenance table.
//
// Cyna owns the identity of a render pass: which stages run for a qualified source family, in what
// order, which algorithm and version each stage pins, and which stage carries an asset digest. The
// Rust host reads the report, computes the digests for the asset slots named here, and assembles the
// persisted render contract; it never names a stage, chooses an algorithm, or orders the pass.
// Stage names match the develop-stage contract in stage_manifest.cy so one stage keeps one identity.
import .engine.pipeline.stage_manifest;

const provenance_contract_version: u32 = 1;
pub const provenance_name_bytes: usize = 24;
pub const provenance_algorithm_bytes: usize = 64;
pub const provenance_descriptor_bytes: usize = provenance_name_bytes + provenance_algorithm_bytes + 8;
const max_provenance_rows: usize = 16;
const variant_label_bytes: usize = 48;

// Transport status codes: 0 success, 2 limit, 3 shape, 4 unknown selector.
const provenance_ok: u32 = 0;
const provenance_limit: u32 = 2;
const provenance_shape: u32 = 3;
const provenance_unknown_selector: u32 = 4;

// Asset slots. The table says which stage carries which asset; the host supplies the digest bytes.
const asset_none: u32 = 0;
const asset_pipeline_source: u32 = 1;
const asset_camera_profile: u32 = 2;
const asset_as_shot_neutral: u32 = 3;
const asset_output_profile: u32 = 4;
const asset_selected_white: u32 = 5;
const asset_working_plan: u32 = 6;

// Source families whose decode and characterization this build has qualified.
const family_dng_classic_le: u32 = 1;
const family_nef_z8: u32 = 2;

// Camera reconstruction choices, in the order the host's diagnostic API offers them.
const demosaic_bilinear: u32 = 1;
const demosaic_malvar_he_cutler: u32 = 2;
const demosaic_hamilton_adams: u32 = 3;

const highlight_none: u32 = 0;
const highlight_neutral_ratio: u32 = 1;
const highlight_saturated_neutral: u32 = 2;
const highlight_two_channel: u32 = 3;
const highlight_spatial: u32 = 4;
const highlight_spatial_headroom: u32 = 5;

// White-balance selection modes the qualified DNG decode path supports.
const white_balance_as_shot: u32 = 0;
const white_balance_temperature_tint: u32 = 1;

pub struct RenderProvenanceRow {
    pub stage: string;
    pub algorithm: string;
    pub version: u32;
    pub asset: u32;
}

fn row(stage: string, algorithm: string, version: u32, asset: u32): RenderProvenanceRow {
    return {
        stage: stage,
        algorithm: algorithm,
        version: version,
        asset: asset
    };
}

// The sensor stage keeps a different identity when the normalization retains the black-level
// headroom instead of subtracting it.
fn sensor_row(highlight: u32): RenderProvenanceRow {
    if highlight == highlight_spatial_headroom {
        return row("sensor", "dng-active-area-black-white-retained-headroom", 2, asset_none);
    }
    return row("sensor", "dng-active-area-black-white", 1, asset_none);
}

fn demosaic_row(demosaic: u32): RenderProvenanceRow {
    if demosaic == demosaic_bilinear {
        return row("demosaic", "bilinear-bayer", 1, asset_none);
    }
    if demosaic == demosaic_malvar_he_cutler {
        return row("demosaic", "malvar-he-cutler-bayer", 2, asset_none);
    }
    return row("demosaic", "hamilton-adams-bayer", 3, asset_none);
}

fn highlight_row(highlight: u32): RenderProvenanceRow {
    if highlight == highlight_neutral_ratio {
        return row("highlight", "neutral-ratio-single-channel", 1, asset_none);
    }
    if highlight == highlight_saturated_neutral {
        return row("highlight", "neutral-ratio-with-saturated-neutral", 2, asset_none);
    }
    if highlight == highlight_two_channel {
        return row("highlight", "neutral-ratio-with-two-channel-neutral", 3, asset_none);
    }
    return row("highlight", "spatial-camera-highlight-reconstruction", 4, asset_none);
}

// The as-shot neutral is used unless the caller selects a temperature and tint, which the core
// derives with the Bradford transform.
fn white_balance_row(white_balance: u32): RenderProvenanceRow {
    if white_balance == white_balance_temperature_tint {
        return row("white-balance", "kim-mired-duv-bradford", 2, asset_selected_white);
    }
    if white_balance == white_balance_as_shot {
        return row("white-balance", "dng-as-shot-neutral", 1, asset_as_shot_neutral);
    }
    return row("", "", 0, asset_none);
}

// The ordered identity of one render pass. An empty table means the family is not qualified.
pub fn render_provenance(family: u32, demosaic: u32, highlight: u32, white_balance: u32): [:]RenderProvenanceRow {
    // Each family qualifies the white-balance modes its decode path can actually execute.
    const white = white_balance_row(white_balance);
    if white.stage.len() == 0 or (family == family_nef_z8 and white_balance != white_balance_as_shot) {
        return [];
    }
    if family == family_dng_classic_le {
        var rows: [:]RenderProvenanceRow = [
            row("pipeline-source", "cyna-rust-pinned", 1, asset_pipeline_source),
            row("container", "classic-tiff-le-subifd", 1, asset_none),
            row("decode", "sof3-lossless-jpeg-two-component", 1, asset_none),
            sensor_row(highlight),
            demosaic_row(demosaic)
        ];
        if highlight != highlight_none {
            rows.push(highlight_row(highlight));
        }
        rows.push(row("profile", "dng-colormatrix-characterization", 1, asset_camera_profile));
        rows.push(white);
        rows.push(row("working", "xyz-d50-to-rec2020-d65", 1, asset_none));
        rows.push(row("exposure", "dng-default-plus-user-ev", 1, asset_none));
        rows.push(row("orientation", "tiff-visual", 1, asset_none));
        rows.push(row("resample", "working-linear-area", 1, asset_none));
        rows.push(row("output", "srgb2014-encoded", 1, asset_output_profile));
        return rows;
    }
    if family == family_nef_z8 {
        var rows: [:]RenderProvenanceRow = [
            row("pipeline-source", "cyna-rust-pinned", 1, asset_pipeline_source),
            row("container", "nikon-classic-tiff-le-subifd", 1, asset_none),
            row("decode", "nikon-lossless-huffman-predictor", 1, asset_none),
            row("sensor", "nikon-maker-note-crop-black-white", 1, asset_none),
            row("demosaic", "malvar-he-cutler-bayer", 2, asset_none),
            row("profile", "z8-libraw-reference-camera2rgb", 1, asset_camera_profile),
            row("white-balance", "nikon-maker-note-as-shot-rgb", 1, asset_as_shot_neutral),
            row("working", "xyz-d50-to-rec2020-d65", 1, asset_none),
            row("exposure", "user-ev", 1, asset_none),
            row("orientation", "tiff-visual", 1, asset_none),
            row("resample", "working-linear-area", 1, asset_none),
            row("output", "srgb2014-encoded", 1, asset_output_profile)
        ];
        return rows;
    }
    return [];
}

// Diagnostic staged contrast pass. The source-specific capture stages retain
// their identities, while the working stages follow their actual order after
// orientation and resampling. This table does not authorize product routing.
pub fn diagnostic_contrast_provenance(family: u32, demosaic: u32, highlight: u32, white_balance: u32): [:]RenderProvenanceRow {
    const base = render_provenance(family, demosaic, highlight, white_balance);
    if base.len() == 0 {
        return [];
    }
    var rows: [:]RenderProvenanceRow = [];
    rows.reserve(max_provenance_rows);
    var index: usize = 0;
    while index < base.len() {
        const current = base[index];
        if current.stage != "exposure" and current.stage != "output" {
            rows.push(current);
        }
        if current.stage == "resample" {
            if family == family_nef_z8 {
                rows.push(row("exposure", "user-ev", 1, asset_none));
            } else {
                rows.push(row("exposure", "dng-default-plus-user-ev", 1, asset_none));
            }
            rows.push(row("working-white", "rec2020-channel-gains", 1, asset_none));
            rows.push(row("contrast", "scene-linear-luminance-affine", 1, asset_working_plan));
            rows.push(row("linear-chroma", "rec2020-linear-chroma", 1, asset_none));
            rows.push(row("output", "srgb2014-encoded", 1, asset_output_profile));
        }
        index = index + 1;
    }
    return rows;
}

// The storage-variant label one render pass is pinned to. An empty label means this build has not
// qualified that family and bit depth, so the host must not claim a render contract for it.
pub fn storage_variant_label(family: u32, bits: u32): string {
    if family == family_dng_classic_le {
        if bits == 12 {
            return "dng/classic-le/sof3-bayer-12bit/v1";
        }
        if bits == 14 {
            return "dng/classic-le/sof3-bayer-14bit/v1";
        }
        if bits == 16 {
            return "dng/classic-le/sof3-bayer-16bit/v1";
        }
        return "";
    }
    if family == family_nef_z8 and bits == 14 {
        return "nef/nikon-z8/classic-le/lossless-bayer-14bit/v1";
    }
    return "";
}

// One row in its fixed descriptor: 24 bytes of NUL-padded stage name, 64 bytes of NUL-padded
// algorithm name, then the algorithm version and the asset slot.
fn write_row(base: usize, index: usize, entry: RenderProvenanceRow): void {
    const slot = base + index * provenance_descriptor_bytes;
    stage_manifest.write_padded(slot, 0, entry.stage, provenance_name_bytes);
    stage_manifest.write_padded(slot, provenance_name_bytes, entry.algorithm, provenance_algorithm_bytes);
    stage_manifest.write_number(slot, provenance_name_bytes + provenance_algorithm_bytes, entry.version);
    stage_manifest.write_number(slot, provenance_name_bytes + provenance_algorithm_bytes + 4, entry.asset);
}

// Report the render provenance for one qualified source family. Status codes are the transport
// codes above.
export c("lc_cyna_img_v1_describe_render_provenance") fn describe_render_provenance(
    family: c_int,
    demosaic: c_int,
    highlight: c_int,
    white_balance: c_int,
    bits: c_int,
    rows: *c_uchar,
    rows_len: c_size_t,
    row_count: *c_uint,
    row_count_len: c_size_t,
    variant: *c_uchar,
    variant_len: c_size_t,
    contract_version: *c_uint,
    contract_version_len: c_size_t
): c_int {
    if rows_len as usize != max_provenance_rows * provenance_descriptor_bytes
    or row_count_len as usize != 1
    or variant_len as usize != variant_label_bytes
    or contract_version_len as usize != 1 {
        return provenance_shape as c_int;
    }
    const entries = render_provenance(family as u32, demosaic as u32, highlight as u32, white_balance as u32);
    if entries.len() == 0 {
        return provenance_unknown_selector as c_int;
    }
    if entries.len() > max_provenance_rows {
        return provenance_limit as c_int;
    }
    const label = storage_variant_label(family as u32, bits as u32);
    if label.len() == 0 or label.len() > variant_label_bytes {
        return provenance_unknown_selector as c_int;
    }
    var index: usize = 0;
    while index < max_provenance_rows {
        if index < entries.len() {
            write_row(rows as! usize, index, entries[index]);
        } else {
            write_row(rows as! usize, index, row("", "", 0, 0));
        }
        index = index + 1;
    }
    stage_manifest.write_padded(variant as! usize, 0, label, variant_label_bytes);
    unchecked {
        *(row_count as! *c_uint) = entries.len() as c_uint;
        *(contract_version as! *c_uint) = provenance_contract_version as c_uint;
    }
    return provenance_ok as c_int;
}

// Separate report for the staged contrast candidate. The wire shape stays
// fixed but its contract version is 2 so it cannot alias the fused pass.
export c("lc_cyna_img_v1_describe_diagnostic_contrast_provenance") fn describe_diagnostic_contrast_provenance(
    family: c_int, demosaic: c_int, highlight: c_int, white_balance: c_int, bits: c_int,
    rows: *c_uchar, rows_len: c_size_t, row_count: *c_uint, row_count_len: c_size_t,
    variant: *c_uchar, variant_len: c_size_t, contract_version: *c_uint, contract_version_len: c_size_t
): c_int {
    if rows_len as usize != max_provenance_rows * provenance_descriptor_bytes
    or row_count_len as usize != 1 or variant_len as usize != variant_label_bytes
    or contract_version_len as usize != 1 {
        return provenance_shape as c_int;
    }
    const entries = diagnostic_contrast_provenance(family as u32, demosaic as u32, highlight as u32, white_balance as u32);
    if entries.len() == 0 {
        return provenance_unknown_selector as c_int;
    }
    if entries.len() > max_provenance_rows {
        return provenance_limit as c_int;
    }
    const label = storage_variant_label(family as u32, bits as u32);
    if label.len() == 0 or label.len() > variant_label_bytes {
        return provenance_unknown_selector as c_int;
    }
    var index: usize = 0;
    while index < max_provenance_rows {
        if index < entries.len() {
            write_row(rows as! usize, index, entries[index]);
        } else {
            write_row(rows as! usize, index, row("", "", 0, 0));
        }
        index = index + 1;
    }
    stage_manifest.write_padded(variant as! usize, 0, label, variant_label_bytes);
    unchecked {
        *(row_count as! *c_uint) = entries.len() as c_uint;
        *(contract_version as! *c_uint) = 2;
    }
    return provenance_ok as c_int;
}
