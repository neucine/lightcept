// The typed, versioned develop-stage contract.
//
// Cyna owns this table: which develop capabilities the product declares, what each stage does to
// the domain ladder, which stages this build composes for a characterised source, in what plan
// position, and which semantic develop controls a composed stage actually drives. The product caller
// reads the report; it never writes a stage name, an order, or an executability flag.
//
// `status` says how far a stage definition is pinned, `executable` says whether this build composes
// it, and `edit_driven` says whether its parameters come from develop edits. A stage may be
// declared without being executable, and executable without being edit driven.

const stage_contract_version: u32 = 2;
const stage_name_bytes: usize = 24;
const stage_descriptor_bytes: usize = 192;
const max_declared_stages: usize = 64;
const driven_controls_bytes: usize = 64;
const aux_ports_bytes: usize = 48;

// The serialized report keeps these exact codes. Constructors use finite
// choices so a stage kind cannot be passed as a domain or maturity status.
pub enum StageKind: u32 {
    pointwise = 1,
    tonal_map = 2,
    chromatic_map = 3,
    banded_map = 4,
    linear_transform = 5,
    neighbourhood = 6,
    field = 7,
    region = 8,
    domain_conversion = 9,
    branch = 10,
    composite = 11,
    analysis = 12,
}
pub enum ImageDomain: u32 {
    sensor_codes = 1,
    normalized_mosaic = 2,
    camera_linear_rgb = 3,
    scene_linear_rgb = 4,
    view_referred_rgb = 5,
    output_ready = 6,
    linear_srgb = 7,
    encoded_srgb = 8,
}
pub enum StageMaturity: u32 {
    contract = 1,
    pinned = 2,
    native = 3,
    qualified = 4,
    promoted = 5,
}

const scope_global: u32 = 1;
const scope_local: u32 = 2;
const edit_driven: u32 = 1;
const fixed_parameters: u32 = 0;
const stage_absent: u32 = 0;
const stage_composed: u32 = 1;

// Value modes a composed stage accepts for the controls it drives: bit 0 delta, bit 1 target.
// A host may apply a control only in a mode this manifest admits.
const modes_none: u32 = 0;
const modes_delta: u32 = 1;
const modes_delta_target: u32 = 3;

pub struct StageContractEntry {
    pub name: string;
    pub kind: u32;
    pub input: u32;
    pub output: u32;
    pub status: u32;
    pub algorithm_version: u32;
    pub executable: u32;
    pub edit_driven: u32;
    pub scopes: u32;
    pub plan_position: u32;
    pub driven_controls: string;
    pub aux_ports: string;
    pub admitted_modes: u32;
}

fn empty_entry(): StageContractEntry {
    return {
        name: "",
        kind: 0,
        input: 0,
        output: 0,
        status: 0,
        algorithm_version: 0,
        executable: 0,
        edit_driven: 0,
        scopes: 0,
        plan_position: 0,
        driven_controls: "",
        aux_ports: "",
        admitted_modes: 0
    };
}

// A capability the contract declares but this build does not yet compose.
fn declared_stage(name: string, kind: StageKind, input: ImageDomain, output: ImageDomain, status: StageMaturity, aux_ports: string): StageContractEntry {
    return {
        name: name,
        kind: kind as u32,
        input: input as u32,
        output: output as u32,
        status: status as u32,
        algorithm_version: 0,
        executable: stage_absent,
        edit_driven: fixed_parameters,
        scopes: 0,
        plan_position: 0,
        driven_controls: "",
        aux_ports: aux_ports,
        admitted_modes: modes_none
    };
}

// A stage this build composes for the characterised source. `controls` names the develop controls
// whose values drive the stage; an empty list means the stage runs with fixed neutral parameters,
// so its control is declared but not yet executable.
fn composed_stage(
    name: string,
    kind: StageKind,
    input: ImageDomain,
    output: ImageDomain,
    status: StageMaturity,
    version: u32,
    scopes: u32,
    drives: u32,
    controls: string,
    aux_ports: string,
    modes: u32,
    position: u32
): StageContractEntry {
    return {
        name: name,
        kind: kind as u32,
        input: input as u32,
        output: output as u32,
        status: status as u32,
        algorithm_version: version,
        executable: stage_composed,
        edit_driven: drives,
        scopes: scopes,
        plan_position: position,
        driven_controls: controls,
        aux_ports: aux_ports,
        admitted_modes: modes
    };
}

