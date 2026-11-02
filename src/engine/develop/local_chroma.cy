import .engine.core.core;
import std.math;

// Scene-linear Rec.2020/D65 masked chroma adjustment v1. The mask is an
// existing raster coverage in the same geometry as the image.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct LocalChromaAsset {
    pub version: u32;
    // Unitless global factor at full coverage; 1 is exact identity.
    pub factor: f64;
    // Nonzero identity of the mask geometry and generation recipe.
    pub mask_hash: u64;
}

pub fn valid(asset: LocalChromaAsset): bool {
    return asset.version == algorithm_version and asset.mask_hash != 0
    and asset.factor >= 0.0 and asset.factor <= 2.0;
}

// `coverage` is unitless [0,1]. The effective factor is
// 1 + coverage*(factor-1). Rec.2020 Y is preserved per pixel.
pub fn adjust(red: f64, green: f64, blue: f64,
    coverage: f64, factor: f64
): [3]f64 {
    if coverage == 0.0 or factor == 1.0 {
        return [red, green, blue];
    }
    const y = 0.2627 * red + 0.6780 * green + 0.0593 * blue;
    const effective = 1.0 + coverage * (factor - 1.0);
    return [y + effective * (red - y),
        y + effective * (green - y),
        y + effective * (blue - y)
    ];
}

// Immutable interleaved f32 RGB in [-0.25,8], disjoint output of equal shape,
// one f32 coverage per pixel. Status 0 success, 1 asset, 2 shape/limit,
// 3 invalid input or mask, 4 invalid result, 7 cancelled. Validation completes
// before writing; any failed or cancelled output must be discarded. Poll each
// row in both passes. No image halo, gamut clipping, or mask generation.
pub fn apply(input: []const f32, mask: []const f32, width: usize, height: usize,
    asset: LocalChromaAsset, output: []f32,
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
    if input.len() != pixels * 3 or mask.len() != pixels
    or output.len() != pixels * 3 {
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
                const pixel = row * width + column;
                const offset = pixel * 3;
                const coverage = mask[pixel];
                if not core.finite_sample(coverage) or coverage < 0.0
                or coverage > 1.0 {
                    return 3;
                }
                var channel: usize = 0;
                while channel < 3 {
                    const value = input[offset + channel];
                    if not core.finite_sample(value) or value < -0.25
                    or value > 8.0 {
                        return 3;
                    }
                    channel = channel + 1;
                }
                const result = adjust(input[offset] as f64,
                    input[offset + 1] as f64, input[offset + 2] as f64,
                    coverage as f64, asset.factor
                );
                channel = 0;
                while channel < 3 {
                    if not (result[channel] >= -16.0 and result[channel] <= 16.0) {
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
