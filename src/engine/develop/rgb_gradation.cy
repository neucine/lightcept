import .engine.core.core;
import .engine.core.sha256;

// Independently sampled RGB gradation v2. Input/output are normalized encoded
// RGB channel values in [0,1] in the asset's declared color domain, at
// unchanged pixel coordinates. Curves do not convert primaries or transfer.
// The operation cannot consume scene-linear RGB or an unnamed RGB16 buffer.
pub const algorithm_version: u32 = 2;
pub const maximum_nodes: usize = 32;
pub const maximum_pixels: usize = 33554432;
pub const SRGB_PRIMARIES: u32 = 1;
pub const DISPLAY_P3_PRIMARIES: u32 = 2;
pub const D65_WHITE: u32 = 1;
pub const IEC_SRGB_TRANSFER: u32 = 1;
pub const NORMALIZED_UNIT_SCALE: u32 = 1;

pub struct Domain {
    pub primaries: u32;
    pub white_point: u32;
    pub transfer: u32;
    pub scale: u32;
}

pub fn srgb_domain(): Domain {
    return {
        primaries: SRGB_PRIMARIES,
        white_point: D65_WHITE,
        transfer: IEC_SRGB_TRANSFER,
        scale: NORMALIZED_UNIT_SCALE
    };
}

pub fn display_p3_domain(): Domain {
    return {
        primaries: DISPLAY_P3_PRIMARIES,
        white_point: D65_WHITE,
        transfer: IEC_SRGB_TRANSFER,
        scale: NORMALIZED_UNIT_SCALE
    };
}

pub fn valid_domain(domain: Domain): bool {
    return (domain.primaries == SRGB_PRIMARIES
        or domain.primaries == DISPLAY_P3_PRIMARIES
    )
    and domain.white_point == D65_WHITE
    and domain.transfer == IEC_SRGB_TRANSFER
    and domain.scale == NORMALIZED_UNIT_SCALE;
}

pub fn is_srgb(domain: Domain): bool {
    return valid_domain(domain) and domain.primaries == SRGB_PRIMARIES;
}

pub struct Node {
    pub input: f64;
    pub output: f64;
}

pub struct Asset {
    pub version: u32;
    pub domain: Domain;
    pub red: [:]Node;
    pub green: [:]Node;
    pub blue: [:]Node;
}

// Editor recipe v2 uses five fixed input positions at 0, 0.25, 0.5,
// 0.75, and 1 in encoded sRGB. The endpoints are fixed. Each channel stores
// three output positions in thousandths of encoded range, ordered by input.
// Nondecreasing values preserve the component's monotone curve contract.
// Version 1 worker requests retain their straight interpolation.
pub const editor_algorithm_version: u32 = 2;

pub struct FivePointEdit {
    pub version: u32;
    pub luma: [3]i32;
    pub red: [3]i32;
    pub green: [3]i32;
    pub blue: [3]i32;
}

pub fn neutral_five_point_edit(): FivePointEdit {
    return {
        version: editor_algorithm_version,
        luma: [250, 500, 750],
        red: [250, 500, 750],
        green: [250, 500, 750],
        blue: [250, 500, 750]
    };
}

fn valid_editor_channel(values: [3]i32): bool {
    return values[0] >= 0 and values[0] <= values[1]
    and values[1] <= values[2] and values[2] <= 1000;
}

pub fn valid_five_point_edit(edit: FivePointEdit): bool {
    return (edit.version == 1 or edit.version == editor_algorithm_version)
    and valid_editor_channel(edit.luma)
    and valid_editor_channel(edit.red)
    and valid_editor_channel(edit.green)
    and valid_editor_channel(edit.blue);
}

fn editor_channel(values: [3]i32): [:]Node {
    const nodes: [:]Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.25,
            output: (values[0] as f64) / 1000.0
        }, {
            input: 0.5,
            output: (values[1] as f64) / 1000.0
        }, {
            input: 0.75,
            output: (values[2] as f64) / 1000.0
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    return nodes;
}

// Callers validate the recipe before use. A malformed recipe produces an
// invalid asset, which the component's application path rejects.
pub fn editor_asset(edit: FivePointEdit): Asset {
    const asset: Asset = {
        version: algorithm_version,
        domain: srgb_domain(),
        red: editor_channel(edit.red),
        green: editor_channel(edit.green),
        blue: editor_channel(edit.blue)
    };
    return asset;
}

