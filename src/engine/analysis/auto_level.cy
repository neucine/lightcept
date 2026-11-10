import std.math;

// Analyze a bounded, camera-upright, display-luminance image before any user
// quarter turn or mirror. Image coordinates are x right, y down. A returned
// angle is the clockwise straighten correction in millidegrees.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 4194304;
const first_angle: i32 = -17000;
const angle_step: i32 = 250;
const angle_count: usize = 137;

pub struct Estimate {
    // 0 suggestion, 1 invalid shape/limit, 2 no reliable line, 7 cancelled.
    pub status: u32;
    pub version: u32;
    pub angle_millidegrees: i32;
    pub votes: u32;
    pub edge_pixels: u32;
}

fn failure(status: u32): Estimate {
    return {
        status: status,
        version: algorithm_version,
        angle_millidegrees: 0,
        votes: 0,
        edge_pixels: 0
    };
}

fn absolute(value: i32): i32 {
    if value < 0 {
        return -value;
    }
    return value;
}

fn slope(angle_millidegrees: i32): f64 {
    const radians = (angle_millidegrees as f64) * 0.000017453292519943295;
    const squared = radians * radians;
    // tan(x), with error below 0.000004 over the declared angle range.
    return radians * (1.0 + squared / 3.0 + 2.0 * squared * squared / 15.0
        + 17.0 * squared * squared * squared / 315.0
    );
}

// Input is immutable 8-bit luminance in camera-upright coordinates, before the
// user's orthogonal transform or crop.
// The caller should reduce a RAW preview to at most 2048 per axis before use.
// All work is deterministic, bounded by 4,194,304 pixels and 137 slope bins.
// Cancellation is polled before each source row; no output image is modified.
pub fn estimate(input: []const u8, width: usize, height: usize,
    cancelled: fn (usize): bool, context: usize
): Estimate {
    if width < 32 or height < 32 or width > 2048 or height > 2048
    or width > maximum_pixels / height or input.len() != width * height {
        return failure(1);
    }
    const margin: usize = 320;
    const row_bins = height + 2 * margin;
    var votes: [:]u32 = [: angle_count * row_bins]u32;
    while votes.len() < angle_count * row_bins {
        votes.push(0);
    }
    var edge_pixels: u32 = 0;
    var y: usize = 1;
    while y + 1 < height {
        if cancelled(context) {
            return failure(7);
        }
        var x: usize = 1;
        while x + 1 < width {
            const vertical = (input[(y + 1) * width + x] as i32)
            - (input[(y - 1) * width + x] as i32);
            const horizontal = (input[y * width + x + 1] as i32)
            - (input[y * width + x - 1] as i32);
            if absolute(vertical) >= 48 and absolute(horizontal) * 2 <= absolute(vertical) {
                edge_pixels = edge_pixels + 1;
                var bin: usize = 0;
                while bin < angle_count {
                    const angle = first_angle + (bin as i32) * angle_step;
                    const intercept = (y as f64) - slope(angle)
                    * ((x as f64) - ((width - 1) as f64) * 0.5);
                    const row = math.round_f64(intercept) as i32 + margin as i32;
                    if row >= 0 and (row as usize) < row_bins {
                        const index = bin * row_bins + row as usize;
                        votes[index] = votes[index] + 1;
                    }
                    bin = bin + 1;
                }
            }
            x = x + 1;
        }
        y = y + 1;
    }
    var best_votes: u32 = 0;
    var best_bin: usize = 0;
    var bin: usize = 0;
    while bin < angle_count {
        var row: usize = 0;
        while row < row_bins {
            const count = votes[bin * row_bins + row];
            if count > best_votes {
                best_votes = count;
                best_bin = bin;
            }
            row = row + 1;
        }
        bin = bin + 1;
    }
    if best_votes < (width / 4) as u32 {
        return failure(2);
    }
    var alternate: u32 = 0;
    bin = 0;
    while bin < angle_count {
        if absolute((bin as i32) - (best_bin as i32)) > 8 {
            var row: usize = 0;
            while row < row_bins {
                const count = votes[bin * row_bins + row];
                if count > alternate {
                    alternate = count;
                }
                row = row + 1;
            }
        }
        bin = bin + 1;
    }
    if best_votes < alternate + alternate / 5 {
        return failure(2);
    }
    return {
        status: 0,
        version: algorithm_version,
        angle_millidegrees: -(first_angle + (best_bin as i32) * angle_step),
        votes: best_votes,
        edge_pixels: edge_pixels
    };
}
