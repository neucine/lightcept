import .engine.core.core;
import .engine.color.working_to_linear_srgb;
import .engine.color.srgb_clip;
import .engine.color.srgb_transfer;
import std.math;

// Fixed sRGB2014 output gamut mapping v1. Scene-linear Rec.2020/D65 RGB in;
// encoded sRGB floats [0,1] ready for output quantization out. This is an
// explicit Lightcept mapping policy, not an ICC CMM or arbitrary ICC profile.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const destination_srgb2014: u32 = 1;
pub const relative_colorimetric: u32 = 1;
pub const perceptual: u32 = 2;

pub struct MapPolicy {
    pub version: u32;
    pub destination: u32;
    pub intent: u32;
}

pub struct MapReport {
    // 0 success, 1 policy, 2 shape/limit, 3 input, 4 mapped output,
    // 7 cancelled. Counts are zero and invalid for nonzero status.
    pub status: u32;
    pub version: u32;
    pub destination: u32;
    pub intent: u32;
    pub pixels: usize;
    pub outside_pixels: usize;
}

pub struct LinearMapResult {
    // 0 success, 1 unsupported intent, 2 input outside [-16,16].
    pub status: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

fn failure(status: u32): MapReport {
    return {
        status: status,
        version: algorithm_version,
        destination: 0,
        intent: 0,
        pixels: 0,
        outside_pixels: 0
    };
}

pub fn valid(policy: MapPolicy): bool {
    return policy.version == algorithm_version
    and policy.destination == destination_srgb2014
    and (policy.intent == relative_colorimetric or policy.intent == perceptual);
}

fn outside(rgb: [3]f64): bool {
    return rgb[0] < 0.0 or rgb[0] > 1.0
    or rgb[1] < 0.0 or rgb[1] > 1.0
    or rgb[2] < 0.0 or rgb[2] > 1.0;
}

// For the perceptual policy, project linear destination RGB toward neutral
// destination luminance until every channel lies in [0,1]. If the neutral
// itself lies outside the range, clamp it first. This preserves the chroma
// ray direction for in-gamut Y and leaves in-gamut samples unchanged.
fn map_linear(linear: [3]f64, intent: u32): [3]f64 {
    if intent == relative_colorimetric {
        return [srgb_clip.channel(linear[0]), srgb_clip.channel(linear[1]),
            srgb_clip.channel(linear[2])
        ];
    }
    if not outside(linear) {
        return linear;
    }
    const y = srgb_clip.channel(0.2126 * linear[0]
        + 0.7152 * linear[1] + 0.0722 * linear[2]
    );
    var scale: f64 = 1.0;
    var channel: usize = 0;
    while channel < 3 {
        const difference = linear[channel] - y;
        if difference > 0.0 {
            const bound = (1.0 - y) / difference;
            if bound < scale {
                scale = bound;
            }
        } else if difference < 0.0 {
            const bound = -y / difference;
            if bound < scale {
                scale = bound;
            }
        }
        channel = channel + 1;
    }
    return [srgb_clip.channel(y + scale * (linear[0] - y)),
        srgb_clip.channel(y + scale * (linear[1] - y)),
        srgb_clip.channel(y + scale * (linear[2] - y))
    ];
}

// Direct destination-linear analytical entry. The fixed sRGB2014 matrix has
// produced these values, but transfer and quantization have not yet run.
pub fn map_linear_checked(linear: [3]f64, intent: u32): LinearMapResult {
    if intent != relative_colorimetric and intent != perceptual {
        return {
            status: 1,
            red: 0.0,
            green: 0.0,
            blue: 0.0
        };
    }
    var channel: usize = 0;
    while channel < 3 {
        if not (linear[channel] >= -16.0 and linear[channel] <= 16.0) {
            return {
                status: 2,
                red: 0.0,
                green: 0.0,
                blue: 0.0
            };
        }
        channel = channel + 1;
    }
    const mapped = map_linear(linear, intent);
    return {
        status: 0,
        red: mapped[0],
        green: mapped[1],
        blue: mapped[2]
    };
}

// Immutable interleaved scene RGB f32 [-0.25,8] and disjoint equal-size
// encoded sRGB output. Two row-wise passes validate before writes. The first
// counts source pixels outside linear destination gamut. Cancellation is
// checked every row in both passes; any failure invalidates all output.
pub fn apply(input: []const f32, width: usize, height: usize,
    policy: MapPolicy, output: []f32,
    cancelled: fn (usize): bool, context: usize
): MapReport {
    if not valid(policy) {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or output.len() != pixels * 3 {
        return failure(2);
    }
    var outside_pixels: usize = 0;
    var pass: usize = 0;
    while pass < 2 {
        var row: usize = 0;
        while row < height {
            if cancelled(context) {
                return failure(7);
            }
            var column: usize = 0;
            while column < width {
                const offset = (row * width + column) * 3;
                var channel: usize = 0;
                while channel < 3 {
                    const sample = input[offset + channel];
                    if not core.finite_sample(sample) or sample < -0.25
                    or sample > 8.0 {
                        return failure(3);
                    }
                    channel = channel + 1;
                }
                const linear = working_to_linear_srgb.convert(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64
                );
                if pass == 0 and outside(linear) {
                    outside_pixels = outside_pixels + 1;
                }
                const mapped = map_linear(linear, policy.intent);
                channel = 0;
                while channel < 3 {
                    const encoded = srgb_transfer.encode(mapped[channel]);
                    if not (encoded >= 0.0 and encoded <= 1.0) {
                        return failure(4);
                    }
                    if pass == 1 {
                        const rounded = math.to_f32_rounded(encoded);
                        if rounded is value {
                            output[offset + channel] = value;
                        } else {
                            return failure(4);
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
    return {
        status: 0,
        version: algorithm_version,
        destination: policy.destination,
        intent: policy.intent,
        pixels: pixels,
        outside_pixels: outside_pixels
    };
}