// Every develop capability the contract declares. Deferring a kernel is allowed; deleting a
// declaration is not.
pub fn declared_stages(): [:]StageContractEntry {
    return [
        // Capture colour.
        declared_stage("exposure", StageKind.pointwise, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.promoted, "camera baseline exposure"),
        declared_stage("working_white", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, "camera color matrix"),
        declared_stage("white_point", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "sampled region evidence"),
        declared_stage("profile", StageKind.domain_conversion, ImageDomain.camera_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "profile asset"),

        // Tone group, in the order the plan policy declares.
        declared_stage("blacks", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "declared black pivot"),
        declared_stage("shadows", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "declared shadow threshold"),
        declared_stage("contrast", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, ""),
        declared_stage("highlights", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "clip map"),
        declared_stage("whites", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "clip map,white reference"),
        declared_stage("tone_curve", StageKind.tonal_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "curve asset"),
        declared_stage("auto_tone", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "histogram,clip map"),
        declared_stage("auto_white_balance", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "camera color matrix"),

        // Colour group. `linear_chroma` composes today but is not driven by an edit yet.
        declared_stage("linear_chroma", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, ""),
        declared_stage("vibrance", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "luminance rule"),
        declared_stage("hue", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "declared hue axis"),
        declared_stage("local_chroma", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "mask weight rule"),
        declared_stage("luminance_bands", StageKind.banded_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "band definition"),
        declared_stage("hsl_grading", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "grading asset"),
        declared_stage("channel_mixer", StageKind.linear_transform, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "matrix asset"),
        declared_stage("gamut_map", StageKind.branch, ImageDomain.scene_linear_rgb, ImageDomain.output_ready, StageMaturity.contract, "rendering intent"),

        // Detail and atmosphere. Each kernel declares its own domain, halo, and boundary rule.
        declared_stage("raw_denoise", StageKind.neighbourhood, ImageDomain.normalized_mosaic, ImageDomain.normalized_mosaic, StageMaturity.contract, "sensor noise model,CFA phase"),
        declared_stage("image_denoise", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "noise model"),
        declared_stage("capture_sharpening", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "kernel radius"),
        declared_stage("clarity", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "declared frequency band"),
        declared_stage("texture", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "detail band"),
        declared_stage("defringe", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "CFA phase"),
        declared_stage("moire", StageKind.neighbourhood, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "CFA frequency"),
        declared_stage("dehaze", StageKind.field, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "haze estimate,clip map"),
        declared_stage("grain", StageKind.pointwise, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "declared seed"),
        declared_stage("highlight_reconstruct", StageKind.neighbourhood, ImageDomain.normalized_mosaic, ImageDomain.normalized_mosaic, StageMaturity.contract, "clip map"),

        // Geometry and optics. A stage that moves pixel coordinates invalidates masks and analysis.
        declared_stage("orientation", StageKind.region, ImageDomain.sensor_codes, ImageDomain.sensor_codes, StageMaturity.native, ""),
        declared_stage("crop", StageKind.region, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "mask remapping"),
        declared_stage("straighten", StageKind.region, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "mask remapping,boundary fill"),
        declared_stage("perspective", StageKind.region, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "control points,mask remapping"),
        declared_stage("lens_distortion", StageKind.region, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "lens model asset"),
        declared_stage("vignetting", StageKind.field, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "lens model asset"),
        declared_stage("tca", StageKind.region, ImageDomain.normalized_mosaic, ImageDomain.normalized_mosaic, StageMaturity.contract, "lens model asset"),

        // Mask operands and masked adjustment.
        declared_stage("mask_geometry", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "source geometry"),
        declared_stage("sky_mask", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "scene content"),
        declared_stage("described_mask", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "mask geometry"),
        declared_stage("linear_gradient", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "gradient endpoints"),
        declared_stage("brush", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "stroke history"),
        declared_stage("range_mask", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "selection bounds"),
        declared_stage("local_adjust", StageKind.composite, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "base stage,mask weight rule"),

        // Output branch. Each branch carries its own identity.
        declared_stage("view_transform", StageKind.branch, ImageDomain.scene_linear_rgb, ImageDomain.view_referred_rgb, StageMaturity.contract, "reference display"),
        declared_stage("proof_transform", StageKind.branch, ImageDomain.view_referred_rgb, ImageDomain.output_ready, StageMaturity.contract, "destination profile,rendering intent"),
        declared_stage("output_transform", StageKind.branch, ImageDomain.scene_linear_rgb, ImageDomain.output_ready, StageMaturity.native, ""),
        declared_stage("working_to_linear_srgb", StageKind.domain_conversion, ImageDomain.scene_linear_rgb, ImageDomain.linear_srgb, StageMaturity.native, ""),
        declared_stage("srgb_clip", StageKind.pointwise, ImageDomain.linear_srgb, ImageDomain.linear_srgb, StageMaturity.native, ""),
        declared_stage("srgb_transfer", StageKind.domain_conversion, ImageDomain.linear_srgb, ImageDomain.encoded_srgb, StageMaturity.native, ""),
        declared_stage("output_quantize", StageKind.domain_conversion, ImageDomain.encoded_srgb, ImageDomain.output_ready, StageMaturity.native, "precision policy"),
        declared_stage("output_profile", StageKind.branch, ImageDomain.output_ready, ImageDomain.output_ready, StageMaturity.native, "icc asset"),
        declared_stage("precision_class", StageKind.branch, ImageDomain.output_ready, ImageDomain.output_ready, StageMaturity.native, "precision policy"),

        // Analysis stages feed auxiliary values and never write pixels.
        declared_stage("histogram", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, ""),
        declared_stage("clip_map", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "white reference"),
        declared_stage("region_statistics", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "region geometry"),
        declared_stage("noise_estimate", StageKind.analysis, ImageDomain.normalized_mosaic, ImageDomain.normalized_mosaic, StageMaturity.contract, "CFA phase"),
        declared_stage("sharpness_estimate", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "kernel radius"),
        declared_stage("color_cast", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.contract, "camera color matrix"),
        declared_stage("gamut_report", StageKind.analysis, ImageDomain.scene_linear_rgb, ImageDomain.output_ready, StageMaturity.contract, "destination gamut")
    ];
}