fn valid_curve(nodes: []const Node): bool {
    if nodes.len() < 2 or nodes.len() > maximum_nodes {
        return false;
    }
    if nodes[0].input != 0.0 or nodes[0].output != 0.0 {
        return false;
    }
    const last = nodes.len() - 1;
    if nodes[last].input != 1.0 or nodes[last].output != 1.0 {
        return false;
    }
    var index: usize = 1;
    while index < nodes.len() {
        const left = nodes[index - 1];
        const right = nodes[index];
        if not (left.input >= 0.0 and left.input <= 1.0
            and left.output >= 0.0 and left.output <= 1.0
            and right.input >= 0.0 and right.input <= 1.0
            and right.output >= 0.0 and right.output <= 1.0
            and right.input > left.input and right.output >= left.output
            and right.output <= 1.0
        ) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn valid(asset: &const Asset): bool {
    return asset.version == algorithm_version and valid_domain(asset.domain)
    and valid_curve(asset.red[..])
    and valid_curve(asset.green[..]) and valid_curve(asset.blue[..]);
}

// SHA-256 over canonical v2 bytes: version u32, domain primaries, white,
// transfer, and scale u32 values, then each RGB curve's count u32 and
// input/output IEEE-754 f64 words, all big endian.
// Status 0 success, 1 invalid asset, 7 cancelled. A failed digest is invalid.
pub fn digest(asset: &const Asset, output: []u8,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid(asset) or output.len() != 32 {
        return 1;
    }
    var bytes: [1568]u8 = [0] ** 1568;
    bytes[3] = algorithm_version as u8;
    bytes[7] = asset.domain.primaries as u8;
    bytes[11] = asset.domain.white_point as u8;
    bytes[15] = asset.domain.transfer as u8;
    bytes[19] = asset.domain.scale as u8;
    var offset: usize = 20;
    var channel: usize = 0;
    while channel < 3 {
        if cancelled(context) {
            return 7;
        }
        var nodes: []const Node = asset.red[..];
        if channel == 1 {
            nodes = asset.green[..];
        }
        if channel == 2 {
            nodes = asset.blue[..];
        }
        bytes[offset + 3] = nodes.len() as u8;
        offset = offset + 4;
        var index: usize = 0;
        while index < nodes.len() {
            const words: [2]u64 = [nodes[index].input as! u64,
                nodes[index].output as! u64
            ];
            var word_index: usize = 0;
            while word_index < 2 {
                var byte_index: usize = 0;
                while byte_index < 8 {
                    const shift = ((7 - byte_index) * 8) as u32;
                    bytes[offset] = ((words[word_index] >> shift) & 255) as u8;
                    offset = offset + 1;
                    byte_index = byte_index + 1;
                }
                word_index = word_index + 1;
            }
            index = index + 1;
        }
        channel = channel + 1;
    }
    return sha256.digest(bytes[0..offset], output, cancelled, context);
}

fn sample(nodes: []const Node, value: f64): f64 {
    var right: usize = 1;
    while right < nodes.len() - 1 and value > nodes[right].input {
        right = right + 1;
    }
    const left = nodes[right - 1];
    const upper = nodes[right];
    return left.output + (value - left.input) *
    (upper.output - left.output) / (upper.input - left.input);
}

// Monotone cubic interpolation for the editor's equally spaced five nodes.
// Harmonic interior tangents and clamped endpoint tangents prevent overshoot.
fn editor_sample(nodes: []const Node, value: f64): f64 {
    var right: usize = 1;
    while right < 4 and value > nodes[right].input {
        right = right + 1;
    }
    const left = right - 1;
    const delta = (nodes[right].output - nodes[left].output) * 4.0;
    var before: f64 = delta;
    if left > 0 {
        const previous = (nodes[left].output - nodes[left - 1].output) * 4.0;
        if previous <= 0.0 or delta <= 0.0 {
            before = 0.0;
        } else {
            before = 2.0 * previous * delta / (previous + delta);
        }
    } else {
        const next = (nodes[2].output - nodes[1].output) * 4.0;
        before = 0.5 * (3.0 * delta - next);
        if before < 0.0 {
            before = 0.0;
        }
        if before > 3.0 * delta {
            before = 3.0 * delta;
        }
    }
    var after: f64 = delta;
    if right < 4 {
        const next = (nodes[right + 1].output - nodes[right].output) * 4.0;
        if delta <= 0.0 or next <= 0.0 {
            after = 0.0;
        } else {
            after = 2.0 * delta * next / (delta + next);
        }
    } else {
        const previous = (nodes[3].output - nodes[2].output) * 4.0;
        after = 0.5 * (3.0 * delta - previous);
        if after < 0.0 {
            after = 0.0;
        }
        if after > 3.0 * delta {
            after = 3.0 * delta;
        }
    }
    const t = (value - nodes[left].input) * 4.0;
    const t2 = t * t;
    const t3 = t2 * t;
    return (2.0 * t3 - 3.0 * t2 + 1.0) * nodes[left].output
    + (t3 - 2.0 * t2 + t) * before * 0.25
    + (-2.0 * t3 + 3.0 * t2) * nodes[right].output
    + (t3 - t2) * after * 0.25;
}

// Encoded sRGB luma Y' uses Rec.709 primaries. The same gain is applied to
// all three encoded channels before individual channel curves. Clipping at
// the sRGB gamut boundary can reduce saturation in bright colored pixels.
fn luma_gain(nodes: []const Node, red: f64, green: f64, blue: f64): f64 {
    const y = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    if y <= 0.0 {
        return 1.0;
    }
    return editor_sample(nodes, y) / y;
}

fn unit(value: f64): f64 {
    if value < 0.0 {
        return 0.0;
    }
    if value > 1.0 {
        return 1.0;
    }
    return value;
}

// Apply the same encoded-sRGB editor curve to already rendered opaque output.
// These bounded in-place paths keep pixel mathematics in the owning component.
// Status: 0 success, 1 invalid recipe, 2 invalid shape or limit, 7 cancelled.
pub fn apply_rgba8_in_place(output: []u8, width: usize, height: usize,
    edit: FivePointEdit, cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid_five_point_edit(edit) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width or output.len() != width * height * 4 {
        return 2;
    }
    const asset = editor_asset(edit);
    const luma = editor_channel(edit.luma);
    const neutral_points: [3]i32 = [250, 500, 750];
    const neutral_luma = edit.luma == neutral_points;
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 4;
            const red = (output[offset] as f64) / 255.0;
            const green = (output[offset + 1] as f64) / 255.0;
            const blue = (output[offset + 2] as f64) / 255.0;
            if edit.version == 1 {
                output[offset] = (sample(asset.red[..], red) * 255.0 + 0.5) as u8;
                output[offset + 1] = (sample(asset.green[..], green) * 255.0 + 0.5) as u8;
                output[offset + 2] = (sample(asset.blue[..], blue) * 255.0 + 0.5) as u8;
            } else {
                var gain: f64 = 1.0;
                if not neutral_luma {
                    gain = luma_gain(luma[..], red, green, blue);
                }
                output[offset] = (editor_sample(asset.red[..], unit(red * gain)) * 255.0 + 0.5) as u8;
                output[offset + 1] = (editor_sample(asset.green[..], unit(green * gain)) * 255.0 + 0.5) as u8;
                output[offset + 2] = (editor_sample(asset.blue[..], unit(blue * gain)) * 255.0 + 0.5) as u8;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}

// Interleaved encoded-sRGB RGB16, three channels per pixel; alpha is absent.
pub fn apply_rgb16_in_place(output: []u16, width: usize, height: usize,
    edit: FivePointEdit, cancelled: fn (usize): bool, context: usize
): u32 {
    if not valid_five_point_edit(edit) {
        return 1;
    }
    if width == 0 or height == 0 or width > maximum_pixels or
    height > maximum_pixels / width or output.len() != width * height * 3 {
        return 2;
    }
    const asset = editor_asset(edit);
    const luma = editor_channel(edit.luma);
    const neutral_points: [3]i32 = [250, 500, 750];
    const neutral_luma = edit.luma == neutral_points;
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < width {
            const offset = (row * width + column) * 3;
            const red = (output[offset] as f64) / 65535.0;
            const green = (output[offset + 1] as f64) / 65535.0;
            const blue = (output[offset + 2] as f64) / 65535.0;
            if edit.version == 1 {
                output[offset] = (sample(asset.red[..], red) * 65535.0 + 0.5) as u16;
                output[offset + 1] = (sample(asset.green[..], green) * 65535.0 + 0.5) as u16;
                output[offset + 2] = (sample(asset.blue[..], blue) * 65535.0 + 0.5) as u16;
            } else {
                var gain: f64 = 1.0;
                if not neutral_luma {
                    gain = luma_gain(luma[..], red, green, blue);
                }
                output[offset] = (editor_sample(asset.red[..], unit(red * gain)) * 65535.0 + 0.5) as u16;
                output[offset + 1] = (editor_sample(asset.green[..], unit(green * gain)) * 65535.0 + 0.5) as u16;
                output[offset + 2] = (editor_sample(asset.blue[..], unit(blue * gain)) * 65535.0 + 0.5) as u16;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}

// Interleaved, immutable encoded RGB f32 input in the asset's declared domain
// and disjoint caller output in the same domain.
// Linear interpolation between nodes; exact endpoints; no extrapolation or
// gamut clipping. Status: 0 success, 1 asset, 2 shape/limit, 3 input,
// 7 cancelled. Two passes check the entire input before writes and poll every
// row; any nonzero status invalidates output for publication.
pub fn apply_image(input: []const f32, width: usize, height: usize,
    asset: &const Asset, output: []f32,
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
                    if not core.finite_sample(value) or value < 0.0 or value > 1.0 {
                        return 3;
                    }
                    if pass == 1 {
                        if channel == 0 {
                            output[offset] = sample(asset.red[..], value as f64) as f32;
                        } else if channel == 1 {
                            output[offset + 1] = sample(asset.green[..], value as f64) as f32;
                        } else {
                            output[offset + 2] = sample(asset.blue[..], value as f64) as f32;
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
