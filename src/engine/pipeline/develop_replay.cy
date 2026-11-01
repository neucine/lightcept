import .engine.develop.edit_plan;
import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;
import .engine.develop.asset_identity;
import .engine.pipeline.develop_sample;

// Exact in-memory plan+asset replay pin. Source identity and persistence are
// intentionally separate contracts. No digest collision is involved here.
pub struct PlanKey {
    pub version: u32;
    pub exposure_ev: u64;
    pub black_offset: u64;
    pub shadows_strength: u64;
    pub contrast_percent: u64;
    pub contrast_slope: u64;
    pub highlights_strength: u64;
    pub whites_strength: u64;
    pub linear_chroma: u64;
    pub vibrance_strength: u64;
}

pub struct ReplayPin {
    pub valid: bool;
    pub plan: PlanKey;
    pub mixer: asset_identity.MixerKey;
    pub curve: asset_identity.CurveKey;
}

// Supplied by a headless caller that has verified both hashes. Width/height
// are pixels before any viewport resampling. Domain 4 is signed scene-linear
// Rec.2020/D65 RGB. The working contract digest names decode, characterization,
// precision, and stage algorithm choices that produced that domain.
pub struct WorkingSourceIdentity {
    pub version: u32;
    pub source_sha256: [32]u8;
    pub working_contract_sha256: [32]u8;
    pub width: u32;
    pub height: u32;
    pub domain: u32;
}

pub struct SourceReplayPin {
    pub valid: bool;
    pub source: WorkingSourceIdentity;
    pub edit: ReplayPin;
}

pub fn valid_source(source: WorkingSourceIdentity): bool {
    if source.version != 1 or source.domain != 4 {
        return false;
    }
    if source.width == 0 or source.height == 0 or source.width > 100000 or source.height > 100000 {
        return false;
    }
    const pixels = (source.width as u64) * (source.height as u64);
    if pixels > 250000000 {
        return false;
    }
    var source_nonzero = false;
    var working_nonzero = false;
    var index: usize = 0;
    while index < 32 {
        if source.source_sha256[index] != 0 {
            source_nonzero = true;
        }
        if source.working_contract_sha256[index] != 0 {
            working_nonzero = true;
        }
        index = index + 1;
    }
    return source_nonzero and working_nonzero;
}

fn same_source(left: WorkingSourceIdentity, right: WorkingSourceIdentity): bool {
    if not valid_source(left) or not valid_source(right) {
        return false;
    }
    if left.version != right.version or left.width != right.width or left.height != right.height or left.domain != right.domain {
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

fn plan_key(plan: edit_plan.DevelopPlan): PlanKey {
    return {
        version: plan.version,
        exposure_ev: asset_identity.float_bits(plan.exposure_ev),
        black_offset: asset_identity.float_bits(plan.black_offset),
        shadows_strength: asset_identity.float_bits(plan.shadows_strength),
        contrast_percent: asset_identity.float_bits(plan.contrast_percent),
        contrast_slope: asset_identity.float_bits(plan.contrast_slope),
        highlights_strength: asset_identity.float_bits(plan.highlights_strength),
        whites_strength: asset_identity.float_bits(plan.whites_strength),
        linear_chroma: asset_identity.float_bits(plan.linear_chroma),
        vibrance_strength: asset_identity.float_bits(plan.vibrance_strength)
    };
}

fn matches_plan(key: PlanKey, plan: edit_plan.DevelopPlan): bool {
    const current = plan_key(plan);
    return key.version == current.version
    and key.exposure_ev == current.exposure_ev
    and key.black_offset == current.black_offset
    and key.shadows_strength == current.shadows_strength
    and key.contrast_percent == current.contrast_percent
    and key.contrast_slope == current.contrast_slope
    and key.highlights_strength == current.highlights_strength
    and key.whites_strength == current.whites_strength
    and key.linear_chroma == current.linear_chroma
    and key.vibrance_strength == current.vibrance_strength;
}

pub fn capture(plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: tone_curve.CurveAsset): ReplayPin {
    const mixer_key = asset_identity.capture_mixer(mixer);
    const curve_key = asset_identity.capture_curve(curve);
    const valid = develop_sample.valid_plan(plan) and mixer_key.valid and curve_key.valid;
    return {
        valid: valid,
        plan: plan_key(plan),
        mixer: mixer_key,
        curve: curve_key
    };
}

pub fn matches(pin: &const ReplayPin, plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: &const tone_curve.CurveAsset): bool {
    return pin.valid and develop_sample.valid_plan(plan)
    and matches_plan(pin.plan, plan)
    and asset_identity.matches_mixer(pin.mixer, mixer)
    and asset_identity.matches_curve(&pin.curve, curve);
}

pub fn apply_pinned(pin: &const ReplayPin, plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: tone_curve.CurveAsset, input: develop_sample.SampleRgb): develop_sample.SampleResult {
    if not matches(pin, plan, mixer, &curve) {
        // Status 8: changed or invalid replay identity. No partial sample.
        return {
            valid: false,
            status: 8,
            pixel: {
                red: 0.0,
                green: 0.0,
                blue: 0.0
            }
        };
    }
    return develop_sample.apply_with_assets(plan, mixer, curve, input);
}

pub fn capture_source(source: WorkingSourceIdentity, plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: tone_curve.CurveAsset): SourceReplayPin {
    const edit = capture(plan, mixer, curve);
    return {
        valid: valid_source(source) and edit.valid,
        source: source,
        edit: edit
    };
}

pub fn matches_source(pin: &const SourceReplayPin, source: WorkingSourceIdentity, plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: &const tone_curve.CurveAsset): bool {
    return pin.valid and same_source(pin.source, source) and matches(&pin.edit, plan, mixer, curve);
}

pub fn apply_source_pinned(pin: &const SourceReplayPin, source: WorkingSourceIdentity, plan: edit_plan.DevelopPlan, mixer: channel_mixer.MixerAsset, curve: tone_curve.CurveAsset, input: develop_sample.SampleRgb): develop_sample.SampleResult {
    if not pin.valid or not same_source(pin.source, source) {
        // Status 9: invalid or changed source/working contract identity.
        return {
            valid: false,
            status: 9,
            pixel: {
                red: 0.0,
                green: 0.0,
                blue: 0.0
            }
        };
    }
    return apply_pinned(&pin.edit, plan, mixer, curve, input);
}
