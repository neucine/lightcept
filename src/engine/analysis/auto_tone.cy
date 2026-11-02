// Scene-linear Rec.2020/D65 tone proposal v1. The histogram and clip map
// must describe the same image and declared white reference.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct ToneProposal {
    // 0 success, 1 provenance/white reference, 2 shape/counts,
    // 3 censored percentile, 4 weak tonal spread, 5 invalid clip bits,
    // 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub source_hash: u64;
    pub pixels: usize;
    pub clipped_pixels: usize;
    pub percentiles: [5]f64;
    pub blacks_offset: f64;
    pub shadows_strength: f64;
    pub contrast_slope: f64;
    pub highlights_strength: f64;
    pub whites_strength: f64;
}

fn failure(status: u32): ToneProposal {
    return {
        status: status,
        version: algorithm_version,
        source_hash: 0,
        pixels: 0,
        clipped_pixels: 0,
        percentiles: [0.0, 0.0, 0.0, 0.0, 0.0],
        blacks_offset: 0.0,
        shadows_strength: 0.0,
        contrast_slope: 1.0,
        highlights_strength: 0.0,
        whites_strength: 0.0
    };
}

fn clamp(value: f64, minimum: f64, maximum: f64): f64 {
    if value < minimum {
        return minimum;
    }
    if value > maximum {
        return maximum;
    }
    return value;
}

// Histogram layout: negative, 256 bins spanning Y [0,1), then Y>=1.
// The selected bin midpoint is used; censored bins cannot yield a proposal.
fn percentile(counts: []const u64, total: u64, basis_points: u64): f64 {
    const rank = ((total - 1) * basis_points) / 10000;
    var cumulative: u64 = 0;
    var index: usize = 0;
    while index < 258 {
        cumulative = cumulative + counts[index];
        if cumulative > rank {
            if index < 2 or index > 256 {
                return -1.0;
            }
            return ((index as f64) - 0.5) / 256.0;
        }
        index = index + 1;
    }
    return -1.0;
}

// Inputs are immutable. `clip_bits` is one byte per pixel, bits 0..2 RGB
// channels at white_reference=1.0. The caller pins `source_hash` for both
// inputs. Poll every 4096 mask entries. No pixel output or spatial halo.
pub fn propose(counts: []const u64, clip_bits: []const u8,
    width: usize, height: usize, source_hash: u64, white_reference: f64,
    cancelled: fn (usize): bool, context: usize
): ToneProposal {
    if source_hash == 0 or white_reference != 1.0 {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    const pixels = width * height;
    if counts.len() != 258 or clip_bits.len() != pixels {
        return failure(2);
    }
    var total: u64 = 0;
    var index: usize = 0;
    while index < 258 {
        if counts[index] > (pixels as u64) - total {
            return failure(2);
        }
        total = total + counts[index];
        index = index + 1;
    }
    if total != pixels as u64 {
        return failure(2);
    }
    var clipped: usize = 0;
    index = 0;
    while index < pixels {
        if index % 4096 == 0 and cancelled(context) {
            return failure(7);
        }
        if clip_bits[index] > 7 {
            return failure(5);
        }
        if clip_bits[index] != 0 {
            clipped = clipped + 1;
        }
        index = index + 1;
    }
    var values: [5]f64 = [0.0, 0.0, 0.0, 0.0, 0.0];
    const ranks: [5]u64 = [200, 2500, 5000, 7500, 9800];
    index = 0;
    while index < 5 {
        values[index] = percentile(counts, total, ranks[index]);
        if values[index] < 0.0 {
            return failure(3);
        }
        index = index + 1;
    }
    if values[3] - values[1] < 0.02 {
        return failure(4);
    }
    var highlights = clamp((0.65 - values[3]) / 0.25, -1.0, 1.0);
    var whites = clamp((0.9 - values[4]) / 0.4, -0.5, 1.0);
    if clipped > 0 {
        if highlights > 0.0 {
            highlights = 0.0;
        }
        if whites > 0.0 {
            whites = 0.0;
        }
    }
    return {
        status: 0,
        version: algorithm_version,
        source_hash: source_hash,
        pixels: pixels,
        clipped_pixels: clipped,
        percentiles: values,
        blacks_offset: clamp(values[0] - 0.02, -0.125, 0.125),
        shadows_strength: clamp((0.12 - values[1]) / 0.12, -1.0, 1.0),
        contrast_slope: clamp(0.35 / (values[3] - values[1]), 0.5, 2.0),
        highlights_strength: highlights,
        whites_strength: whites
    };
}
