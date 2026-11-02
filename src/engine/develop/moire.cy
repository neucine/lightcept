import .engine.core.core;
import std.math;

// CFA-locked two-pixel chroma moire reduction v1 on scene-linear Rec.2020/D65
// RGB. A signed local projection measures chroma at the Bayer green/non-green
// checkerboard frequency. Only that measured component is attenuated.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct MoireAsset {
    pub version: u32;
    pub cfa: [4]u32;
    pub minimum_chroma_amplitude: f64;
    pub maximum_luminance_amplitude: f64;
    pub strength: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: MoireAsset): bool {
    var counts: [3]u32 = [0, 0, 0];
    var phase: usize = 0;
    while phase < 4 {
        if asset.cfa[phase] > 2 {
            return false;
        }
        const color = asset.cfa[phase] as usize;
        counts[color] = counts[color] + 1;
        phase = phase + 1;
    }
    return asset.version == algorithm_version
    and counts[0] == 1 and counts[1] == 2 and counts[2] == 1
    and ((asset.cfa[0] == 1 and asset.cfa[3] == 1)
        or (asset.cfa[1] == 1 and asset.cfa[2] == 1)
    )
    and asset.minimum_chroma_amplitude >= 0.001
    and asset.minimum_chroma_amplitude <= 0.5
    and asset.maximum_luminance_amplitude >= 0.001
    and asset.maximum_luminance_amplitude <= 1.0
    and asset.strength >= 0.0 and asset.strength <= 1.0
    and asset.maximum_change >= 0.0 and asset.maximum_change <= 0.5;
}

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}

fn luminance(input: []const f32, index: usize): f64 {
    return 0.2627 * (input[index] as f64)
    + 0.6780 * (input[index + 1] as f64)
    + 0.0593 * (input[index + 2] as f64);
}

fn coordinate(position: usize, displacement: i32, limit: usize): usize {
    if displacement < 0 {
        const magnitude = (-displacement) as usize;
        if position < magnitude {
            return 0;
        }
        return position - magnitude;
    }
    const magnitude = displacement as usize;
    if magnitude >= limit or position >= limit - magnitude {
        return limit - 1;
    }
    return position + magnitude;
}

fn phase_sign(asset: MoireAsset, x: usize, y: usize): f64 {
    if asset.cfa[(y % 2) * 2 + x % 2] == 1 {
        return 1.0;
    }
    return -1.0;
}

fn adjusted(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: MoireAsset
): ?f32 {
    const index = (y * width + x) * 3;
    if asset.strength == 0.0 or asset.maximum_change == 0.0 {
        return input[index + channel];
    }
    var sum_sign: f64 = 0.0;
    var sum_y: f64 = 0.0;
    var sum_rg: f64 = 0.0;
    var sum_bg: f64 = 0.0;
    var signed_y: f64 = 0.0;
    var signed_rg: f64 = 0.0;
    var signed_bg: f64 = 0.0;
    var dy: i32 = -2;
    while dy <= 2 {
        const ny = coordinate(y, dy, height);
        var dx: i32 = -2;
        while dx <= 2 {
            const nx = coordinate(x, dx, width);
            const sample = (ny * width + nx) * 3;
            const sign = phase_sign(asset, nx, ny);
            const value_y = luminance(input, sample);
            const value_rg = (input[sample] as f64) - (input[sample + 1] as f64);
            const value_bg = (input[sample + 2] as f64) - (input[sample + 1] as f64);
            sum_sign = sum_sign + sign;
            sum_y = sum_y + value_y;
            sum_rg = sum_rg + value_rg;
            sum_bg = sum_bg + value_bg;
            signed_y = signed_y + sign * value_y;
            signed_rg = signed_rg + sign * value_rg;
            signed_bg = signed_bg + sign * value_bg;
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    // Least-squares coefficient of the signed CFA basis with a free DC term.
    const denominator = 25.0 - sum_sign * sum_sign / 25.0;
    if denominator <= 0.0 {
        return input[index + channel];
    }
    const amplitude_y = (signed_y - sum_sign * sum_y / 25.0) / denominator;
    const amplitude_rg = (signed_rg - sum_sign * sum_rg / 25.0) / denominator;
    const amplitude_bg = (signed_bg - sum_sign * sum_bg / 25.0) / denominator;
    const chroma = absolute(amplitude_rg) + absolute(amplitude_bg);
    if chroma < asset.minimum_chroma_amplitude
    or absolute(amplitude_y) > asset.maximum_luminance_amplitude {
        return input[index + channel];
    }
    const sign = phase_sign(asset, x, y);
    const removal = asset.strength * sign
    * (chroma - asset.minimum_chroma_amplitude) / chroma;
    const rg_change = -removal * amplitude_rg;
    const bg_change = -removal * amplitude_bg;
    const green_change = -0.2627 * rg_change - 0.0593 * bg_change;
    const red_change = green_change + rg_change;
    const blue_change = green_change + bg_change;
    var largest = absolute(red_change);
    if absolute(green_change) > largest {
        largest = absolute(green_change);
    }
    if absolute(blue_change) > largest {
        largest = absolute(blue_change);
    }
    var scale: f64 = 1.0;
    if largest > asset.maximum_change {
        scale = asset.maximum_change / largest;
    }
    var change = green_change;
    if channel == 0 {
        change = red_change;
    }
    if channel == 2 {
        change = blue_change;
    }
    return math.to_f32_rounded((input[index + channel] as f64) + scale * change);
}

// Immutable interleaved RGB input and disjoint output. Clamp-to-edge support
// needs a two-pixel halo. Status 0 success, 1 asset, 2 shape/limit, 3 nonfinite
// input, 4 nonfinite output, 7 cancelled. Any failure invalidates the output.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: MoireAsset, output: []f32,
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
    while pass < 3 {
        var y: usize = 0;
        while y < height {
            if cancelled(context) {
                return 7;
            }
            var x: usize = 0;
            while x < width {
                const index = (y * width + x) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    if pass == 0 {
                        if not core.finite_sample(input[index + channel]) {
                            return 3;
                        }
                    } else {
                        const adjusted_value = adjusted(input, width, height, x, y, channel, asset);
                        if adjusted_value is value {
                            if pass == 1 {
                                if not core.finite_sample(value) {
                                    return 4;
                                }
                            } else {
                                output[index + channel] = value;
                            }
                        } else {
                            return 4;
                        }
                    }
                    channel = channel + 1;
                }
                x = x + 1;
            }
            y = y + 1;
        }
        pass = pass + 1;
    }
    return 0;
}