// Which declared stages this build composes for one characterised source, in plan order. Exposure
// and the output transform always compose. The working-white stage composes only when the source
// carries a camera color matrix and the pinned review permits a white balance other than as-shot.
// No composed stage accepts a masked local application yet, so none reports the local scope bit.
pub fn composed_stages(has_camera_matrix: bool, editable_white_balance: bool): [:]StageContractEntry {
    var stages: [:]StageContractEntry = [
        composed_stage("exposure", StageKind.pointwise, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.promoted, 1, scope_global, edit_driven, "exposure", "camera baseline exposure", modes_delta, 1)
    ];
    var position: u32 = 1;
    if has_camera_matrix and editable_white_balance {
        position = position + 1;
        stages.push(composed_stage("working_white", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, 1, scope_global, edit_driven, "temp,tint", "camera color matrix", modes_delta_target, position));
    }
    // The chroma stage composes with the fixed neutral value, so saturation is declared but the
    // stage is not driven by an edit yet.
    position = position + 1;
    stages.push(composed_stage("linear_chroma", StageKind.chromatic_map, ImageDomain.scene_linear_rgb, ImageDomain.scene_linear_rgb, StageMaturity.native, 1, scope_global, fixed_parameters, "", "", modes_none, position));
    position = position + 1;
    stages.push(composed_stage("output_transform", StageKind.branch, ImageDomain.scene_linear_rgb, ImageDomain.output_ready, StageMaturity.native, 1, scope_global, fixed_parameters, "", "", modes_none, position));
    return stages;
}

// Mask operands the composed plan accepts: bit 0 sky, bit 1 described, bit 2 linear gradient.
// No composed native stage applies a mask yet, so this reports zero.
pub fn composed_mask_operands(): u32 {
    return 0;
}

