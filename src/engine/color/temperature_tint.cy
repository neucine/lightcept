// Temperature/tint v1. Adapted from LightCraft color/cct.rs at b3d392b
// (MIT OR Apache-2.0; see NOTICE). Kim's Planckian approximation, extended
// linearly in mired outside 1667..25000 K. Tint = CIE 1960 Duv * 3000;
// positive source-green offset produces a magenta correction.
import std.math;

fn clamp(value: f64, low: f64, high: f64): f64 {
    if value < low {
        return low;
    }
    if value > high {
        return high;
    }
    return value;
}
fn xy_to_uv(xy: [2]f64): [2]f64 {
    const d = -2.0 * xy[0] + 12.0 * xy[1] + 3.0;
    return [4.0 * xy[0] / d, 6.0 * xy[1] / d];
}
fn kim_uv(t: f64): [2]f64 {
    const t2 = t * t;
    const t3 = t2 * t;
    var x: f64 = 0.0;
    if t <= 4000.0 {
        x = -266123900.0 / t3 - 234358.9 / t2 + 877.6956 / t + 0.179910;
    } else {
        x = -3025846900.0 / t3 + 2107037.9 / t2 + 222.6347 / t + 0.240390;
    }
    const x2 = x * x;
    const x3 = x2 * x;
    var y: f64 = 0.0;
    if t <= 2222.0 {
        y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683;
    } else if t <= 4000.0 {
        y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867;
    } else {
        y = 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483;
    }
    return xy_to_uv([x, y]);
}
fn locus(t: f64): [2]f64 {
    if t >= 1667.0 and t <= 25000.0 {
        return kim_uv(t);
    }
    var a: f64 = 24500.0;
    var b: f64 = 25000.0;
    if t < 1667.0 {
        a = 1667.0;
        b = 1717.0;
    }
    const first = kim_uv(a);
    const second = kim_uv(b);
    const s = (1000000.0 / t - 1000000.0 / a) / (1000000.0 / b - 1000000.0 / a);
    return [first[0] + s * (second[0] - first[0]), first[1] + s * (second[1] - first[1])];
}
fn normal(t: f64): [2]f64 {
    const m = 1000000.0 / t;
    const a = locus(1000000.0 / (m + 1.0));
    const b = locus(1000000.0 / clamp(m - 1.0, 1.0, 1000000.0));
    const du = b[0] - a[0];
    const dv = b[1] - a[1];
    const length = math.sqrt_f64((du * du + dv * dv) as f64) as f64;
    if du < 0.0 {
        return [dv / length, -du / length];
    }
    return [-dv / length, du / length];
}
pub fn to_xy(kelvin: f64, tint: f64): [2]f64 {
    const base = locus(kelvin);
    const n = normal(kelvin);
    const u = base[0] + n[0] * tint / 3000.0;
    const v = base[1] + n[1] * tint / 3000.0;
    const d = 2.0 * u - 8.0 * v + 4.0;
    return [3.0 * u / d, 2.0 * v / d];
}
fn distance(mired: f64, uv: [2]f64): f64 {
    const p = locus(1000000.0 / mired);
    const du = uv[0] - p[0];
    const dv = uv[1] - p[1];
    return du * du + dv * dv;
}
pub fn from_xy(xy: [2]f64): [2]f64 {
    const uv = xy_to_uv(xy);
    var best: f64 = 20.0;
    var m: f64 = 20.0;
    while m <= 1000.0 {
        if distance(m, uv) < distance(best, uv) {
            best = m;
        }
        m = m + 5.0;
    }
    var low = clamp(best - 5.0, 20.0, 1000.0);
    var high = clamp(best + 5.0, 20.0, 1000.0);
    const golden: f64 = 0.61803398875;
    var iteration: usize = 0;
    while iteration < 60 {
        const left = high - golden * (high - low);
        const right = low + golden * (high - low);
        if distance(left, uv) < distance(right, uv) {
            high = right;
        } else {
            low = left;
        }
        iteration = iteration + 1;
    }
    const kelvin = 1000000.0 / ((low + high) / 2.0);
    const base = locus(kelvin);
    const n = normal(kelvin);
    return [kelvin, ((uv[0] - base[0]) * n[0] + (uv[1] - base[1]) * n[1]) * 3000.0];
}
