import .engine.core.core;

// Diagnostic gray-world gain proposal v1 for scene-linear Rec.2020/D65 RGB.
// This is analysis only: the caller decides whether a scene supports the
// gray-world assumption and whether to apply the proposal.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct WhiteBalanceProposal {
    // 0 success, 1 identity, 2 shape/limit, 3 invalid input,
    // 4 insufficient eligible pixels, 5 unsupported gain, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub camera_matrix_hash: u64;
    pub total_pixels: usize;
    pub eligible_pixels: usize;
    pub mean_rgb: [3]f64;
    pub working_gains: [3]f64;
}

fn failure(status: u32): WhiteBalanceProposal {
    return {
        status: status,
        version: algorithm_version,
        camera_matrix_hash: 0,
        total_pixels: 0,
        eligible_pixels: 0,
        mean_rgb: [0.0, 0.0, 0.0],
        working_gains: [0.0, 0.0, 0.0]
    };
}

// Immutable interleaved RGB input in [-0.25,8], row-major pixel coordinates.
// A pixel is eligible when every channel is in [0.02,0.98] and Rec.2020 Y
// is in [0.03,0.9]. Every input sample is validated; no image is modified.
// Poll before each row. Any failure returns no usable proposal.
pub fn propose(input: []const f32, width: usize, height: usize,
    camera_matrix_hash: u64,
    cancelled: fn (usize): bool, context: usize
): WhiteBalanceProposal {
    if camera_matrix_hash == 0 {
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
    var sums: [3]f64 = [0.0, 0.0, 0.0];
    var eligible: usize = 0;
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 3;
            var rgb: [3]f64 = [0.0, 0.0, 0.0];
            var usable = true;
            var channel: usize = 0;
            while channel < 3 {
                const sample = input[offset + channel];
                if not core.finite_sample(sample) or sample < -0.25
                or sample > 8.0 {
                    return failure(3);
                }
                rgb[channel] = sample as f64;
                if rgb[channel] < 0.02 or rgb[channel] > 0.98 {
                    usable = false;
                }
                channel = channel + 1;
            }
            const y = 0.2627 * rgb[0] + 0.6780 * rgb[1] + 0.0593 * rgb[2];
            if y < 0.03 or y > 0.9 {
                usable = false;
            }
            if usable {
                channel = 0;
                while channel < 3 {
                    sums[channel] = sums[channel] + rgb[channel];
                    channel = channel + 1;
                }
                eligible = eligible + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    if eligible < 16 {
        return failure(4);
    }
    var means: [3]f64 = [0.0, 0.0, 0.0];
    var channel: usize = 0;
    while channel < 3 {
        means[channel] = sums[channel] / (eligible as f64);
        channel = channel + 1;
    }
    const y = 0.2627 * means[0] + 0.6780 * means[1] + 0.0593 * means[2];
    var gains: [3]f64 = [1.0, 1.0, 1.0];
    channel = 0;
    while channel < 3 {
        gains[channel] = y / means[channel];
        if not (gains[channel] >= 0.25 and gains[channel] <= 4.0) {
            return failure(5);
        }
        channel = channel + 1;
    }
    return {
        status: 0,
        version: algorithm_version,
        camera_matrix_hash: camera_matrix_hash,
        total_pixels: pixels,
        eligible_pixels: eligible,
        mean_rgb: means,
        working_gains: gains
    };
}
