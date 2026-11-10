import std.math;

// Exact binary32 coefficients used by the spatial reconstruction policy.
const logarithm_floor_bits: u32 = 730643660; // approximately 1e-12
const ratio_floor_bits: u32 = 814313567; // approximately 1e-09
const luminance_floor_bits: u32 = 897988541; // approximately 1e-06
const minimum_source_sum_bits: u32 = 953267991; // approximately 0.0001
const minimum_reference_channel_bits: u32 = 981668463; // approximately 0.001
const pyramid_prior_weight_bits: u32 = 1008981770; // approximately 0.01
const rim_mix_start_ev_bits: u32 = 1022739087; // approximately 0.03
const rim_trust_weight_bits: u32 = 1028443341; // approximately 0.05
const edge_transition_start_ev_bits: u32 = 1041865114; // approximately 0.15
const saturation_transition_start_bits: u32 = 1045220557; // approximately 0.2
const rim_mix_end_ev_bits: u32 = 1047233823; // approximately 0.23
const edge_transition_end_ev_bits: u32 = 1053609165; // approximately 0.4
const source_weight_full_scale_bits: u32 = 1058642330; // approximately 0.6
const near_clip_support_width_bits: u32 = 1041865114; // approximately 0.15, normalized camera RGB
const saturation_transition_end_bits: u32 = 1053609165; // approximately 0.4, unitless
const near_clip_support_start_bits: u32 = 1062836634; // approximately 0.85
const clip_threshold_bits: u32 = 1065185444; // approximately 0.99
const maximum_white_balance_gain_bits: u32 = 1107296256; // approximately 32
const maximum_log_ratio_ev_bits: u32 = 1115684864; // approximately 64
const largest_finite_bits: u32 = 2139095039; // approximately 3.402823e+38

// Spatial highlight reconstruction, algorithm version 5, on demosaiced camera
// RGB. The caller owns every buffer; this component owns the source estimate,
// the multi-resolution prior, the rim estimate, and the per-pixel repair.
//
// The policy is local and evidence-driven:
//   1. Build a half-resolution source estimate from unclipped neighbours whose
//      channel ratios and luminance agree with the clipped pixel.
//   2. Extend that estimate over a small pyramid so colour can be borrowed
//      across a wider radius without inventing detail.
//   3. Estimate a four-channel rim sample from near-clip pixels so the repair
//      can distinguish a genuinely bright object from a clipped edge.
//   4. For each clipped pixel, blend a neutral and a colour-borrowed repair.
//      Support trust, exposure contradiction, rim disagreement, and saturation
//      each move the blend toward the conservative reconstruction.
//
// All thresholds are exact binary32 bit patterns so the result is independent
// of decimal literal parsing. All work is scalar and in place; the function
// returns a status code rather than aborting.

