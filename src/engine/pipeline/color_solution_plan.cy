// Headless color-solution plan validator v1. This is a logical contract only:
// it never interprets asset bytes or writes pixels. SHA-256 values are supplied
// by a caller that has verified immutable source and asset bytes.
pub enum ColorDomain: u32 {
    camera_linear = 1,
    scene_linear_rec2020_d65 = 2,
    view_rgb = 3,
    output_rgb = 4,
    encoded_srgb_d65 = 5,
}

pub enum ColorOperation: u32 {
    characterize = 1,
    chroma_map = 2,
    gradation = 3,
    output_transform = 4,
    scene_to_srgb_view = 5,
    srgb_view_gradation = 6,
}

// Public wire values retain their v1 identities for existing callers.
pub const CAMERA_LINEAR: u32 = 1;
pub const SCENE_LINEAR_REC2020_D65: u32 = 2;
pub const VIEW_RGB: u32 = 3;
pub const OUTPUT_RGB: u32 = 4;
// Encoded IEC sRGB with D65 primaries, normalized f32 samples in [0,1].
pub const ENCODED_SRGB_D65: u32 = 5;
pub const CHARACTERIZE: u32 = 1;
pub const CHROMA_MAP: u32 = 2;
pub const GRADATION: u32 = 3;
pub const OUTPUT_TRANSFORM: u32 = 4;
// Route v3 positions: a fixed three-kernel view conversion, then gradation.
pub const SCENE_TO_SRGB_VIEW: u32 = 5;
pub const SRGB_VIEW_GRADATION: u32 = 6;

pub struct Operation {
    pub slot: u32;
    pub algorithm_version: u32;
    pub input_domain: u32;
    pub output_domain: u32;
    pub asset_sha256: [32]u8;
    // Zero means source-independent. Otherwise the complete source profile
    // identity must match; a camera-specific asset cannot follow another RAW.
    pub source_profile_sha256: [32]u8;
}

pub struct Request {
    pub route_version: u32;
    pub source_sha256: [32]u8;
    pub source_profile_sha256: [32]u8;
    pub initial_domain: u32;
    pub branch_sha256: [32]u8;
    pub width: usize;
    pub height: usize;
    pub max_pixels: usize;
    pub operations: [:]Operation;
}

// An accepted snapshot pins the exact order and every supplied identity.
// The caller must retain verified immutable bytes for replay.
pub struct Plan {
    pub valid: bool;
    pub route_version: u32;
    pub source_sha256: [32]u8;
    pub source_profile_sha256: [32]u8;
    pub branch_sha256: [32]u8;
    pub width: usize;
    pub height: usize;
    pub count: usize;
    pub operations: [4]Operation;
}

