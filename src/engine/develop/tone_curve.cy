import .engine.color.output_color;

// Diagnostic luminance-only scene-linear tone curve asset v1. Nodes span
// reference black to reference white in Rec.2020/D65 luminance. RGB receives
// one equal offset, preserving absolute channel differences and signed values.
pub const algorithm_version: u32 = 1;
pub const maximum_nodes: usize = 32;

pub struct CurveNode {
    pub input: f64;
    pub output: f64;
}

pub struct CurveAsset {
    pub version: u32;
    pub strength: f64;
    pub nodes: [:]CurveNode;
}

pub struct CurveResult {
    pub valid: bool;
    // 0 success, 1 invalid asset, 2 nonfinite input, 3 nonfinite output.
    pub status: u32;
    pub red: f64;
    pub green: f64;
    pub blue: f64;
}

fn finite(value: f64): bool {
    const infinity = output_color.exposure_gain_native(1024.0);
    return value > -infinity and value < infinity;
}

pub fn valid(asset: &const CurveAsset): bool {
    if asset.version != algorithm_version or asset.nodes.len() < 2 or asset.nodes.len() > maximum_nodes {
        return false;
    }
    if not (asset.strength >= 0.0 and asset.strength <= 1.0) {
        return false;
    }
    if asset.nodes[0].input != 0.0 or asset.nodes[0].output != 0.0 {
        return false;
    }
    const last = asset.nodes.len() - 1;
    if asset.nodes[last].input != 1.0 or asset.nodes[last].output != 1.0 {
        return false;
    }
    var index: usize = 1;
    while index < asset.nodes.len() {
        const left = asset.nodes[index - 1];
        const right = asset.nodes[index];
        if not (finite(left.input) and finite(left.output) and finite(right.input) and finite(right.output)) {
            return false;
        }
        if not (right.input > left.input and right.output >= left.output) {
            return false;
        }
        const slope = (right.output - left.output) / (right.input - left.input);
        if not (slope >= 0.0 and slope <= 4.0) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn mapped_luminance(nodes: []CurveNode, luminance: f64): f64 {
    var right: usize = 1;
    if luminance >= 1.0 {
        right = nodes.len() - 1;
    } else if luminance > 0.0 {
        while right < nodes.len() - 1 and luminance > nodes[right].input {
            right = right + 1;
        }
    }
    const left = nodes[right - 1];
    const upper = nodes[right];
    const slope = (upper.output - left.output) / (upper.input - left.input);
    return left.output + (luminance - left.input) * slope;
}

fn failure(status: u32): CurveResult {
    return {
        valid: false,
        status: status,
        red: 0.0,
        green: 0.0,
        blue: 0.0
    };
}

pub fn apply(asset: CurveAsset, red: f64, green: f64, blue: f64): CurveResult {
    if not valid(&asset) {
        return failure(1);
    }
    if not (finite(red) and finite(green) and finite(blue)) {
        return failure(2);
    }
    if asset.strength == 0.0 {
        return {
            valid: true,
            status: 0,
            red: red,
            green: green,
            blue: blue
        };
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const strength = asset.strength;
    const mapped = mapped_luminance(asset.nodes[..], y);
    const offset = strength * (mapped - y);
    const result: CurveResult = {
        valid: true,
        status: 0,
        red: (red + offset),
        green: (green + offset),
        blue: (blue + offset)
    };
    if not (finite(result.red) and finite(result.green) and finite(result.blue)) {
        return failure(3);
    }
    return result;
}