// The full contract for one source: every declared row, with composed rows replaced by their
// executable description.
pub fn stage_contract(has_camera_matrix: bool, editable_white_balance: bool): [:]StageContractEntry {
    var stages: [:]StageContractEntry = declared_stages();
    const composed = composed_stages(has_camera_matrix, editable_white_balance);
    var index: usize = 0;
    while index < stages.len() {
        var found: usize = 0;
        while found < composed.len() {
            if composed[found].name == stages[index].name {
                stages[index] = composed[found];
                found = composed.len();
            } else {
                found = found + 1;
            }
        }
        index = index + 1;
    }
    return stages;
}

// Bounded little-endian field writers shared by the contract reports in this package.
pub fn write_padded(base: usize, offset: usize, text: string, width: usize): void {
    const bytes: []const u8 = text.bytes();
    var position: usize = 0;
    while position < width {
        var byte: u8 = 0;
        if position < bytes.len() {
            byte = bytes[position];
        }
        unchecked {
            *((base + offset + position) as! *u8) = byte as u8;
        }
        position = position + 1;
    }
}

pub fn write_number(base: usize, offset: usize, value: u32): void {
    unchecked {
        *((base + offset) as! *u32) = value as u32;
    }
}

// One stage contract entry in a fixed 192-byte descriptor: 24 bytes of NUL-padded stage name, then
// algorithm version, kind, input domain, output domain, status, executable, edit-driven, scope bits,
// plan position, a 64-byte comma-separated list of controls the stage drives, a 48-byte comma
// separated list of auxiliary ports, the 4-byte mode-admission bitmask, and 12 reserved zero bytes.
fn write_descriptor(base: usize, index: usize, entry: StageContractEntry): void {
    const slot = base + index * stage_descriptor_bytes;
    write_padded(slot, 0, entry.name, stage_name_bytes);
    write_number(slot, 24, entry.algorithm_version);
    write_number(slot, 28, entry.kind);
    write_number(slot, 32, entry.input);
    write_number(slot, 36, entry.output);
    write_number(slot, 40, entry.status);
    write_number(slot, 44, entry.executable);
    write_number(slot, 48, entry.edit_driven);
    write_number(slot, 52, entry.scopes);
    write_number(slot, 56, entry.plan_position);
    write_padded(slot, 60, entry.driven_controls, driven_controls_bytes);
    write_padded(slot, 124, entry.aux_ports, aux_ports_bytes);
    write_number(slot, 172, entry.admitted_modes);
    var byte: usize = 176;
    while byte < stage_descriptor_bytes {
        unchecked {
            *((slot + byte) as! *u8) = 0;
        }
        byte = byte + 1;
    }
}

// Report the develop-stage contract for one characterised source. The host reads this manifest; it
// never writes it. Status: 0 success, 2 limit, 3 shape.
fn describe_stage_contract(
    has_camera_matrix: i32,
    editable_white_balance: i32,
    stages: *u8,
    stages_len: usize,
    stage_count: *u32,
    stage_count_len: usize,
    contract_version: *u32,
    contract_version_len: usize,
    mask_operands: *u32,
    mask_operands_len: usize
): i32 {
    if stages_len as usize != max_declared_stages * stage_descriptor_bytes
    or stage_count_len as usize != 1
    or contract_version_len as usize != 1
    or mask_operands_len as usize != 1 {
        return 3;
    }
    const entries = stage_contract(has_camera_matrix != 0, editable_white_balance != 0);
    if entries.len() > max_declared_stages {
        return 2;
    }
    var index: usize = 0;
    while index < max_declared_stages {
        if index < entries.len() {
            write_descriptor(stages as! usize, index, entries[index]);
        } else {
            write_descriptor(stages as! usize, index, empty_entry());
        }
        index = index + 1;
    }
    unchecked {
        *(stage_count as! *u32) = entries.len() as u32;
        *(contract_version as! *u32) = stage_contract_version as u32;
        *(mask_operands as! *u32) = composed_mask_operands() as u32;
    }
    return 0;
}