fn zero(hash: [32]u8): bool {
    var index: usize = 0;
    while index < 32 {
        if hash[index] != 0 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn same(left: [32]u8, right: [32]u8): bool {
    var index: usize = 0;
    while index < 32 {
        if left[index] != right[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn empty(): Plan {
    const hash: [32]u8 = [0] ** 32;
    const operation: Operation = {
        slot: 0,
        algorithm_version: 0,
        input_domain: 0,
        output_domain: 0,
        asset_sha256: hash,
        source_profile_sha256: hash
    };
    return {
        valid: false,
        route_version: 0,
        source_sha256: hash,
        source_profile_sha256: hash,
        branch_sha256: hash,
        width: 0,
        height: 0,
        count: 0,
        operations: [operation] ** 4
    };
}

// Route v1 requires one characterization, optional scene chroma map and view
// gradation, and one output transform. A separate version is required to add
// slots or change their domain semantics. Returns an invalid plan on any error.
pub fn compile(request: &const Request): Plan {
    var rejected = empty();
    // Route v4 inserts one caller-supplied scene-linear Rec.2020/D65 chroma
    // map before the fixed view conversion and view-domain gradation.
    if request.route_version == 4 {
        if request.width == 0 or request.height == 0
        or request.width > request.max_pixels / request.height
        or request.width > 16777216 or request.height > 16777216 / request.width
        or zero(request.source_sha256) or zero(request.source_profile_sha256)
        or zero(request.branch_sha256)
        or request.initial_domain != SCENE_LINEAR_REC2020_D65
        or request.operations.len() != 3 {
            return rejected;
        }
        const chroma = request.operations[0];
        const conversion = request.operations[1];
        const gradation = request.operations[2];
        if chroma.slot != CHROMA_MAP or chroma.algorithm_version != 1
        or chroma.input_domain != SCENE_LINEAR_REC2020_D65
        or chroma.output_domain != SCENE_LINEAR_REC2020_D65
        or zero(chroma.asset_sha256) or not zero(chroma.source_profile_sha256)
        or conversion.slot != SCENE_TO_SRGB_VIEW
        or conversion.algorithm_version != 1
        or conversion.input_domain != SCENE_LINEAR_REC2020_D65
        or conversion.output_domain != ENCODED_SRGB_D65
        or not zero(conversion.asset_sha256)
        or not zero(conversion.source_profile_sha256)
        or gradation.slot != SRGB_VIEW_GRADATION
        or gradation.algorithm_version != 2
        or gradation.input_domain != ENCODED_SRGB_D65
        or gradation.output_domain != ENCODED_SRGB_D65
        or zero(gradation.asset_sha256)
        or not zero(gradation.source_profile_sha256) {
            return rejected;
        }
        rejected.valid = true;
        rejected.route_version = 4;
        rejected.source_sha256 = request.source_sha256;
        rejected.source_profile_sha256 = request.source_profile_sha256;
        rejected.branch_sha256 = request.branch_sha256;
        rejected.width = request.width;
        rejected.height = request.height;
        rejected.count = 3;
        rejected.operations[0] = chroma;
        rejected.operations[1] = conversion;
        rejected.operations[2] = gradation;
        return rejected;
    }
    // Route v3 starts from an already characterized scene-linear Rec.2020/D65
    // frame. Its conversion bundle v1 is matrix -> destination clip -> IEC
    // transfer, followed by the same digest-pinned gradation kernel as v2.
    if request.route_version == 3 {
        if request.width == 0 or request.height == 0
        or request.width > request.max_pixels / request.height
        or request.width > 16777216 or request.height > 16777216 / request.width
        or zero(request.source_sha256) or zero(request.source_profile_sha256)
        or zero(request.branch_sha256)
        or request.initial_domain != SCENE_LINEAR_REC2020_D65
        or request.operations.len() != 2 {
            return rejected;
        }
        const conversion = request.operations[0];
        const gradation = request.operations[1];
        if conversion.slot != SCENE_TO_SRGB_VIEW
        or conversion.algorithm_version != 1
        or conversion.input_domain != SCENE_LINEAR_REC2020_D65
        or conversion.output_domain != ENCODED_SRGB_D65
        or not zero(conversion.asset_sha256)
        or not zero(conversion.source_profile_sha256)
        or gradation.slot != SRGB_VIEW_GRADATION
        or gradation.algorithm_version != 2
        or gradation.input_domain != ENCODED_SRGB_D65
        or gradation.output_domain != ENCODED_SRGB_D65
        or zero(gradation.asset_sha256)
        or not zero(gradation.source_profile_sha256) {
            return rejected;
        }
        rejected.valid = true;
        rejected.route_version = 3;
        rejected.source_sha256 = request.source_sha256;
        rejected.source_profile_sha256 = request.source_profile_sha256;
        rejected.branch_sha256 = request.branch_sha256;
        rejected.width = request.width;
        rejected.height = request.height;
        rejected.count = 2;
        rejected.operations[0] = conversion;
        rejected.operations[1] = gradation;
        return rejected;
    }
    // Route v2 is the executable view-domain slice. It cannot claim a RAW
    // characterization: its source is already encoded sRGB/D65. The single
    // supported operation is the versioned independent RGB gradation kernel.
    if request.route_version == 2 {
        if request.width == 0 or request.height == 0
        or request.width > request.max_pixels / request.height
        or request.width > 16777216 or request.height > 16777216 / request.width
        or zero(request.source_sha256) or zero(request.branch_sha256)
        or request.initial_domain != ENCODED_SRGB_D65
        or request.operations.len() != 1 {
            return rejected;
        }
        const operation = request.operations[0];
        if operation.slot != GRADATION or operation.algorithm_version != 2
        or operation.input_domain != ENCODED_SRGB_D65
        or operation.output_domain != ENCODED_SRGB_D65
        or zero(operation.asset_sha256)
        or not zero(operation.source_profile_sha256)
        or not zero(request.source_profile_sha256) {
            return rejected;
        }
        rejected.valid = true;
        rejected.route_version = 2;
        rejected.source_sha256 = request.source_sha256;
        rejected.branch_sha256 = request.branch_sha256;
        rejected.width = request.width;
        rejected.height = request.height;
        rejected.count = 1;
        rejected.operations[0] = operation;
        return rejected;
    }
    if request.route_version != 1 or request.width == 0 or request.height == 0
    or request.width > request.max_pixels / request.height
    or zero(request.source_sha256) or zero(request.source_profile_sha256)
    or zero(request.branch_sha256) or request.initial_domain != ColorDomain.camera_linear as u32
    or request.operations.len() < 2 or request.operations.len() > 4 {
        return rejected;
    }
    var current = request.initial_domain;
    var previous: u32 = 0;
    var index: usize = 0;
    while index < request.operations.len() {
        const operation = request.operations[index];
        if operation.slot <= previous or operation.slot > OUTPUT_TRANSFORM
        or operation.algorithm_version == 0 or zero(operation.asset_sha256)
        or operation.input_domain != current
        or (not zero(operation.source_profile_sha256)
            and not same(operation.source_profile_sha256, request.source_profile_sha256)
        ) {
            return rejected;
        }
        if (operation.slot == ColorOperation.characterize as u32) {
            if index != 0 or operation.input_domain != CAMERA_LINEAR
            or operation.output_domain != SCENE_LINEAR_REC2020_D65
            or not same(operation.source_profile_sha256, request.source_profile_sha256) {
                return rejected;
            }
        } else if (operation.slot == ColorOperation.chroma_map as u32) {
            if (current != SCENE_LINEAR_REC2020_D65
                or operation.output_domain != SCENE_LINEAR_REC2020_D65
            ) {
                return rejected;
            }
        } else if (operation.slot == ColorOperation.gradation as u32) {
            if (current != SCENE_LINEAR_REC2020_D65
                or operation.output_domain != VIEW_RGB
            ) {
                return rejected;
            }
        } else {
            if (index + 1 != request.operations.len() or operation.output_domain != OUTPUT_RGB
                or (current != SCENE_LINEAR_REC2020_D65 and current != VIEW_RGB)
            ) {
                return rejected;
            }
        }
        rejected.operations[index] = operation;
        current = operation.output_domain;
        previous = operation.slot;
        index = index + 1;
    }
    if (previous != OUTPUT_TRANSFORM) {
        return empty();
    }
    rejected.valid = true;
    rejected.route_version = request.route_version;
    rejected.source_sha256 = request.source_sha256;
    rejected.source_profile_sha256 = request.source_profile_sha256;
    rejected.branch_sha256 = request.branch_sha256;
    rejected.width = request.width;
    rejected.height = request.height;
    rejected.count = request.operations.len();
    return rejected;
}

pub fn matches(plan: Plan, request: &const Request): bool {
    const fresh = compile(request);
    if not plan.valid or not fresh.valid or plan.route_version != fresh.route_version
    or plan.width != fresh.width or plan.height != fresh.height
    or plan.count != fresh.count or not same(plan.source_sha256, fresh.source_sha256)
    or not same(plan.source_profile_sha256, fresh.source_profile_sha256)
    or not same(plan.branch_sha256, fresh.branch_sha256) {
        return false;
    }
    var index: usize = 0;
    while index < plan.count {
        const left = plan.operations[index];
        const right = fresh.operations[index];
        if left.slot != right.slot or left.algorithm_version != right.algorithm_version
        or left.input_domain != right.input_domain or left.output_domain != right.output_domain
        or not same(left.asset_sha256, right.asset_sha256)
        or not same(left.source_profile_sha256, right.source_profile_sha256) {
            return false;
        }
        index = index + 1;
    }
    return true;
}
