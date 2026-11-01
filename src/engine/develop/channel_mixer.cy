import .engine.color.output_color;

// Diagnostic scene-linear Rec.2020/D65 channel mixer v1. The six stored
// cross-channel coefficients imply each row's diagonal coefficient. Computing
// with channel differences keeps every neutral RGB triplet exactly neutral.
pub const algorithm_version: u32 = 1;

pub struct MixerAsset {
    pub version: u32;
    pub red_from_green: f64;
    pub red_from_blue: f64;
    pub green_from_red: f64;
    pub green_from_blue: f64;
    pub blue_from_red: f64;
    pub blue_from_green: f64;
}

pub struct MixerResult {
    pub valid: bool;
    // 0 success, 1 invalid asset, 2 nonfinite input, 3 nonfinite output.
    pub status: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

fn finite(value: f64): bool {
    const infinity = output_color.exposure_gain_native(1024.0);
    return value > -infinity and value < infinity;
}

fn bounded(value: f64): bool {
    return value >= -1.0 and value <= 1.0;
}

pub fn neutral_asset(): MixerAsset {
    return {
        version: algorithm_version,
        red_from_green: 0.0,
        red_from_blue: 0.0,
        green_from_red: 0.0,
        green_from_blue: 0.0,
        blue_from_red: 0.0,
        blue_from_green: 0.0
    };
}

pub fn valid(asset: MixerAsset): bool {
    return asset.version == algorithm_version
    and bounded(asset.red_from_green) and bounded(asset.red_from_blue)
    and bounded(asset.green_from_red) and bounded(asset.green_from_blue)
    and bounded(asset.blue_from_red) and bounded(asset.blue_from_green);
}

fn failure(status: u32): MixerResult {
    return {
        valid: false,
        status: status,
        red: 0.0,
        green: 0.0,
        blue: 0.0
    };
}

pub fn apply(asset: MixerAsset, red: f64, green: f64, blue: f64): MixerResult {
    if not valid(asset) {
        return failure(1);
    }
    if not (finite(red) and finite(green) and finite(blue)) {
        return failure(2);
    }
    const result: MixerResult = {
        valid: true,
        status: 0,
        red: red + asset.red_from_green * (green - red) + asset.red_from_blue * (blue - red),
        green: green + asset.green_from_red * (red - green) + asset.green_from_blue * (blue - green),
        blue: blue + asset.blue_from_red * (red - blue) + asset.blue_from_green * (green - blue)
    };
    if not (finite(result.red) and finite(result.green) and finite(result.blue)) {
        return failure(3);
    }
    return result;
}
