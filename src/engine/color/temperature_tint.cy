// Temperature/tint coordinate conversion, algorithm version 1.
// Adapted from LightCraft color/cct.rs at b3d392b; see NOTICE.
//
// White points are placed on the Planckian locus with the polynomial
// approximation published by Kim et al. for 1667 K through 25000 K. Outside
// that interval the locus is extended linearly in mired. The tint coordinate
// is a signed CIE 1960 Duv offset scaled by 3000; a positive value moves the
// white point toward green, so its correction is magenta.
import std.math;

const locus_min_kelvin: f64 = 1667.0;
const locus_max_kelvin: f64 = 25000.0;
const tint_scale: f64 = 3000.0;
const warm_locus_anchor_kelvin: f64 = 1717.0;
const cool_locus_anchor_kelvin: f64 = 24500.0;
const golden_ratio: f64 = 0.61803398875;

fn bounded(value: f64, low: f64, high: f64): f64 {
    if value < low {
        return low;
    }
    if value > high {
        return high;
    }
    return value;
}

fn cie1960_uv(xy: [2]f64): [2]f64 {
    const denominator = -2.0 * xy[0] + 12.0 * xy[1] + 3.0;
    return [4.0 * xy[0] / denominator, 6.0 * xy[1] / denominator];
}

fn planckian_xy(kelvin: f64): [2]f64 {
    const t2 = kelvin * kelvin;
    const t3 = t2 * kelvin;
    var x: f64 = 0.0;
    if kelvin <= 4000.0 {
        x = -266123900.0 / t3 - 234358.9 / t2 + 877.6956 / kelvin + 0.179910;
    } else {
        x = -3025846900.0 / t3 + 2107037.9 / t2 + 222.6347 / kelvin + 0.240390;
    }
    const x2 = x * x;
    const x3 = x2 * x;
    var y: f64 = 0.0;
    if kelvin <= 2222.0 {
        y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683;
    } else if kelvin <= 4000.0 {
        y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867;
    } else {
        y = 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483;
    }
    return cie1960_uv([x, y]);
}

fn locus_uv(kelvin: f64): [2]f64 {
    if kelvin >= locus_min_kelvin and kelvin <= locus_max_kelvin {
        return planckian_xy(kelvin);
    }
    var anchor_a = cool_locus_anchor_kelvin;
    var anchor_b = locus_max_kelvin;
    if kelvin < locus_min_kelvin {
        anchor_a = locus_min_kelvin;
        anchor_b = warm_locus_anchor_kelvin;
    }
    const first = planckian_xy(anchor_a);
    const second = planckian_xy(anchor_b);
    const position = (1000000.0 / kelvin - 1000000.0 / anchor_a) / (1000000.0 / anchor_b - 1000000.0 / anchor_a);
    return [first[0] + position * (second[0] - first[0]), first[1] + position * (second[1] - first[1])];
}

fn locus_normal(kelvin: f64): [2]f64 {
    const mired = 1000000.0 / kelvin;
    const warmer = locus_uv(1000000.0 / (mired + 1.0));
    const cooler = locus_uv(1000000.0 / bounded(mired - 1.0, 1.0, 1000000.0));
    const du = cooler[0] - warmer[0];
    const dv = cooler[1] - warmer[1];
    const length = math.sqrt_f64((du * du + dv * dv) as f64) as f64;
    if du < 0.0 {
        return [dv / length, -du / length];
    }
    return [-dv / length, du / length];
}

pub fn to_xy(kelvin: f64, tint: f64): [2]f64 {
    const base = locus_uv(kelvin);
    const normal = locus_normal(kelvin);
    const u = base[0] + normal[0] * tint / tint_scale;
    const v = base[1] + normal[1] * tint / tint_scale;
    const denominator = 2.0 * u - 8.0 * v + 4.0;
    return [3.0 * u / denominator, 2.0 * v / denominator];
}

fn mired_distance(mired: f64, uv: [2]f64): f64 {
    const on_locus = locus_uv(1000000.0 / mired);
    const du = uv[0] - on_locus[0];
    const dv = uv[1] - on_locus[1];
    return du * du + dv * dv;
}

pub fn from_xy(xy: [2]f64): [2]f64 {
    const uv = cie1960_uv(xy);
    var best_mired: f64 = 20.0;
    var candidate: f64 = 20.0;
    while candidate <= 1000.0 {
        if mired_distance(candidate, uv) < mired_distance(best_mired, uv) {
            best_mired = candidate;
        }
        candidate = candidate + 5.0;
    }
    var low = bounded(best_mired - 5.0, 20.0, 1000.0);
    var high = bounded(best_mired + 5.0, 20.0, 1000.0);
    var iteration: usize = 0;
    while iteration < 60 {
        const left = high - golden_ratio * (high - low);
        const right = low + golden_ratio * (high - low);
        if mired_distance(left, uv) < mired_distance(right, uv) {
            high = right;
        } else {
            low = left;
        }
        iteration = iteration + 1;
    }
    const kelvin = 1000000.0 / ((low + high) / 2.0);
    const base = locus_uv(kelvin);
    const normal = locus_normal(kelvin);
    const tint = ((uv[0] - base[0]) * normal[0] + (uv[1] - base[1]) * normal[1]) * tint_scale;
    return [kelvin, tint];
}
