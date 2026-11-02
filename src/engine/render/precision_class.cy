// Output precision branch policy v1. This component selects a bounded sample
// layout and quantization identity; it does not write or pack pixels.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;
pub const dither_none: u32 = 0;
pub const round_nearest_ties_up: u32 = 1;

pub struct PrecisionPolicy {
    pub version: u32;
    pub channel_bits: u32;
    pub channels: u32;
    pub dither: u32;
    pub rounding: u32;
}

pub struct PrecisionDecision {
    // 0 success, 1 unsupported policy, 2 extent/limit, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub channel_bits: u32;
    pub channels: u32;
    pub dither: u32;
    pub rounding: u32;
    pub pixels: usize;
    pub samples: usize;
    pub bytes: usize;
    pub maximum_code: u32;
}

fn failure(status: u32): PrecisionDecision {
    return {
        status: status,
        version: algorithm_version,
        channel_bits: 0,
        channels: 0,
        dither: 0,
        rounding: 0,
        pixels: 0,
        samples: 0,
        bytes: 0,
        maximum_code: 0
    };
}

pub fn valid(policy: PrecisionPolicy): bool {
    if policy.version != algorithm_version or policy.dither != dither_none
    or policy.rounding != round_nearest_ties_up {
        return false;
    }
    return (policy.channel_bits == 8
        and (policy.channels == 3 or policy.channels == 4)
    )
    or (policy.channel_bits == 16 and policy.channels == 3);
}

// The channel layout is interleaved visual RGB or RGBA, with opaque alpha
// policy supplied by the caller. The result gives checked allocation sizes
// but never allocates. One cancellation check precedes return.
pub fn select(width: usize, height: usize, policy: PrecisionPolicy,
    cancelled: fn (usize): bool, context: usize
): PrecisionDecision {
    if not valid(policy) {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    if cancelled(context) {
        return failure(7);
    }
    const pixels = width * height;
    const channels = policy.channels as usize;
    const bytes_per_channel = (policy.channel_bits / 8) as usize;
    const maximum_code: u32 = 255;
    if policy.channel_bits == 16 {
        return {
            status: 0,
            version: algorithm_version,
            channel_bits: policy.channel_bits,
            channels: policy.channels,
            dither: policy.dither,
            rounding: policy.rounding,
            pixels: pixels,
            samples: pixels * channels,
            bytes: pixels * channels * bytes_per_channel,
            maximum_code: 65535
        };
    }
    return {
        status: 0,
        version: algorithm_version,
        channel_bits: policy.channel_bits,
        channels: policy.channels,
        dither: policy.dither,
        rounding: policy.rounding,
        pixels: pixels,
        samples: pixels * channels,
        bytes: pixels * channels * bytes_per_channel,
        maximum_code: maximum_code
    };
}
