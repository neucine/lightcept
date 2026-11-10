import .engine.core.core;
import .engine.color.output_color;
import .engine.develop.hue;
import .engine.develop.linear_chroma;
import std.math;

// HSL grading LUT v1 in scene-linear Rec.2020/D65 RGB. The asset is a complete
// 12 hue x 5 saturation x 5 luminance grid, ordered hue-major, then saturation,
// then luminance. Hue wraps; the other axes clamp. Nodes contain operations,
// not output RGB, so signed and out-of-gamut values retain their meaning.
pub const algorithm_version: u32 = 1;
pub const hue_steps: usize = 12;
pub const saturation_steps: usize = 5;
pub const luminance_steps: usize = 5;
pub const node_count: usize = 300;
pub const maximum_pixels: usize = 33554432;
pub const editor_band_count: usize = 8;
pub const editor_algorithm_version: u32 = 1;

pub struct GradeNode {
    // Opponent-plane hue rotation [-180,180] degrees; chroma gain [0,2];
    // luminance exposure [-2,2] stops. Neutral is (0,1,0).
    pub hue_degrees: f64;
    pub chroma_gain: f64;
    pub luminance_ev: f64;
}

pub struct GradeAsset {
    pub version: u32;
    pub nodes: []const GradeNode;
}

pub struct EightBandResult {
    pub valid: bool;
    pub nodes: [:]GradeNode;
}

// Compact editor recipe for eight hue bands in 45-degree steps. Each signed
// percentage is in [-100,100]. Hue maps to [-45,45] degrees, saturation to
// chroma gain [0,2], and luminance to [-1,1] EV. V1 stores all 24 integers.
pub struct EightBandEdit {
    pub version: u32;
    pub hue_percent: [8]i32;
    pub saturation_percent: [8]i32;
    pub luminance_percent: [8]i32;
}

pub fn neutral_eight_band_edit(): EightBandEdit {
    return {
        version: editor_algorithm_version,
        hue_percent: [0] ** 8,
        saturation_percent: [0] ** 8,
        luminance_percent: [0] ** 8
    };
}

