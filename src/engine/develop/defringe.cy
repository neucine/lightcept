import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 chromatic fringe attenuation v1. The caller
// supplies the Bayer CFA phase of the demosaiced image. Only matching phases
// inform a pixel's local chroma reference; luminance is preserved.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct DefringeAsset {
    pub version: u32;
    pub cfa: [4]u32;
    pub chroma_threshold: f64;
    pub edge_threshold_y: f64;
    pub strength: f64;
    pub maximum_change: f64;
}

pub fn valid(asset: DefringeAsset): bool {
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
    and asset.chroma_threshold >= 0.001 and asset.chroma_threshold <= 1.0
    and asset.edge_threshold_y >= 0.001 and asset.edge_threshold_y <= 1.0
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

fn median(values: [8]f64, count: usize): f64 {
    var sorted = values;
    var i: usize = 1;
    while i < count {
        const value = sorted[i];
        var j = i;
        while j > 0 and sorted[j - 1] > value {
            sorted[j] = sorted[j - 1];
            j = j - 1;
        }
        sorted[j] = value;
        i = i + 1;
    }
    if count % 2 == 1 {
        return sorted[count / 2];
    }
    return (sorted[count / 2 - 1] + sorted[count / 2]) * 0.5;
}

fn adjusted(input: []const f32, width: usize, height: usize,
    x: usize, y: usize, channel: usize, asset: DefringeAsset
): ?f32 {
    const index = (y * width + x) * 3;
    if asset.strength == 0.0 or asset.maximum_change == 0.0 {
        return input[index + channel];
    }
    const center_y = luminance(input, index);
    const center_rg = (input[index] as f64) - (input[index + 1] as f64);
    const center_bg = (input[index + 2] as f64) - (input[index + 1] as f64);
    var neighbor_rg: [8]f64 = [0.0] ** 8;
    var neighbor_bg: [8]f64 = [0.0] ** 8;
    var neighbors: usize = 0;
    var edge: f64 = 0.0;
    var dy: i32 = -1;
    while dy <= 1 {
        var dx: i32 = -1;
        while dx <= 1 {
            if dx != 0 or dy != 0 {
                const valid_x = (dx >= 0 or x >= 2) and (dx <= 0 or x + 2 < width);
                const valid_y = (dy >= 0 or y >= 2) and (dy <= 0 or y + 2 < height);
                if valid_x and valid_y {
                    var nx = x;
                    var ny = y;
                    if dx < 0 {
                        nx = x - 2;
                    } else if dx > 0 {
                        nx = x + 2;
                    }
                    if dy < 0 {
                        ny = y - 2;
                    } else if dy > 0 {
                        ny = y + 2;
                    }
                    const neighbor_index = (ny * width + nx) * 3;
                    neighbor_rg[neighbors] = (input[neighbor_index] as f64)
                    - (input[neighbor_index + 1] as f64);
                    neighbor_bg[neighbors] = (input[neighbor_index + 2] as f64)
                    - (input[neighbor_index + 1] as f64);
                    const difference = absolute(luminance(input, neighbor_index) - center_y);
                    if difference > edge {
                        edge = difference;
                    }
                    neighbors = neighbors + 1;
                }
            }
            dx = dx + 1;
        }
        dy = dy + 1;
    }
    if neighbors == 0 or edge < asset.edge_threshold_y {
        return input[index + channel];
    }
    const reference_rg = median(neighbor_rg, neighbors);
    const reference_bg = median(neighbor_bg, neighbors);
    const chroma_excess = absolute(center_rg - reference_rg)
    + absolute(center_bg - reference_bg);
    if chroma_excess <= asset.chroma_threshold {
        return input[index + channel];
    }
    const fraction = asset.strength
    * (chroma_excess - asset.chroma_threshold) / chroma_excess;
    const target_rg = center_rg + fraction * (reference_rg - center_rg);
    const target_bg = center_bg + fraction * (reference_bg - center_bg);
    const target_green = center_y - 0.2627 * target_rg - 0.0593 * target_bg;
    const green_change = target_green - (input[index + 1] as f64);
    const red_change = target_green + target_rg - (input[index] as f64);
    const blue_change = target_green + target_bg - (input[index + 2] as f64);
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

// Input and disjoint output are interleaved f32 RGB. Same-phase neighbors
// outside the image are omitted; halo is two pixels. Status 0 succeeds,
// 1 invalid asset, 2 shape/limit, 3 nonfinite input, 4 nonfinite result,
// 7 cancelled. A nonzero status invalidates output, even after partial writes.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: DefringeAsset, output: []f32,
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
                        const adjusted_result = adjusted(input, width, height, x, y, channel, asset);
                        if adjusted_result is result {
                            if pass == 1 {
                                if not core.finite_sample(result) {
                                    return 4;
                                }
                            } else {
                                output[index + channel] = result;
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
