import .engine.core.core;
import std.math;

// Diagnostic luminance bands v1. Scene-linear Rec.2020/D65 RGB in and out.
// Input Y selects EV at fixed anchors: black 0, middle gray 0.18, white 1.
// Below black and above white use the endpoint EV. RGB receives one common
// gain, preserving ratios and signed headroom. No gamut clipping occurs here.
// The scalar operation is pointwise; the image entry polls cancellation per row.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct BandAsset {
    pub version: u32;
    pub black_ev: f64;
    pub middle_ev: f64;
    pub white_ev: f64;
}

pub struct BandResult {
    pub valid: bool;
    // 0 success, 1 invalid asset, 2 nonfinite input, 3 nonfinite output.
    pub status: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

fn finite(value: f64): bool {
    const infinity = math.pow_f64(2.0, 1024.0);
    return value > -infinity and value < infinity;
}

fn bounded(ev: f64): bool {
    return ev >= -4.0 and ev <= 4.0;
}

pub fn neutral_asset(): BandAsset {
    return {
        version: algorithm_version,
        black_ev: 0.0,
        middle_ev: 0.0,
        white_ev: 0.0
    };
}

pub fn valid(asset: BandAsset): bool {
    return asset.version == algorithm_version
    and bounded(asset.black_ev) and bounded(asset.middle_ev) and bounded(asset.white_ev);
}

fn failure(status: u32): BandResult {
    return {
        valid: false,
        status: status,
        red: 0.0,
        green: 0.0,
        blue: 0.0
    };
}

pub fn apply(asset: BandAsset, red: f64, green: f64, blue: f64): BandResult {
    if not valid(asset) {
        return failure(1);
    }
    if not (finite(red) and finite(green) and finite(blue)) {
        return failure(2);
    }
    if asset.black_ev == 0.0 and asset.middle_ev == 0.0 and asset.white_ev == 0.0 {
        return {
            valid: true,
            status: 0,
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    if not finite(y) {
        return failure(3);
    }
    var ev = asset.black_ev;
    if y >= 1.0 {
        ev = asset.white_ev;
    } else if y >= 0.18 {
        ev = asset.middle_ev + (asset.white_ev - asset.middle_ev) * ((y - 0.18) / 0.82);
    } else if y > 0.0 {
        ev = asset.black_ev + (asset.middle_ev - asset.black_ev) * (y / 0.18);
    }
    const gain = math.pow_f64(2.0, ev);
    const result: BandResult = {
        valid: true,
        status: 0,
        red: red * gain,
        green: green * gain,
        blue: blue * gain
    };
    if not (finite(result.red) and finite(result.green) and finite(result.blue)) {
        return failure(3);
    }
    return result;
}

// Immutable interleaved scene-linear Rec.2020/D65 f32 RGB in [-0.25,8],
// disjoint output in [-4,128] linear reference-white units. Three EV
// anchors are dimensionless exposure stops. No gamut clipping or halo.
// Status 0 success, 1 asset, 2 shape/limit, 3 input, 4 result, 7 cancelled.
// Two passes validate before writes and poll cancellation per row. Nonzero
// status invalidates all output.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: BandAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return 2;
    }
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return 7;
            }
            var column: usize = 0;
            while column < width {
                const offset = (row * width + column) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    const value = input[offset + channel];
                    if not core.finite_sample(value) or value < -0.25
                    or value > 8.0 {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = apply(asset, input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64
                );
                if result.status != 0 {
                    return 4;
                }
                const values: [3]f64 = [result.red, result.green, result.blue];
                channel = 0;
                while channel < 3 {
                    const value = values[channel];
                    if not (value >= -4.0 and value <= 128.0) {
                        return 4;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(value);
                        if rounded is sample {
                            output[offset + channel] = sample;
                        } else {
                            return 4;
                        }
                    }
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