pub fn valid_eight_band_edit(edit: EightBandEdit): bool {
    if edit.version != editor_algorithm_version {
        return false;
    }
    var index: usize = 0;
    while index < editor_band_count {
        if edit.hue_percent[index] < -100 or edit.hue_percent[index] > 100
        or edit.saturation_percent[index] < -100
        or edit.saturation_percent[index] > 100
        or edit.luminance_percent[index] < -100
        or edit.luminance_percent[index] > 100 {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn editor_nodes(edit: EightBandEdit): EightBandResult {
    if not valid_eight_band_edit(edit) {
        return {
            valid: false,
            nodes: []
        };
    }
    var bands: [8]GradeNode = [neutral_node()] ** 8;
    var index: usize = 0;
    while index < editor_band_count {
        bands[index] = {
            hue_degrees: (edit.hue_percent[index] as f64) * 0.45,
            chroma_gain: 1.0 + (edit.saturation_percent[index] as f64) / 100.0,
            luminance_ev: (edit.luminance_percent[index] as f64) / 100.0
        };
        index = index + 1;
    }
    return eight_band_nodes(bands);
}

pub struct LookupResult {
    // 0 success, 1 invalid asset, 2 invalid coordinate.
    pub status: u32;
    pub node: GradeNode;
}

pub fn neutral_node(): GradeNode {
    return {
        hue_degrees: 0.0,
        chroma_gain: 1.0,
        luminance_ev: 0.0
    };
}

// Translate eight evenly spaced hue bands (red at 0 degrees, then 45-degree
// steps) into the complete LUT. Every saturation and luminance plane receives
// the same operation. The interpolation wraps between the last and first band.
// The caller owns the returned nodes and must keep them alive with GradeAsset.
pub fn eight_band_nodes(bands: [8]GradeNode): EightBandResult {
    var band: usize = 0;
    while band < editor_band_count {
        const node = bands[band];
        if not (node.hue_degrees >= -180.0 and node.hue_degrees <= 180.0
            and node.chroma_gain >= 0.0 and node.chroma_gain <= 2.0
            and node.luminance_ev >= -2.0 and node.luminance_ev <= 2.0
        ) {
            return {
                valid: false,
                nodes: []
            };
        }
        band = band + 1;
    }
    var nodes: [:]GradeNode = [];
    var hue: usize = 0;
    while hue < hue_steps {
        const degrees = hue * 30;
        const left = degrees / 45;
        const right = (left + 1) % editor_band_count;
        const weight = ((degrees % 45) as f64) / 45.0;
        const a = bands[left];
        const b = bands[right];
        const node: GradeNode = {
            hue_degrees: a.hue_degrees + weight * (b.hue_degrees - a.hue_degrees),
            chroma_gain: a.chroma_gain + weight * (b.chroma_gain - a.chroma_gain),
            luminance_ev: a.luminance_ev + weight * (b.luminance_ev - a.luminance_ev)
        };
        var plane: usize = 0;
        while plane < saturation_steps * luminance_steps {
            nodes.push(node);
            plane = plane + 1;
        }
        hue = hue + 1;
    }
    return {
        valid: true,
        nodes: nodes
    };
}

pub fn valid(asset: &const GradeAsset): bool {
    if asset.version != algorithm_version or asset.nodes.len() != node_count {
        return false;
    }
    var index: usize = 0;
    while index < node_count {
        const node = asset.nodes[index];
        if not (node.hue_degrees >= -180.0 and node.hue_degrees <= 180.0
            and node.chroma_gain >= 0.0 and node.chroma_gain <= 2.0
            and node.luminance_ev >= -2.0 and node.luminance_ev <= 2.0
        ) {
            return false;
        }
        index = index + 1;
    }
    return true;
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

fn absolute(value: f64): f64 {
    if value < 0.0 {
        return -value;
    }
    return value;
}

fn maximum(a: f64, b: f64, c: f64): f64 {
    var value = a;
    if b > value {
        value = b;
    }
    if c > value {
        value = c;
    }
    return value;
}

fn minimum(a: f64, b: f64, c: f64): f64 {
    var value = a;
    if b < value {
        value = b;
    }
    if c < value {
        value = c;
    }
    return value;
}

// Input axes: conventional RGB hue in degrees; normalized scene chroma
// clamp((max-min)/(2*max(|Y|,0.18)),0,1); compressed nonnegative Y/(1+Y).
// Negative Y maps to the lowest luminance slice. None of these axes clips RGB.
pub fn coordinates(red: f64, green: f64, blue: f64): [3]f64 {
    const high = maximum(red, green, blue);
    const low = minimum(red, green, blue);
    const delta = high - low;
    var hue_degrees: f64 = 0.0;
    if delta > 0.0 {
        if high == red {
            hue_degrees = 60.0 * ((green - blue) / delta);
        } else if high == green {
            hue_degrees = 60.0 * (2.0 + (blue - red) / delta);
        } else {
            hue_degrees = 60.0 * (4.0 + (red - green) / delta);
        }
        if hue_degrees < 0.0 {
            hue_degrees = hue_degrees + 360.0;
        }
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    var reference = absolute(y);
    if reference < 0.18 {
        reference = 0.18;
    }
    var luminance: f64 = 0.0;
    if y > 0.0 {
        luminance = y / (1.0 + y);
    }
    return [hue_degrees, clamp01(delta / (2.0 * reference)), luminance];
}

fn index_of(h: usize, s: usize, l: usize): usize {
    return (h * saturation_steps + s) * luminance_steps + l;
}

// Trilinear interpolation of operation parameters. Hue location is periodic;
// parameter angle is linearly interpolated as signed degrees by policy.
fn lookup(asset: &const GradeAsset, axes: [3]f64): GradeNode {
    const h_position = axes[0] / 30.0;
    const h0 = h_position as usize;
    const h1 = (h0 + 1) % hue_steps;
    const fh = h_position - h0 as f64;
    const s_position = axes[1] * 4.0;
    var s0 = s_position as usize;
    if s0 > 3 {
        s0 = 3;
    }
    const fs = s_position - s0 as f64;
    const l_position = axes[2] * 4.0;
    var l0 = l_position as usize;
    if l0 > 3 {
        l0 = 3;
    }
    const fl = l_position - l0 as f64;
    var result: GradeNode = {
        hue_degrees: 0.0,
        chroma_gain: 0.0,
        luminance_ev: 0.0
    };
    var ih: usize = 0;
    while ih < 2 {
        var saturation_corner: usize = 0;
        while saturation_corner < 2 {
            var il: usize = 0;
            while il < 2 {
                var h = h0;
                if ih == 1 {
                    h = h1;
                }
                const node = asset.nodes[index_of(h, s0 + saturation_corner, l0 + il)];
                var weight = 1.0 - fh;
                if ih == 1 {
                    weight = fh;
                }
                if saturation_corner == 0 {
                    weight = weight * (1.0 - fs);
                } else {
                    weight = weight * fs;
                }
                if il == 0 {
                    weight = weight * (1.0 - fl);
                } else {
                    weight = weight * fl;
                }
                result.hue_degrees = result.hue_degrees + weight * node.hue_degrees;
                result.chroma_gain = result.chroma_gain + weight * node.chroma_gain;
                result.luminance_ev = result.luminance_ev + weight * node.luminance_ev;
                il = il + 1;
            }
            saturation_corner = saturation_corner + 1;
        }
        ih = ih + 1;
    }
    return result;
}

// Direct analytical sampler. Axes are hue degrees [0,360), normalized
// saturation [0,1], and compressed luminance [0,1]. Invalid input returns
// a neutral node with nonzero status; callers must check status before use.
pub fn lookup_at(asset: &const GradeAsset, axes: [3]f64): LookupResult {
    if not valid(asset) {
        return {
            status: 1,
            node: neutral_node()
        };
    }
    if not (axes[0] >= 0.0 and axes[0] < 360.0
        and axes[1] >= 0.0 and axes[1] <= 1.0
        and axes[2] >= 0.0 and axes[2] <= 1.0
    ) {
        return {
            status: 2,
            node: neutral_node()
        };
    }
    return {
        status: 0,
        node: lookup(asset, axes)
    };
}

pub fn grade_pixel(red: f64, green: f64, blue: f64,
    asset: &const GradeAsset
): [3]f64 {
    const node = lookup(asset, coordinates(red, green, blue));
    if node.hue_degrees == 0.0 and node.chroma_gain == 1.0
    and node.luminance_ev == 0.0 {
        return [red, green, blue];
    }
    const rotated = hue.rotate(red, green, blue, {
            version: hue.algorithm_version,
            angle_degrees: node.hue_degrees
        }
    );
    const chroma = linear_chroma.apply_native(rotated[0], rotated[1], rotated[2], node.chroma_gain);
    const gain = output_color.exposure_gain_native(node.luminance_ev);
    return [chroma.red * gain, chroma.green * gain, chroma.blue * gain];
}

// Immutable interleaved f64 scene-linear Rec.2020/D65 RGB and disjoint
// caller-owned output, each exactly width * height * 3 samples. The input
// range is [-0.25,8] and the output range is [-128,128]. Status and
// cancellation semantics match apply; no spatial halo or gamut clipping.
pub fn apply_f64(input: []const f64, width: usize, height: usize,
    asset: &const GradeAsset, output: []f64,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const count = width * height * 3;
    if input.len() != count or output.len() != count {
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
                    const sample = input[offset + channel];
                    if not (sample >= -0.25 and sample <= 8.0) {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = grade_pixel(input[offset], input[offset + 1],
                    input[offset + 2], asset
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -128.0 and result[channel] <= 128.0) {
                        return 4;
                    }
                    if pass == 1 {
                        output[offset + channel] = result[channel];
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

// Immutable interleaved f32 scene RGB [-0.25,8] and disjoint equal-size
// output. Signed values and out-of-gamut headroom remain; output [-128,128].
// Status: 0 success, 1 asset, 2 shape/limit, 3 input, 4 output, 7 cancelled.
// Two row-wise passes validate all values before writes; cancellation at each
// row invalidates partial output. No spatial halo or output gamut clip.
pub fn apply(input: []const f32, width: usize, height: usize,
    asset: &const GradeAsset, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels
    or height > maximum_pixels / width {
        return 2;
    }
    const count = width * height * 3;
    if input.len() != count or output.len() != count {
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
                    const sample = input[offset + channel];
                    if not core.finite_sample(sample) or sample < -0.25 or sample > 8.0 {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = grade_pixel(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64, asset
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -128.0 and result[channel] <= 128.0) {
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
