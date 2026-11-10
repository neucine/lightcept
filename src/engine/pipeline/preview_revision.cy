import .engine.pipeline.preview_develop_plan;
import .engine.pipeline.develop_replay;

// Fixed photographic route v1. The caller verifies these SHA-256 identities
// against immutable source bytes and the prepared working-frame contract.
pub enum PreviewRoute: u32 {
    dng_spatial = 1,
    nef_z8_lossless = 2,
}
pub const DNG_SPATIAL: u32 = 1;
pub const NEF_Z8_LOSSLESS: u32 = 2;

pub struct Revision {
    pub sequence: u64;
    pub route: u32;
    pub source: develop_replay.WorkingSourceIdentity;
    pub baseline_exposure_ev: f64;
    pub controls: preview_develop_plan.Controls;
}

pub fn valid(revision: Revision): bool {
    return (revision.route == PreviewRoute.dng_spatial as u32 or revision.route == PreviewRoute.nef_z8_lossless as u32)
    and develop_replay.valid_source(revision.source)
    and revision.source.width <= 2048 and revision.source.height <= 2048
    and revision.baseline_exposure_ev >= -16.0 and revision.baseline_exposure_ev <= 16.0
    and preview_develop_plan.valid(revision.controls);
}

// Only the six fixed develop slots are admitted. Crop has no v1 slot.
pub fn set_exposure(parent: Revision, next_sequence: u64, tenths: i32): Revision {
    var next = parent;
    next.sequence = next_sequence;
    next.controls.exposure_tenths = tenths;
    return next;
}

pub fn valid_child(parent: Revision, child: Revision): bool {
    return valid(parent) and valid(child) and child.sequence == parent.sequence + 1
    and child.route == parent.route
    and child.source.version == parent.source.version
    and child.source.width == parent.source.width and child.source.height == parent.source.height
    and child.source.domain == parent.source.domain
    and child.baseline_exposure_ev == parent.baseline_exposure_ev
    and same_source(parent.source, child.source);
}

fn same_source(left: develop_replay.WorkingSourceIdentity, right: develop_replay.WorkingSourceIdentity): bool {
    if left.version != right.version or left.width != right.width or left.height != right.height
    or left.domain != right.domain {
        return false;
    }
    var index: usize = 0;
    while index < 32 {
        if left.source_sha256[index] != right.source_sha256[index]
        or left.working_contract_sha256[index] != right.working_contract_sha256[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn same_controls(left: preview_develop_plan.Controls, right: preview_develop_plan.Controls): bool {
    return left.exposure_tenths == right.exposure_tenths
    and left.contrast_percent == right.contrast_percent
    and left.shadows_percent == right.shadows_percent
    and left.highlights_percent == right.highlights_percent
    and left.blacks_percent == right.blacks_percent
    and left.whites_percent == right.whites_percent
    and left.warmth_percent == right.warmth_percent
    and left.tint_percent == right.tint_percent
    and left.vibrance_percent == right.vibrance_percent
    and left.saturation_percent == right.saturation_percent
    and left.clarity_percent == right.clarity_percent;
}

// Status 8 is a replay identity mismatch. Output is untouched on rejection.
pub fn render_pinned(pin: Revision, current: Revision, working: *const f64,
    working_length: usize, output: *u8, output_length: usize,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not valid(pin) or not valid(current) or pin.route != current.route
    or not same_source(pin.source, current.source)
    or pin.baseline_exposure_ev != current.baseline_exposure_ev
    or not same_controls(pin.controls, current.controls) {
        return 8;
    }
    return preview_develop_plan.render(working, working_length, output, output_length,
        pin.source.width as usize, pin.source.height as usize,
        pin.baseline_exposure_ev, pin.controls, cancelled, context
    );
}
