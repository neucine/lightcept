import .engine.core.core;

// Destination linear-RGB gamut diagnostic v1. Scene-linear Rec.2020/D65
// input is mapped by a declared 3x3 destination matrix before clipping.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct DestinationMatrix {
    pub version: u32;
    pub profile_hash: u64;
    pub rows: [9]f64;
}

pub struct Report {
    // 0 success, 1 asset, 2 shape/limit, 3 invalid input,
    // 4 invalid transform result, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub profile_hash: u64;
    pub pixels: usize;
    pub outside_pixels: usize;
    pub below_zero: [3]usize;
    pub above_one: [3]usize;
    // Largest absolute channel excursion past [0,1], linear destination units.
    pub maximum_excursion: f64;
}

fn failure(status: u32): Report {
    return {
        status: status,
        version: algorithm_version,
        profile_hash: 0,
        pixels: 0,
        outside_pixels: 0,
        below_zero: [0, 0, 0],
        above_one: [0, 0, 0],
        maximum_excursion: 0.0
    };
}

pub fn valid(asset: DestinationMatrix): bool {
    if asset.version != algorithm_version or asset.profile_hash == 0 {
        return false;
    }
    var index: usize = 0;
    while index < 9 {
        const coefficient = asset.rows[index];
        if not (coefficient >= -8.0 and coefficient <= 8.0) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn srgb_destination(profile_hash: u64): DestinationMatrix {
    return {
        version: algorithm_version,
        profile_hash: profile_hash,
        rows: [1.660491, -0.587641, -0.072850,
            -0.124550, 1.132900, -0.008349,
            -0.018151, -0.100579, 1.118730
        ]
    };
}

// Immutable, interleaved scene-linear RGB input in [-0.25,8]. Destination
// code range [0,1] is linear and before transfer. Poll before each row.
// No image mutation, halo, clipping, or pixel output. Failure has no evidence.
pub fn measure(input: []const f32, width: usize, height: usize,
    asset: DestinationMatrix,
    cancelled: fn (usize): bool, context: usize
): Report {
    if not valid(asset) {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    const pixels = width * height;
    if input.len() != pixels * 3 {
        return failure(2);
    }
    var below: [3]usize = [0, 0, 0];
    var above: [3]usize = [0, 0, 0];
    var outside_pixels: usize = 0;
    var maximum_excursion: f64 = 0.0;
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 3;
            var source: [3]f64 = [0.0, 0.0, 0.0];
            var channel: usize = 0;
            while channel < 3 {
                const value = input[offset + channel];
                if not core.finite_sample(value) or value < -0.25 or value > 8.0 {
                    return failure(3);
                }
                source[channel] = value as f64;
                channel = channel + 1;
            }
            var outside = false;
            channel = 0;
            while channel < 3 {
                const start = channel * 3;
                const value = asset.rows[start] * source[0]
                + asset.rows[start + 1] * source[1]
                + asset.rows[start + 2] * source[2];
                if not (value >= -64.0 and value <= 64.0) {
                    return failure(4);
                }
                var excursion: f64 = 0.0;
                if value < 0.0 {
                    below[channel] = below[channel] + 1;
                    excursion = -value;
                    outside = true;
                } else if value > 1.0 {
                    above[channel] = above[channel] + 1;
                    excursion = value - 1.0;
                    outside = true;
                }
                if excursion > maximum_excursion {
                    maximum_excursion = excursion;
                }
                channel = channel + 1;
            }
            if outside {
                outside_pixels = outside_pixels + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return {
        status: 0,
        version: algorithm_version,
        profile_hash: asset.profile_hash,
        pixels: pixels,
        outside_pixels: outside_pixels,
        below_zero: below,
        above_one: above,
        maximum_excursion: maximum_excursion
    };
}
