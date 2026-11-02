import .engine.core.core;
import std.math;

// Working Rec.2020/D65 hue rotation v1. The chromatic plane uses
// U = R-Y, V = B-Y; Y is fixed. This is a declared linear opponent plane,
// not a perceptually uniform hue representation.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct HueAsset {
    pub version: u32;
    // Counterclockwise degrees in the (U,V) plane, [-180,180].
    pub angle_degrees: f64;
}

pub fn valid(asset: HueAsset): bool {
    return asset.version == algorithm_version
    and asset.angle_degrees >= -180.0 and asset.angle_degrees <= 180.0;
}

// Pinned scalar Taylor approximation for |angle| <= pi. The first omitted
// terms bound |sin error| below 4e-8 and |cos error| below 2e-7.
fn sine(x: f64): f64 {
    const t = x * x;
    return x * (1.0 + t * (-1.0 / 6.0 + t * (1.0 / 120.0
        + t * (-1.0 / 5040.0 + t * (1.0 / 362880.0
            + t * (-1.0 / 39916800.0 + t * (1.0 / 6227020800.0
                + t * (-1.0 / 1307674368000.0
                    + t / 355687428096000.0
                )
            ))
        ))
    )));
}

fn cosine(x: f64): f64 {
    const t = x * x;
    return 1.0 + t * (-1.0 / 2.0 + t * (1.0 / 24.0
        + t * (-1.0 / 720.0 + t * (1.0 / 40320.0
            + t * (-1.0 / 3628800.0 + t * (1.0 / 479001600.0
                + t * (-1.0 / 87178291200.0
                    + t / 20922789888000.0
                )
            ))
        ))
    ));
}

pub fn rotate(red: f64, green: f64, blue: f64,
    asset: HueAsset
): [3]f64 {
    if asset.angle_degrees == 0.0 or (red == green and green == blue) {
        return [red, green, blue];
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const u = red - y;
    const v = blue - y;
    const radians = asset.angle_degrees * 0.017453292519943295;
    const c = cosine(radians);
    const s = sine(radians);
    const rotated_u = c * u - s * v;
    const rotated_v = s * u + c * v;
    const result_red = y + rotated_u;
    const result_blue = y + rotated_v;
    const result_green = (y - 0.2627 * result_red
        - 0.0593 * result_blue
    ) / 0.6780;
    return [result_red, result_green, result_blue];
}

// Immutable interleaved f32 scene-linear RGB in [-0.25,8]; disjoint output
// of identical shape. Status 0 success, 1 asset, 2 shape/limit, 3 invalid
// input, 4 invalid output, 7 cancelled. Validate projected output before
// writes. Poll before each row in both passes. No spatial halo or gamut clip.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: HueAsset, output: []f32,
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
                const result = rotate(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64, asset
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -32.0 and result[channel] <= 32.0) {
                        return 4;
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(result[channel]);
                        if rounded is value {
                            output[offset + channel] = value;
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