fn read_f32(p: *const f32, i: usize): f32 {
    unchecked {
        return *(((p as! usize) + i * 4) as! *const f32) as f32;
    }
}
fn write_f32(p: *f32, i: usize, value: f32): void {
    unchecked {
        *(((p as! usize) + i * 4) as! *f32) = value as f32;
    }
}
fn read_u8(p: *const u8, i: usize): u32 {
    unchecked {
        return *(((p as! usize) + i) as! *const u8) as u32;
    }
}
fn write_u8(p: *u8, i: usize, value: u32): void {
    unchecked {
        *(((p as! usize) + i) as! *u8) = value as u8;
    }
}
fn read_usize(p: *const usize, i: usize): usize {
    unchecked {
        return *(((p as! usize) + i * 8) as! *const usize) as usize;
    }
}
// Decimal f64-to-f32 casts are exactness-checked by this Cyna toolchain.
// Bit reinterpretation provides the intended rounded f32 constants without a
// runtime trap. For example: 1065185444 = 0.99, 1041865114 = 0.15,
// 1053609165 = 0.4, and 1065353216 = 1.0 (IEEE-754 binary32).
fn bits_value(bits: u32): f32 {
    unchecked {
        return bits as! f32;
    }
}
fn min(a: f32, b: f32): f32 {
    if a < b {
        return a;
    }
    return b;
}
fn max(a: f32, b: f32): f32 {
    if a > b {
        return a;
    }
    return b;
}
fn max_three(a: f32, b: f32, c: f32): f32 {
    return max(max(a, b), c);
}
fn clamp(v: f32, lo: f32, hi: f32): f32 {
    return min(max(v, lo), hi);
}
fn smooth(e0: f32, e1: f32, v: f32): f32 {
    const t = clamp((v - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * ((3.0 as f32) - (2.0 as f32) * t);
}
fn ceil_div(v: usize, d: usize): usize {
    return (v + d - 1) / d;
}
fn any_channel_clipped(rgb: *const f32, pixel: usize): bool {
    return read_f32(rgb, pixel * 3) >= bits_value(clip_threshold_bits) or read_f32(rgb, pixel * 3 + 1) >= bits_value(clip_threshold_bits) or read_f32(rgb, pixel * 3 + 2) >= bits_value(clip_threshold_bits);
}
fn support_needed(near: *const u8, cw: usize, ch: usize, x: usize, y: usize): bool {
    var yy = y;
    if yy > 0 {
        yy = yy - 1;
    }
    const last = min_usize(y + 1, ch - 1);
    while yy <= last {
        if read_u8(near, yy * cw + x) != 0 {
            return true;
        }
        yy = yy + 1;
    }
    return false;
}
fn min_usize(a: usize, b: usize): usize {
    if a < b {
        return a;
    }
    return b;
}

// Metadata triples are [element offset, width, height].
fn texel(p: *const f32, meta: *const usize, level: usize, n: usize, x: usize, y: usize, channel: usize): f32 {
    const offset = read_usize(meta, level * 3);
    const width = read_usize(meta, level * 3 + 1);
    return read_f32(p, offset + (y * width + x) * n + channel);
}
fn write_texel(p: *f32, meta: *const usize, level: usize, n: usize, x: usize, y: usize, channel: usize, value: f32): void {
    const offset = read_usize(meta, level * 3);
    const width = read_usize(meta, level * 3 + 1);
    write_f32(p, offset + (y * width + x) * n + channel, value);
}
fn interpolate(p: *const f32, meta: *const usize, level: usize, n: usize, scale: f32, x: usize, y: usize): [4]f32 {
    const w = read_usize(meta, level * 3 + 1);
    const h = read_usize(meta, level * 3 + 2);
    const fx = clamp(((x as f32) + (0.5 as f32)) / scale - (0.5 as f32), 0.0, (w - 1) as f32);
    const fy = clamp(((y as f32) + (0.5 as f32)) / scale - (0.5 as f32), 0.0, (h - 1) as f32);
    const x0 = math.floor_f32(fx as f32) as usize;
    const y0 = math.floor_f32(fy as f32) as usize;
    const x1 = min_usize(x0 + 1, w - 1);
    const y1 = min_usize(y0 + 1, h - 1);
    const tx = fx - x0 as f32;
    const ty = fy - y0 as f32;
    var result: [4]f32 = [0.0, 0.0, 0.0, 0.0];
    var k: usize = 0;
    while k < n {
        const a = texel(p, meta, level, n, x0, y0, k);
        const b = texel(p, meta, level, n, x1, y0, k);
        const c = texel(p, meta, level, n, x0, y1, k);
        const d = texel(p, meta, level, n, x1, y1, k);
        result[k] = (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty;
        k = k + 1;
    }
    return result;
}

// Estimate source colour per two-by-two pixel cell. Only unclipped pixels that
// are bright enough and whose camera-space sum is meaningful contribute. The
// output triples are [red-weighted, blue-weighted, weight]; green follows from
// the neutral assumption. `lum` and `touched` are cell-resolution scratch data.
fn estimate_source_texels(rgb: *const f32, w: usize, h: usize, wb: [3]f32, source: *f32, meta: *const usize, lum: *f32, touched: *u8, near: *u8): void {
    const cw = ceil_div(w, 2);
    const ch = ceil_div(h, 2);
    var y: usize = 0;
    while y < ch {
        var x: usize = 0;
        while x < cw {
            var red: f32 = 0.0;
            var blue: f32 = 0.0;
            var weight: f32 = 0.0;
            var sum: f32 = 0.0;
            var count: usize = 0;
            var hit: u32 = 0;
            var sy = y * 2;
            while sy < min_usize(y * 2 + 2, h) {
                var sx = x * 2;
                while sx < min_usize(x * 2 + 2, w) {
                    const i = sy * w + sx;
                    const p0 = read_f32(rgb, i * 3);
                    const p1 = read_f32(rgb, i * 3 + 1);
                    const p2 = read_f32(rgb, i * 3 + 2);
                    const q0 = p0 * wb[0];
                    const q1 = p1 * wb[1];
                    const q2 = p2 * wb[2];
                    const s = max(q0, 0.0) + max(q1, 0.0) + max(q2, 0.0);
                    sum = sum + s;
                    count = count + 1;
                    if any_channel_clipped(rgb, i) {
                        hit = 1;
                    } else if max_three(p0, p1, p2) > (0.25 as f32) * bits_value(clip_threshold_bits) and s > bits_value(minimum_source_sum_bits) {
                        const b = smooth(0.25, bits_value(source_weight_full_scale_bits), max_three(p0, p1, p2) / bits_value(clip_threshold_bits)) / s;
                        red = red + b * max(q0, 0.0);
                        blue = blue + b * max(q2, 0.0);
                        weight = weight + b * s;
                    }
                    sx = sx + 1;
                }
                sy = sy + 1;
            }
            const k = (1.0 as f32) / count as f32;
            write_texel(source, meta, 0, 3, x, y, 0, red * k);
            write_texel(source, meta, 0, 3, x, y, 1, blue * k);
            write_texel(source, meta, 0, 3, x, y, 2, weight * k);
            write_f32(lum, y * cw + x, max(sum * k, bits_value(luminance_floor_bits)));
            write_u8(touched, y * cw + x, hit);
            x = x + 1;
        }
        y = y + 1;
    }
    y = 0;
    while y < ch {
        var x: usize = 0;
        while x < cw {
            var hit: u32 = 0;
            var xx = x;
            if xx > 0 {
                xx = xx - 1;
            }
            while xx <= min_usize(x + 1, cw - 1) {
                if read_u8(touched, y * cw + xx) != 0 {
                    hit = 1;
                }
                xx = xx + 1;
            }
            write_u8(near, y * cw + x, hit);
            x = x + 1;
        }
        y = y + 1;
    }
    const edge_lo = math.exp2_f32(bits_value(edge_transition_start_ev_bits) as f32) as f32;
    const edge_hi = math.exp2_f32(bits_value(edge_transition_end_ev_bits) as f32) as f32;
    y = 0;
    while y < ch {
        var x: usize = 0;
        while x < cw {
            const weight = texel(source, meta, 0, 3, x, y, 2);
            if weight > (0.0 as f32) {
                var close = false;
                var yy = y;
                if yy > 0 {
                    yy = yy - 1;
                }
                while yy <= min_usize(y + 1, ch - 1) {
                    if read_u8(near, yy * cw + x) != 0 {
                        close = true;
                    }
                    yy = yy + 1;
                }
                var keep: f32 = 0.0;
                if not close {
                    const l = read_f32(lum, y * cw + x);
                    var lo = l;
                    var hi = l;
                    yy = y;
                    if yy > 0 {
                        yy = yy - 1;
                    }
                    while yy <= min_usize(y + 1, ch - 1) {
                        var xx = x;
                        if xx > 0 {
                            xx = xx - 1;
                        }
                        while xx <= min_usize(x + 1, cw - 1) {
                            const v = read_f32(lum, yy * cw + xx);
                            lo = min(lo, v);
                            hi = max(hi, v);
                            xx = xx + 1;
                        }
                        yy = yy + 1;
                    }
                    keep = (1.0 as f32) - smooth(edge_lo, edge_hi, max(hi / l, l / lo));
                }
                var c: usize = 0;
                while c < 3 {
                    write_texel(source, meta, 0, 3, x, y, c, texel(source, meta, 0, 3, x, y, c) * keep);
                    c = c + 1;
                }
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

// Box-filter the previous pyramid level into the current one.
fn build_mip_level(p: *f32, meta: *const usize, level: usize, n: usize): void {
    const sw = read_usize(meta, (level - 1) * 3 + 1);
    const sh = read_usize(meta, (level - 1) * 3 + 2);
    const w = read_usize(meta, level * 3 + 1);
    const h = read_usize(meta, level * 3 + 2);
    var y: usize = 0;
    while y < h {
        var x: usize = 0;
        while x < w {
            var sum: [4]f32 = [0.0, 0.0, 0.0, 0.0];
            var count: usize = 0;
            var sy = y * 2;
            while sy < min_usize(y * 2 + 2, sh) {
                var sx = x * 2;
                while sx < min_usize(x * 2 + 2, sw) {
                    var c: usize = 0;
                    while c < n {
                        sum[c] = sum[c] + texel(p, meta, level - 1, n, sx, sy, c);
                        c = c + 1;
                    }
                    count = count + 1;
                    sx = sx + 1;
                }
                sy = sy + 1;
            }
            var c: usize = 0;
            while c < n {
                write_texel(p, meta, level, n, x, y, c, sum[c] / count as f32);
                c = c + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

// Pull coarse colour back down the pyramid. Coarse samples act as a weak prior
// for fine cells that have little or no direct support; `limit_base` keeps
// unsupported base cells neutral and stops them from borrowing across a gap.
fn spread_priors(p: *f32, meta: *const usize, levels: usize, n: usize, near: *const u8, limit_base: bool, neutral: [3]f32): void {
    const top = levels - 1;
    const tw = read_usize(meta, top * 3 + 1);
    const th = read_usize(meta, top * 3 + 2);
    var y: usize = 0;
    while y < th {
        var x: usize = 0;
        while x < tw {
            const weight = texel(p, meta, top, n, x, y, n - 1);
            var c: usize = 0;
            while c < n - 1 {
                var value: f32 = 0.0;
                if weight > (0.0 as f32) {
                    value = texel(p, meta, top, n, x, y, c) / weight;
                } else if limit_base and c == 0 {
                    value = neutral[0];
                } else if limit_base and c == 1 {
                    value = neutral[2];
                }
                write_texel(p, meta, top, n, x, y, c, value);
                c = c + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    var level = top;
    while level > 0 {
        const fine = level - 1;
        const w = read_usize(meta, fine * 3 + 1);
        const h = read_usize(meta, fine * 3 + 2);
        y = 0;
        while y < h {
            var x: usize = 0;
            while x < w {
                if not (limit_base and fine == 0 and not support_needed(near, w, h, x, y)) {
                    const prior = interpolate(p, meta, level, n, 2.0, x, y);
                    const weight = texel(p, meta, fine, n, x, y, n - 1);
                    var c: usize = 0;
                    while c < n - 1 {
                        const v = (texel(p, meta, fine, n, x, y, c) + bits_value(pyramid_prior_weight_bits) * prior[c]) / (weight + bits_value(pyramid_prior_weight_bits));
                        write_texel(p, meta, fine, n, x, y, c, v);
                        c = c + 1;
                    }
                }
                x = x + 1;
            }
            y = y + 1;
        }
        level = fine;
    }
}

// Estimate a four-channel rim sample per four-by-four pixel cell. Near-clip
// pixels dominate with a quartic weight; the fourth channel is the accumulated
// weight and tells the caller whether the rim cell holds usable evidence.
fn estimate_rim_texels(rgb: *const f32, w: usize, h: usize, wb: [3]f32, rim: *f32, meta: *const usize, near: *const u8): void {
    const rw = ceil_div(w, 4);
    const rh = ceil_div(h, 4);
    const cw = ceil_div(w, 2);
    const ch = ceil_div(h, 2);
    var y: usize = 0;
    while y < rh {
        var x: usize = 0;
        while x < rw {
            var sum: [4]f32 = [0.0, 0.0, 0.0, 0.0];
            var count: usize = 0;
            var sy = y * 4;
            while sy < min_usize(y * 4 + 4, h) {
                var sx = x * 4;
                while sx < min_usize(x * 4 + 4, w) {
                    count = count + 1;
                    const i = sy * w + sx;
                    const p0 = read_f32(rgb, i * 3);
                    const p1 = read_f32(rgb, i * 3 + 1);
                    const p2 = read_f32(rgb, i * 3 + 2);
                    const top = max_three(p0, p1, p2) / bits_value(clip_threshold_bits);
                    if top >= bits_value(near_clip_support_start_bits) and top < (1.0 as f32) and not any_channel_clipped(rgb, i) and not support_needed(near, cw, ch, sx / 2, sy / 2) {
                        const base = (top - bits_value(near_clip_support_start_bits)) / bits_value(near_clip_support_width_bits);
                        const k = base * base * base * base;
                        sum[0] = sum[0] + k * p0 * wb[0];
                        sum[1] = sum[1] + k * p1 * wb[1];
                        sum[2] = sum[2] + k * p2 * wb[2];
                        sum[3] = sum[3] + k;
                    }
                    sx = sx + 1;
                }
                sy = sy + 1;
            }
            var c: usize = 0;
            while c < 4 {
                write_texel(rim, meta, 0, 4, x, y, c, sum[c] / count as f32);
                c = c + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

// Replace the base weight of cells near clipped pixels with the best support
// weight found in any sufficiently coarse pyramid level within reach.
fn measure_support_trust(source: *f32, meta: *const usize, levels: usize, near: *const u8, w: usize, h: usize): void {
    const cw = read_usize(meta, 1);
    const ch = read_usize(meta, 2);
    const reach = (0.25 as f32) * max(w as f32, h as f32) / (2.0 as f32);
    var widest: usize = levels - 1;
    var i: usize = 0;
    var scale: f32 = 1.0;
    while i < levels and scale < reach {
        scale = scale * (2.0 as f32);
        i = i + 1;
    }
    if i < levels {
        widest = i;
    }
    var y: usize = 0;
    while y < ch {
        var x: usize = 0;
        while x < cw {
            if support_needed(near, cw, ch, x, y) {
                var trust: f32 = 0.0;
                var level: usize = 1;
                var step: f32 = 2.0;
                while level <= widest and trust < (1.0 as f32) {
                    const e = interpolate(source, meta, level, 3, step, x, y);
                    trust = max(trust, smooth(0.0, bits_value(rim_trust_weight_bits), e[2]));
                    step = step * (2.0 as f32);
                    level = level + 1;
                }
                write_texel(source, meta, 0, 3, x, y, 2, trust);
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

fn clip_bound(p: [3]f32, cl: [3]bool, c: usize): f32 {
    if cl[c] {
        return 1.0;
    }
    return smooth(0.75, 1.0, p[c] / bits_value(clip_threshold_bits));
}
// Measure how many stops of unexplained exposure separate the clipped pixel
// from the borrowed source colour. A large value means the support is probably
// not the same object, so trust should fall.
fn exposure_contradiction(p: [3]f32, q: [3]f32, cl: [3]bool, r: [3]f32): f32 {
    var lo: f32 = bits_value(largest_finite_bits);
    var hi: f32 = 0.0;
    var c: usize = 0;
    while c < 3 {
        const level = q[c] / max(r[c], bits_value(minimum_reference_channel_bits));
        hi = max(hi, level);
        const b = clip_bound(p, cl, c);
        if r[c] > bits_value(minimum_reference_channel_bits) and b < (1.0 as f32) {
            lo = min(lo, level / ((1.0 as f32) - b));
        }
        c = c + 1;
    }
    if hi > (0.0 as f32) and lo > (0.0 as f32) and lo < bits_value(largest_finite_bits) {
        return max(math.log2_f32((hi / lo) as f32) as f32, 0.0);
    }
    return 0.0;
}
// Largest pairwise log-ratio distance between two chromaticities. Values are
// floor-limited so a near-black channel cannot dominate the result.
fn log_chroma_distance(a: [3]f32, b: [3]f32): f32 {
    var result: f32 = 0.0;
    var i: usize = 0;
    while i < 3 {
        var j = i + 1;
        while j < 3 {
            const ratio = max(a[i], bits_value(luminance_floor_bits)) * max(b[j], bits_value(luminance_floor_bits)) / (max(a[j], bits_value(luminance_floor_bits)) * max(b[i], bits_value(luminance_floor_bits)));
            result = max(result, max(math.log2_f32(ratio as f32) as f32, -(math.log2_f32(ratio as f32) as f32)));
            j = j + 1;
        }
        i = i + 1;
    }
    return result;
}
struct Reconstruction {
    valid: bool;
    value: [3]f32;
}
// Reconstruct one pixel's clipped channels from a reference colour `r`.
// `p` is camera RGB, `q` is white-balanced camera RGB, and `cl` marks the
// channels at or above the clip threshold. Unclipped channels provide the
// ratio evidence; a fully clipped pixel inherits the reference level.
fn reconstruct_level(p: [3]f32, q: [3]f32, cl: [3]bool, r: [3]f32, max_level: f32): Reconstruction {
    var sum: f32 = 0.0;
    var near_clip: f32 = 0.0;
    var count: usize = 0;
    var floor: f32 = 0.0;
    var c: usize = 0;
    while c < 3 {
        if cl[c] {
            floor = max(floor, q[c] / max(r[c], bits_value(minimum_reference_channel_bits)));
        } else if r[c] > bits_value(minimum_reference_channel_bits) {
            const s = q[c] / r[c];
            sum = sum + s;
            near_clip = max(near_clip, s * smooth(0.75, 1.0, p[c] / bits_value(clip_threshold_bits)));
            count = count + 1;
        }
        c = c + 1;
    }
    if count == 0 {
        return {
            valid: false,
            value: [0.0, 0.0, 0.0]
        };
    }
    const top = max(max_three(r[0], r[1], r[2]), bits_value(minimum_reference_channel_bits));
    const level = max(sum / count as f32, min(max(near_clip, floor), max_level / top));
    var out: [3]f32 = q;
    c = 0;
    while c < 3 {
        if cl[c] {
            out[c] = max(q[c], level * r[c]);
        }
        c = c + 1;
    }
    return {
        valid: true,
        value: out
    };
}

// Repair every clipped pixel in place, dividing the result back out of white
// balance so the output stays in camera RGB.
fn repair_clipped_pixels(rgb: *f32, w: usize, h: usize, wb: [3]f32, source: *const f32, smeta: *const usize, rim: *const f32, rmeta: *const usize, has_rim: bool): void {
    const max_level = max_three(wb[0], wb[1], wb[2]) * bits_value(clip_threshold_bits);
    var y: usize = 0;
    while y < h {
        var x: usize = 0;
        while x < w {
            const i = y * w + x;
            if any_channel_clipped(rgb, i) {
                const p: [3]f32 = [read_f32(rgb, i * 3), read_f32(rgb, i * 3 + 1), read_f32(rgb, i * 3 + 2)];
                const q: [3]f32 = [p[0] * wb[0], p[1] * wb[1], p[2] * wb[2]];
                const cl: [3]bool = [p[0] >= bits_value(clip_threshold_bits), p[1] >= bits_value(clip_threshold_bits), p[2] >= bits_value(clip_threshold_bits)];
                const e = interpolate(source, smeta, 0, 3, 2.0, x, y);
                const borrowed: [3]f32 = [e[0], (1.0 as f32) - e[0] - e[1], e[1]];
                var edge: [4]f32 = [0.0, 0.0, 0.0, 0.0];
                if has_rim {
                    edge = interpolate(rim, rmeta, 0, 4, 4.0, x, y);
                }
                var trust = clamp(e[2], 0.0, 1.0);
                if trust > (0.0 as f32) {
                    var off = exposure_contradiction(p, q, cl, borrowed);
                    if off > bits_value(edge_transition_start_ev_bits) {
                        if has_rim {
                            const s = edge[0] + edge[1] + edge[2];
                            if s > bits_value(luminance_floor_bits) {
                                const other: [3]f32 = [edge[0] / s, edge[1] / s, edge[2] / s];
                                off = min(off, log_chroma_distance(other, borrowed));
                            } else {
                                off = 0.0;
                            }
                        } else {
                            off = 0.0;
                        }
                    }
                    trust = trust * ((1.0 as f32) - smooth(bits_value(edge_transition_start_ev_bits), bits_value(edge_transition_end_ev_bits), off));
                }
                var rim_mix: f32 = 1.0;
                var rim_rebuilt = Reconstruction {
                    valid: false,
                    value: [0.0, 0.0, 0.0]
                };
                if has_rim {
                    var ratio: f32 = 1.0;
                    var c: usize = 0;
                    while c < 3 {
                        const a = max(q[c], bits_value(logarithm_floor_bits));
                        const b = max(edge[c], bits_value(logarithm_floor_bits));
                        var value = a / b;
                        if a < b {
                            const weight = clip_bound(p, cl, c);
                            if weight <= (0.0 as f32) {
                                value = b / a;
                            } else if weight >= (1.0 as f32) {
                                value = 1.0;
                            } else {
                                value = math.pow_f32((b / a) as f32, ((1.0 as f32) - weight) as f32) as f32;
                            }
                        }
                        ratio = max(ratio, value);
                        c = c + 1;
                    }
                    const past = min(math.log2_f32(ratio as f32) as f32, bits_value(maximum_log_ratio_ev_bits));
                    rim_mix = smooth(bits_value(rim_mix_start_ev_bits), bits_value(rim_mix_end_ev_bits), past);
                    const s = edge[0] + edge[1] + edge[2];
                    if (1.0 as f32) > rim_mix and s > bits_value(luminance_floor_bits) {
                        const color: [3]f32 = [edge[0] / s, edge[1] / s, edge[2] / s];
                        rim_rebuilt = reconstruct_level(p, q, cl, color, max_level);
                    }
                }
                const neutral: [3]f32 = [(1.0 as f32) / (3.0 as f32), (1.0 as f32) / (3.0 as f32), (1.0 as f32) / (3.0 as f32)];
                var local = Reconstruction {
                    valid: false,
                    value: [0.0, 0.0, 0.0]
                };
                var plain = Reconstruction {
                    valid: false,
                    value: [0.0, 0.0, 0.0]
                };
                if trust > (0.0 as f32) {
                    local = reconstruct_level(p, q, cl, borrowed, max_level);
                }
                if trust < (1.0 as f32) {
                    plain = reconstruct_level(p, q, cl, neutral, max_level);
                }
                var c: usize = 0;
                while c < 3 {
                    if rim_rebuilt.valid {
                        if local.valid {
                            local.value[c] = rim_rebuilt.value[c] + (local.value[c] - rim_rebuilt.value[c]) * rim_mix;
                        }
                        if plain.valid {
                            plain.value[c] = rim_rebuilt.value[c] + (plain.value[c] - rim_rebuilt.value[c]) * rim_mix;
                        }
                    }
                    c = c + 1;
                }
                var out: [3]f32 = [0.0, 0.0, 0.0];
                if local.valid and plain.valid {
                    c = 0;
                    while c < 3 {
                        out[c] = plain.value[c] + (local.value[c] - plain.value[c]) * trust;
                        c = c + 1;
                    }
                } else if local.valid {
                    out = local.value;
                } else if plain.valid {
                    out = plain.value;
                } else {
                    const full = max(max_three(q[0], q[1], q[2]), max_level);
                    out = [full, full, full];
                }
                var above: f32 = 0.0;
                var lowest: f32 = bits_value(largest_finite_bits);
                c = 0;
                while c < 3 {
                    if cl[c] {
                        above = max(above, math.log2_f32(max(out[c] / max(q[c], bits_value(ratio_floor_bits)), 1.0) as f32) as f32);
                    } else {
                        lowest = min(lowest, p[c]);
                    }
                    c = c + 1;
                }
                const below = max(math.log2_f32((bits_value(clip_threshold_bits) / max(lowest, bits_value(luminance_floor_bits))) as f32) as f32, 0.0);
                var way: f32 = 0.0;
                if above > (0.0 as f32) and lowest < bits_value(clip_threshold_bits) {
                    way = above / (above + below);
                }
                const lo = min(min(out[0], out[1]), out[2]);
                const hi = max_three(out[0], out[1], out[2]);
                var saturation: f32 = 1.0;
                if hi > (0.0 as f32) and hi < bits_value(largest_finite_bits) {
                    saturation = (1.0 as f32) - max(lo, 0.0) / hi;
                }
                const start = (0.5 as f32) * smooth(bits_value(saturation_transition_start_bits), bits_value(saturation_transition_end_bits), saturation);
                const t_level = smooth(0.5, 1.0, way);
                const t_color = smooth(start, start + (0.5 as f32), way);
                if t_color > (0.0 as f32) {
                    const level = (out[0] + out[1] + out[2]) / (3.0 as f32);
                    const full = max(max_three(q[0], q[1], q[2]), max_level);
                    const v = level + (full - level) * t_level;
                    c = 0;
                    while c < 3 {
                        out[c] = out[c] + (v - out[c]) * t_color;
                        c = c + 1;
                    }
                }
                c = 0;
                while c < 3 {
                    write_f32(rgb, i * 3 + c, out[c] / wb[c]);
                    c = c + 1;
                }
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

// Check a pyramid's metadata against its exact contiguous layout.
fn levels_valid(meta: *const usize, levels: usize, len: usize, buffer_len: usize, width: usize, height: usize, channels: usize): bool {
    if levels == 0 or levels > 32 or len != levels * 3 {
        return false;
    }
    var w = width;
    var h = height;
    var offset: usize = 0;
    var i: usize = 0;
    while i < levels {
        if read_usize(meta, i * 3) != offset or read_usize(meta, i * 3 + 1) != w or read_usize(meta, i * 3 + 2) != h {
            return false;
        }
        offset = offset + w * h * channels;
        if offset > buffer_len {
            return false;
        }
        if w == 1 and h == 1 {
            return i + 1 == levels and offset == buffer_len;
        }
        w = (w + 1) / 2;
        h = (h + 1) / 2;
        i = i + 1;
    }
    return false;
}

// Validate every size, white-balance gain, and pyramid geometry before
// dereferencing caller buffers. Status 4 means invalid parameters or shape;
// status 0 means the buffers were repaired (or contained no clipped pixels).
pub fn reconstruct(rgb: *f32, width: usize, height: usize, white_balance: *const f32, source: *f32, source_meta: *const usize, source_levels: usize, rim: *f32, rim_meta: *const usize, rim_levels: usize, lum: *f32, touched: *u8, near: *u8, rgb_len: usize, white_balance_len: usize, source_len: usize, source_meta_len: usize, rim_len: usize, rim_meta_len: usize, lum_len: usize, touched_len: usize, near_len: usize): i32 {
    const w = width as usize;
    const h = height as usize;
    if w < 2 or h < 2 or w > 33554432 / h {
        return 4;
    }
    const cw = (w + 1) / 2;
    const ch = (h + 1) / 2;
    if rgb_len as usize != w * h * 3 or white_balance_len as usize != 3 or lum_len as usize != cw * ch or touched_len as usize != cw * ch or near_len as usize != cw * ch {
        return 4;
    }
    if not levels_valid(source_meta, source_levels as usize, source_meta_len as usize, source_len as usize, cw, ch, 3) or not levels_valid(rim_meta, rim_levels as usize, rim_meta_len as usize, rim_len as usize, (w + 3) / 4, (h + 3) / 4, 4) {
        return 4;
    }
    const wb: [3]f32 = [read_f32(white_balance, 0), read_f32(white_balance, 1), read_f32(white_balance, 2)];
    if wb[0] <= (0.0 as f32) or wb[0] > bits_value(maximum_white_balance_gain_bits) or wb[1] <= (0.0 as f32) or wb[1] > bits_value(maximum_white_balance_gain_bits) or wb[2] <= (0.0 as f32) or wb[2] > bits_value(maximum_white_balance_gain_bits) {
        return 4;
    }
    var count: usize = 0;
    var i: usize = 0;
    while i < w * h {
        if any_channel_clipped(rgb, i) {
            count = count + 1;
        }
        i = i + 1;
    }
    if count == 0 {
        return 0;
    }
    estimate_source_texels(rgb, w, h, wb, source, source_meta, lum, touched, near);
    i = 1;
    while i < source_levels as usize {
        build_mip_level(source, source_meta, i, 3);
        i = i + 1;
    }
    const neutral: [3]f32 = [(1.0 as f32) / (3.0 as f32), (1.0 as f32) / (3.0 as f32), (1.0 as f32) / (3.0 as f32)];
    spread_priors(source, source_meta, source_levels as usize, 3, near, true, neutral);
    measure_support_trust(source, source_meta, source_levels as usize, near, w, h);
    estimate_rim_texels(rgb, w, h, wb, rim, rim_meta, near);
    i = 1;
    while i < rim_levels as usize {
        build_mip_level(rim, rim_meta, i, 4);
        i = i + 1;
    }
    const top = rim_levels as usize - 1;
    const rw = read_usize(rim_meta, top * 3 + 1);
    const rh = read_usize(rim_meta, top * 3 + 2);
    var has_rim = false;
    i = 0;
    while i < rw * rh {
        if read_f32(rim, read_usize(rim_meta, top * 3) + i * 4 + 3) > (0.0 as f32) {
            has_rim = true;
        }
        i = i + 1;
    }
    if has_rim {
        spread_priors(rim, rim_meta, rim_levels as usize, 4, near, false, neutral);
    }
    repair_clipped_pixels(rgb, w, h, wb, source, source_meta, rim, rim_meta, has_rim);
    return 0;
}
