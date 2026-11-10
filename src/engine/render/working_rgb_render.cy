import .engine.core.camera_contract;
import { CameraStageStatus } from .engine.core.camera_contract;
import .engine.develop.control_bounds;
import .engine.develop.exposure;
import .engine.develop.black_point;
import .engine.develop.whites;
import .engine.develop.vibrance;
import .engine.develop.clarity;
import .engine.develop.texture;
import .engine.color.relative_white;
import .engine.render.working_pixel;
import .engine.render.render;
import .engine.render.output_quantize;
import std.math;

fn read_double(input: *const f64, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *const f64) as f64;
    }
}

// The preview-sized working image is immutable across exposure and contrast edits.
pub fn render_working_rgba8(input: *const f64, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64, cancelled: fn (usize): bool, context: usize): i32 {
    return render_working_rgba8_with_tone(input, input_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, contrast_slope, 0.0, 0.0, cancelled, context);
}

// Signed scene-linear Rec.2020/D65 working preview to opaque sRGB RGBA8.
// Shadow and highlight strengths are in [-1, 1], with zero neutral.
pub fn render_working_rgba8_with_tone(input: *const f64, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64, shadow_strength: f64, highlight_strength: f64, cancelled: fn (usize): bool, context: usize): i32 {
    if width == 0 or height == 0 or height > camera_contract.max_camera_pixels / width or input_len != width * height * 3 or output_len != width * height * 4 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) or not (shadow_strength >= -1.0 and shadow_strength <= 1.0) or not (highlight_strength >= -1.0 and highlight_strength <= 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    var pixel: usize = 0;
    while pixel < width * height {
        if pixel % width == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const offset = pixel * 3;
        const encoded = working_pixel.encode_working_pixel_with_tone(read_double(input, offset), read_double(input, offset + 1), read_double(input, offset + 2), plan, contrast_slope, shadow_strength, highlight_strength);
        const out = pixel * 4;
        render.write_byte(output, out, render.quantize(encoded.red));
        render.write_byte(output, out + 1, render.quantize(encoded.green));
        render.write_byte(output, out + 2, render.quantize(encoded.blue));
        render.write_byte(output, out + 3, 255);
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// EndpointToneV2 accepts a black offset in linear reference-white units and
// a white strength in [-0.5, 1]. Input stays immutable; output is invalid on
// failure, including cancellation. Neutral endpoints use the pinned v1 path.
pub fn render_working_rgba8_with_endpoints(input: *const f64, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64, black_offset: f64, shadow_strength: f64, highlight_strength: f64, white_strength: f64, cancelled: fn (usize): bool, context: usize): i32 {
    if black_offset == 0.0 and white_strength == 0.0 {
        return render_working_rgba8_with_tone(input, input_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, contrast_slope, shadow_strength, highlight_strength, cancelled, context);
    }
    if width == 0 or height == 0 or height > camera_contract.max_camera_pixels / width or input_len != width * height * 3 or output_len != width * height * 4 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) or not black_point.valid_offset(black_offset) or not whites.valid_strength(white_strength) or not (shadow_strength >= -1.0 and shadow_strength <= 1.0) or not (highlight_strength >= -1.0 and highlight_strength <= 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    var pixel: usize = 0;
    while pixel < width * height {
        if pixel % width == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const offset = pixel * 3;
        const encoded = working_pixel.encode_working_pixel_with_endpoints(read_double(input, offset), read_double(input, offset + 1), read_double(input, offset + 2), plan, contrast_slope, black_offset, shadow_strength, highlight_strength, white_strength);
        const out = pixel * 4;
        render.write_byte(output, out, render.quantize(encoded.red));
        render.write_byte(output, out + 1, render.quantize(encoded.green));
        render.write_byte(output, out + 2, render.quantize(encoded.blue));
        render.write_byte(output, out + 3, 255);
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// ColorPreviewV1. Working input remains immutable; nonzero status invalidates
// output. The neutral color route preserves the pinned endpoint renderer.
pub fn render_working_rgba8_with_color(input: *const f64, input_len: usize,
    output: *u8, output_len: usize, width: usize, height: usize,
    default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64,
    black_offset: f64, shadow_strength: f64, highlight_strength: f64,
    white_strength: f64, warmth_percent: i32, tint_percent: i32,
    vibrance_percent: i32, saturation_percent: i32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if not relative_white.valid(warmth_percent, tint_percent) or
    vibrance_percent < -100 or vibrance_percent > 100 or
    saturation_percent < -100 or saturation_percent > 100 {
        return CameraStageStatus.invalid_parameters as i32;
    }
    if warmth_percent == 0 and tint_percent == 0 and vibrance_percent == 0 and saturation_percent == 0 {
        return render_working_rgba8_with_endpoints(input, input_len, output, output_len,
            width, height, default_exposure_ev, user_exposure_ev, contrast_slope,
            black_offset, shadow_strength, highlight_strength, white_strength,
            cancelled, context
        );
    }
    if width == 0 or height == 0 or height > camera_contract.max_camera_pixels / width or
    input_len != width * height * 3 or output_len != width * height * 4 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) or
    not black_point.valid_offset(black_offset) or not whites.valid_strength(white_strength) or
    not (shadow_strength >= -1.0 and shadow_strength <= 1.0) or
    not (highlight_strength >= -1.0 and highlight_strength <= 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    var pixel: usize = 0;
    while pixel < width * height {
        if pixel % width == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const offset = pixel * 3;
        const encoded = working_pixel.encode_working_pixel_with_color(
            read_double(input, offset), read_double(input, offset + 1),
            read_double(input, offset + 2), plan, contrast_slope, black_offset,
            shadow_strength, highlight_strength, white_strength,
            warmth_percent, tint_percent, vibrance_percent, saturation_percent
        );
        const out = pixel * 4;
        render.write_byte(output, out, render.quantize(encoded.red));
        render.write_byte(output, out + 1, render.quantize(encoded.green));
        render.write_byte(output, out + 2, render.quantize(encoded.blue));
        render.write_byte(output, out + 3, 255);
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// Full-size, interleaved encoded sRGB RGB16 from immutable scene-linear
// Rec.2020/D65 working RGB. This uses the same per-pixel Color plan as the
// fitted RGBA8 route, with only the final quantizer changed. The caller owns
// output and must discard it on failure. Status matches the RGBA8 renderer.
pub fn render_working_rgb16_with_color(input: *const f64, input_len: usize,
    output: *u16, output_len: usize, width: usize, height: usize,
    default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64,
    black_offset: f64, shadow_strength: f64, highlight_strength: f64,
    white_strength: f64, warmth_percent: i32, tint_percent: i32,
    vibrance_percent: i32, saturation_percent: i32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if width == 0 or height == 0 or height > camera_contract.max_camera_pixels / width or
    input_len != width * height * 3 or output_len != input_len {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not relative_white.valid(warmth_percent, tint_percent) or
    vibrance_percent < -100 or vibrance_percent > 100 or
    saturation_percent < -100 or saturation_percent > 100 or
    not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) or
    not black_point.valid_offset(black_offset) or not whites.valid_strength(white_strength) or
    not (shadow_strength >= -1.0 and shadow_strength <= 1.0) or
    not (highlight_strength >= -1.0 and highlight_strength <= 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    var pixel: usize = 0;
    while pixel < width * height {
        if pixel % width == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const offset = pixel * 3;
        const encoded = working_pixel.encode_working_pixel_with_color(
            read_double(input, offset), read_double(input, offset + 1),
            read_double(input, offset + 2), plan, contrast_slope, black_offset,
            shadow_strength, highlight_strength, white_strength,
            warmth_percent, tint_percent, vibrance_percent, saturation_percent
        );
        unchecked {
            *(((output as! usize) + offset * 2) as! *u16) = output_quantize.channel16(encoded.red);
            *(((output as! usize) + (offset + 1) * 2) as! *u16) = output_quantize.channel16(encoded.green);
            *(((output as! usize) + (offset + 2) * 2) as! *u16) = output_quantize.channel16(encoded.blue);
        }
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// Full-size Detail export v1. A four-row halo covers the Clarity radius of
// three followed by Texture's radius of one. Each tile is at most 136 rows;
// the original working RGB and finished RGB16 buffers remain caller-owned.
// Tile seams must match a whole-frame Detail render at the same dimensions.
pub fn render_working_rgb16_with_detail(input: *const f64, input_len: usize,
    output: *u16, output_len: usize, width: usize, height: usize,
    default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64,
    black_offset: f64, shadow_strength: f64, highlight_strength: f64,
    white_strength: f64, warmth_percent: i32, tint_percent: i32,
    vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32,
    texture_percent: i32, cancelled: fn (usize): bool, context: usize
): i32 {
    if clarity_percent < -100 or clarity_percent > 100 or
    texture_percent < -100 or texture_percent > 100 {
        return CameraStageStatus.invalid_parameters as i32;
    }
    if clarity_percent == 0 and texture_percent == 0 {
        return render_working_rgb16_with_color(input, input_len, output,
            output_len, width, height, default_exposure_ev, user_exposure_ev,
            contrast_slope, black_offset, shadow_strength, highlight_strength,
            white_strength, warmth_percent, tint_percent, vibrance_percent,
            saturation_percent, cancelled, context
        );
    }
    if width == 0 or height == 0 or width > 10000 or height > 10000 or
    height > camera_contract.max_camera_pixels / width or
    input_len != width * height * 3 or output_len != input_len {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not relative_white.valid(warmth_percent, tint_percent) or
    vibrance_percent < -100 or vibrance_percent > 100 or
    saturation_percent < -100 or saturation_percent > 100 or
    not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or
    not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) or
    not black_point.valid_offset(black_offset) or not whites.valid_strength(white_strength) or
    not (shadow_strength >= -1.0 and shadow_strength <= 1.0) or
    not (highlight_strength >= -1.0 and highlight_strength <= 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    const clarity_asset: clarity.ClarityAsset = {
        version: clarity.algorithm_version,
        amount: (clarity_percent as f64) / 100.0,
        edge_scale_y: 0.5,
        noise_threshold_y: 0.002,
        maximum_offset_y: 0.05
    };
    const texture_asset: texture.TextureAsset = {
        version: texture.algorithm_version,
        edge_limit_y: 0.3,
        amount: (texture_percent as f64) / 100.0,
        noise_threshold_y: 0.001,
        maximum_offset_y: 0.02
    };
    var first_row: usize = 0;
    while first_row < height {
        if cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        var last_row = first_row + 128;
        if last_row > height {
            last_row = height;
        }
        var tile_top: usize = 0;
        if first_row > 4 {
            tile_top = first_row - 4;
        }
        var tile_bottom = last_row + 4;
        if tile_bottom > height {
            tile_bottom = height;
        }
        const tile_height = tile_bottom - tile_top;
        const channels = width * tile_height * 3;
        var source: [:]f32 = [: channels]f32;
        var clarity_frame: [:]f32 = [: channels]f32;
        var texture_frame: [:]f32 = [: channels]f32;
        var index: usize = 0;
        while index < channels {
            const rounded = math.to_f32_rounded(read_double(input, tile_top * width * 3 + index));
            if rounded is value {
                source.push(value);
            } else {
                return CameraStageStatus.invalid_parameters as i32;
            }
            clarity_frame.push(0.0);
            texture_frame.push(0.0);
            index = index + 1;
        }
        var adjusted: []const f32 = source[..];
        if clarity_percent != 0 {
            const status = clarity.apply(source[..], width, tile_height,
                clarity_asset, clarity_frame[..], cancelled, context
            );
            if status != 0 {
                return status as i32;
            }
            adjusted = clarity_frame[..];
        }
        if texture_percent != 0 {
            const status = texture.apply(adjusted, width, tile_height,
                texture_asset, texture_frame[..], cancelled, context
            );
            if status != 0 {
                return status as i32;
            }
            adjusted = texture_frame[..];
        }
        var row = first_row;
        while row < last_row {
            if cancelled(context) {
                return CameraStageStatus.cancelled as i32;
            }
            var column: usize = 0;
            while column < width {
                const offset = ((row - tile_top) * width + column) * 3;
                const encoded = working_pixel.encode_working_pixel_with_color(
                    adjusted[offset] as f64, adjusted[offset + 1] as f64,
                    adjusted[offset + 2] as f64, plan, contrast_slope,
                    black_offset, shadow_strength, highlight_strength,
                    white_strength, warmth_percent, tint_percent,
                    vibrance_percent, saturation_percent
                );
                const out = (row * width + column) * 3;
                unchecked {
                    *(((output as! usize) + out * 2) as! *u16) = output_quantize.channel16(encoded.red);
                    *(((output as! usize) + (out + 1) * 2) as! *u16) = output_quantize.channel16(encoded.green);
                    *(((output as! usize) + (out + 2) * 2) as! *u16) = output_quantize.channel16(encoded.blue);
                }
                column = column + 1;
            }
            row = row + 1;
        }
        first_row = last_row;
    }
    return CameraStageStatus.ok as i32;
}

// DetailPreviewV1 applies the versioned mid-frequency clarity kernel to the
// immutable fitted scene-linear working image before the ColorPreviewV1 path.
// Percent is signed [-100,100]; zero calls the pinned color renderer exactly.
// The two f32 scratch frames and one f64 staging frame are caller-private.
pub fn render_working_rgba8_with_clarity(input: *const f64, input_len: usize,
    output: *u8, output_len: usize, width: usize, height: usize,
    default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64,
    black_offset: f64, shadow_strength: f64, highlight_strength: f64,
    white_strength: f64, warmth_percent: i32, tint_percent: i32,
    vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if clarity_percent < -100 or clarity_percent > 100 {
        return CameraStageStatus.invalid_parameters as i32;
    }
    if clarity_percent == 0 {
        return render_working_rgba8_with_color(input, input_len, output, output_len,
            width, height, default_exposure_ev, user_exposure_ev, contrast_slope,
            black_offset, shadow_strength, highlight_strength, white_strength,
            warmth_percent, tint_percent, vibrance_percent, saturation_percent, cancelled, context
        );
    }
    if width == 0 or height == 0 or height > 4194304 / width or
    input_len != width * height * 3 or output_len != width * height * 4 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var source: [:]f32 = [: input_len]f32;
    var adjusted: [:]f32 = [: input_len]f32;
    var staged: [:]f64 = [: input_len]f64;
    var index: usize = 0;
    while index < input_len {
        const rounded = math.to_f32_rounded(read_double(input, index));
        if rounded is value {
            source.push(value);
        } else {
            return CameraStageStatus.invalid_parameters as i32;
        }
        adjusted.push(0.0);
        staged.push(0.0);
        index = index + 1;
    }
    const asset: clarity.ClarityAsset = {
        version: clarity.algorithm_version,
        amount: (clarity_percent as f64) / 100.0,
        edge_scale_y: 0.5,
        noise_threshold_y: 0.002,
        maximum_offset_y: 0.05
    };
    const clarity_status = clarity.apply(source[..], width, height, asset,
        adjusted[..], cancelled, context
    );
    if clarity_status != 0 {
        return clarity_status as i32;
    }
    index = 0;
    while index < input_len {
        staged[index] = adjusted[index] as f64;
        index = index + 1;
    }
    return render_working_rgba8_with_color(staged[..].ptr, input_len, output,
        output_len, width, height, default_exposure_ev, user_exposure_ev,
        contrast_slope, black_offset, shadow_strength, highlight_strength,
        white_strength, warmth_percent, tint_percent, vibrance_percent, saturation_percent,
        cancelled, context
    );
}

// DetailPreviewV2 adds fine texture after mid-frequency Clarity. Zero Texture
// calls the pinned Clarity route exactly; source bytes remain immutable.
pub fn render_working_rgba8_with_detail(input: *const f64, input_len: usize,
    output: *u8, output_len: usize, width: usize, height: usize,
    default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64,
    black_offset: f64, shadow_strength: f64, highlight_strength: f64,
    white_strength: f64, warmth_percent: i32, tint_percent: i32,
    vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32,
    texture_percent: i32, cancelled: fn (usize): bool, context: usize
): i32 {
    if texture_percent < -100 or texture_percent > 100 or
    clarity_percent < -100 or clarity_percent > 100 {
        return CameraStageStatus.invalid_parameters as i32;
    }
    if texture_percent == 0 {
        return render_working_rgba8_with_clarity(input, input_len, output,
            output_len, width, height, default_exposure_ev, user_exposure_ev,
            contrast_slope, black_offset, shadow_strength, highlight_strength,
            white_strength, warmth_percent, tint_percent, vibrance_percent,
            saturation_percent, clarity_percent, cancelled, context
        );
    }
    if width == 0 or height == 0 or height > 4194304 / width or
    input_len != width * height * 3 or output_len != width * height * 4 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var source: [:]f32 = [: input_len]f32;
    var clarity_frame: [:]f32 = [: input_len]f32;
    var texture_frame: [:]f32 = [: input_len]f32;
    var staged: [:]f64 = [: input_len]f64;
    var index: usize = 0;
    while index < input_len {
        const rounded = math.to_f32_rounded(read_double(input, index));
        if rounded is value {
            source.push(value);
        } else {
            return CameraStageStatus.invalid_parameters as i32;
        }
        clarity_frame.push(0.0);
        texture_frame.push(0.0);
        staged.push(0.0);
        index = index + 1;
    }
    if clarity_percent != 0 {
        const clarity_asset: clarity.ClarityAsset = {
            version: clarity.algorithm_version,
            amount: (clarity_percent as f64) / 100.0,
            edge_scale_y: 0.5,
            noise_threshold_y: 0.002,
            maximum_offset_y: 0.05
        };
        const clarity_status = clarity.apply(source[..], width, height,
            clarity_asset, clarity_frame[..], cancelled, context
        );
        if clarity_status != 0 {
            return clarity_status as i32;
        }
    }
    const texture_asset: texture.TextureAsset = {
        version: texture.algorithm_version,
        edge_limit_y: 0.3,
        amount: (texture_percent as f64) / 100.0,
        noise_threshold_y: 0.001,
        maximum_offset_y: 0.02
    };
    var texture_source: []const f32 = source[..];
    if clarity_percent != 0 {
        texture_source = clarity_frame[..];
    }
    const texture_status = texture.apply(
        texture_source, width, height,
        texture_asset, texture_frame[..], cancelled, context
    );
    if texture_status != 0 {
        return texture_status as i32;
    }
    index = 0;
    while index < input_len {
        staged[index] = texture_frame[index] as f64;
        index = index + 1;
    }
    return render_working_rgba8_with_color(staged[..].ptr, input_len, output,
        output_len, width, height, default_exposure_ev, user_exposure_ev,
        contrast_slope, black_offset, shadow_strength, highlight_strength,
        white_strength, warmth_percent, tint_percent, vibrance_percent,
        saturation_percent, cancelled, context
    );
}
