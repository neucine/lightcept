import .engine.core.core;
import std.math;

// Daylight sky mask v1 for upright scene-linear Rec.2020/D65 RGB. Blue
// evidence seeds the top edge; four-connected growth may include bright
// near-neutral cloud pixels. No model, source mutation, or RGB adjustment.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct SkyPolicy {
    pub version: u32;
    // Caller declares that the input has already been oriented upright.
    pub upright: bool;
}

pub struct SkyReport {
    // 0 success, 1 policy, 2 shape/limit, 3 invalid RGB,
    // 7 cancelled. Nonzero status invalidates all output and counts.
    pub status: u32;
    pub version: u32;
    pub selected_pixels: usize;
    pub seed_pixels: usize;
}

fn failure(status: u32): SkyReport {
    return {
        status: status,
        version: algorithm_version,
        selected_pixels: 0,
        seed_pixels: 0
    };
}

pub fn valid(policy: SkyPolicy): bool {
    return policy.version == algorithm_version and policy.upright;
}

fn clamp01(value: f64): f64 {
    if value < 0.0 {
        return 0.0;
    }
    if value > 1.0 {
        return 1.0;
    }
    return value;
}

fn maximum(a: f64, b: f64): f64 {
    if a > b {
        return a;
    }
    return b;
}

fn minimum(a: f64, b: f64): f64 {
    if a < b {
        return a;
    }
    return b;
}

// Color belief is deliberately conservative: a blue excess over red/green
// receives a soft score, while bright near-neutral cloud-like pixels can
// join an already seeded region. Cloud score alone cannot start a region.
fn blue_score(red: f64, green: f64, blue: f64): f64 {
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    if y < 0.04 or blue < 0.08 {
        return 0.0;
    }
    return clamp01((blue - maximum(red, green) - 0.02) / 0.10);
}

fn cloud_score(red: f64, green: f64, blue: f64): f64 {
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const spread = maximum(maximum(red, green), blue)
    - minimum(minimum(red, green), blue);
    if y < 0.55 or spread > 0.12 or blue < red * 0.95
    or blue < green * 0.95 {
        return 0.0;
    }
    return 0.6 * clamp01((y - 0.55) / 0.20);
}

fn score(input: []const f32, pixel: usize): f64 {
    const offset = pixel * 3;
    const red = input[offset] as f64;
    const green = input[offset + 1] as f64;
    const blue = input[offset + 2] as f64;
    return maximum(blue_score(red, green, blue), cloud_score(red, green, blue));
}

fn enqueue(input: []const f32, pixel: usize,
    seen: []u8, queue: []usize, output: []f32, tail: usize
): usize {
    if seen[pixel] != 0 {
        return tail;
    }
    const belief = score(input, pixel);
    if belief < 0.3 {
        seen[pixel] = 2;
        return tail;
    }
    if tail >= queue.len() {
        return tail;
    }
    const rounded = math.to_f32_rounded(belief);
    if rounded is value {
        output[pixel] = value;
    } else {
        seen[pixel] = 2;
        return tail;
    }
    seen[pixel] = 1;
    queue[tail] = pixel;
    return tail + 1;
}

// Input is immutable interleaved f32 scene RGB, each channel [-0.25,8].
// Caller owns output coverage, a rewritten u8 visitation buffer, and
// a usize queue; each has one element per pixel. Output is [0,1], with zero
// outside top-connected candidates. Validate input before using scratch.
// Poll each validation/initialization row and each 256 BFS nodes. Cancellation
// or failure invalidates all output; connected growth may leave it partial.
pub fn build(input: []const f32, width: usize, height: usize,
    policy: SkyPolicy, seen: []u8, queue: []usize, output: []f32,
    cancelled: fn (usize): bool, context: usize
): SkyReport {
    if not valid(policy) {
        return failure(1);
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return failure(2);
    }
    const pixels = width * height;
    if input.len() != pixels * 3 or seen.len() != pixels
    or queue.len() != pixels or output.len() != pixels {
        return failure(2);
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return failure(7);
        }
        var channel: usize = row * width * 3;
        while channel < (row + 1) * width * 3 {
            const value = input[channel];
            if not core.finite_sample(value) or value < -0.25
            or value > 8.0 {
                return failure(3);
            }
            channel = channel + 1;
        }
        row = row + 1;
    }
    var index: usize = 0;
    while index < pixels {
        if index % width == 0 and cancelled(context) {
            return failure(7);
        }
        seen[index] = 0;
        output[index] = 0.0;
        index = index + 1;
    }
    var tail: usize = 0;
    var column: usize = 0;
    while column < width {
        if column % 256 == 0 and cancelled(context) {
            return failure(7);
        }
        const offset = column * 3;
        if blue_score(input[offset] as f64,
            input[offset + 1] as f64, input[offset + 2] as f64
        ) >= 0.6 {
            tail = enqueue(input, column, seen, queue, output, tail);
        }
        column = column + 1;
    }
    const seeds = tail;
    var head: usize = 0;
    while head < tail {
        if head % 256 == 0 and cancelled(context) {
            return failure(7);
        }
        const pixel = queue[head];
        const x = pixel % width;
        const y = pixel / width;
        if x > 0 {
            tail = enqueue(input, pixel - 1, seen, queue, output, tail);
        }
        if x + 1 < width {
            tail = enqueue(input, pixel + 1, seen, queue, output, tail);
        }
        if y > 0 {
            tail = enqueue(input, pixel - width, seen, queue, output, tail);
        }
        if y + 1 < height {
            tail = enqueue(input, pixel + width, seen, queue, output, tail);
        }
        head = head + 1;
    }
    return {
        status: 0,
        version: algorithm_version,
        selected_pixels: tail,
        seed_pixels: seeds
    };
}
