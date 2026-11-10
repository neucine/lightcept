import .engine.core.camera_rgb;
import { never_poll } from .engine.core.cancellation;
import .engine.core.camera_contract;
import { CameraStageStatus, Demosaic, Highlight, OutputDepth } from .engine.core.camera_contract;
import .engine.raw.bayer;
import .engine.color.color_matrix;
import .engine.raw.highlight_recovery;
import .engine.develop.control_bounds;
import .engine.develop.exposure;
import .engine.render.working_pixel;
import .engine.render.render;

fn read_word(input: *const u32, index: usize): u32 {
    unchecked {
        return *(((input as! usize) + index * 4) as! *const u32) as u32;
    }
}

fn read_double(input: *const f64, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *const f64) as f64;
    }
}

fn write_double(output: *u8, index: usize, value: f64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *f64) = value;
    }
}

fn write_float(output: *f32, index: usize, value: f32): void {
    unchecked {
        *(((output as! usize) + index * 4) as! *f32) = value as f32;
    }
}

// Preview v1: area-average scene-linear working samples before sRGB encoding.
// Input is a cropped, black-subtracted Bayer mosaic and its crop-relative CFA.
// The matrix maps camera RGB to XYZ D50. Output is opaque encoded sRGB RGBA8.
fn render_normalized_bayer(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, output_bits: u32, orientation: u32, view_left: usize, view_top: usize, view_width: usize, view_height: usize, cancelled: fn (usize): bool, context: usize, highlight_version: u32, neutral_input: *const f64, neutral_len: usize): i32 {
    const sw = source_width as usize;
    const sh = source_height as usize;
    const w = width as usize;
    const h = height as usize;
    if sw < 2 or sh < 2 or sw > camera_contract.max_camera_source_pixels / sh or input_len as usize != sw * sh or cfa_len as usize != 4 or matrix_len as usize != 9 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    if orientation < 1 or orientation > 8 {
        return CameraStageStatus.unsupported as i32;
    }
    var visual_width = sw;
    var visual_height = sh;
    if orientation >= 5 {
        visual_width = sh;
        visual_height = sw;
    }
    var channels: usize = 4;
    if output_bits == OutputDepth.rgb16 as u32 or output_bits == OutputDepth.working_f64 as u32 {
        channels = 3;
    }
    if view_left >= visual_width or view_top >= visual_height or view_width == 0 or view_height == 0 or view_width > visual_width - view_left or view_height > visual_height - view_top or w == 0 or h == 0 or w > view_width or h > view_height or w > camera_contract.max_camera_pixels / h or (output_bits != OutputDepth.rgba8 as u32 and output_bits != OutputDepth.rgb16 as u32 and output_bits != OutputDepth.working_f64 as u32) or output_len as usize != w * h * channels or (demosaic_version != Demosaic.bilinear as u32 and demosaic_version != Demosaic.malvar_he_cutler as u32 and demosaic_version != Demosaic.hamilton_adams as u32) or highlight_version > Highlight.two_channel_neutral as u32 or (highlight_version != Highlight.disabled as u32 and neutral_len as usize != 3) {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_parameters(exposure_ev, 1.0, 1.0, 1.0) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const cfa: [4]u32 = [read_word(cfa_input, 0), read_word(cfa_input, 1), read_word(cfa_input, 2), read_word(cfa_input, 3)];
    if not bayer.valid_pattern(cfa) {
        return CameraStageStatus.unsupported as i32;
    }
    var matrix: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        const value = read_double(matrix_input, index);
        if value != value or value < -32.0 or value > 32.0 {
            return CameraStageStatus.unsupported as i32;
        }
        matrix[index] = value;
        index = index + 1;
    }
    var neutral: [3]f64 = [1.0, 1.0, 1.0];
    if highlight_version != Highlight.disabled as u32 {
        index = 0;
        while index < 3 {
            neutral[index] = read_double(neutral_input, index);
            index = index + 1;
        }
        if not highlight_recovery.valid_neutral(neutral) {
            return CameraStageStatus.invalid_parameters as i32;
        }
    }
    var pixel: usize = 0;
    while pixel < w * h {
        const output_row = pixel / w;
        if pixel % w == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const output_column = pixel % w;
        const top = view_top + output_row * view_height / h;
        const bottom = view_top + (output_row + 1) * view_height / h;
        const left = view_left + output_column * view_width / w;
        const right = view_left + (output_column + 1) * view_width / w;
        var red: f64 = 0.0;
        var green: f64 = 0.0;
        var blue: f64 = 0.0;
        var row = top;
        while row < bottom {
            if row > top and (row - top) % 64 == 0 and cancelled(context) {
                return CameraStageStatus.cancelled as i32;
            }
            var column = left;
            while column < right {
                const sensor = camera_contract.sensor_position(row, column, sw, sh, orientation);
                const sensor_row = sensor.row;
                const sensor_column = sensor.column;
                var camera: camera_rgb.CameraRgb = {
                    red: 0.0,
                    green: 0.0,
                    blue: 0.0
                };
                if demosaic_version == Demosaic.malvar_he_cutler as u32 {
                    camera = bayer.normalized_mhc_pixel(input, sw, sh, cfa, sensor_row, sensor_column);
                } else if demosaic_version == Demosaic.hamilton_adams as u32 {
                    camera = bayer.normalized_ha_pixel(input, sw, sh, cfa, sensor_row, sensor_column);
                } else {
                    camera = bayer.normalized_pixel(input, sw, sh, cfa, sensor_row, sensor_column);
                }
                if camera.red != camera.red or camera.green != camera.green or camera.blue != camera.blue or camera.red < -camera_contract.maximum_channel_magnitude() or camera.red > camera_contract.maximum_channel_magnitude() or camera.green < -camera_contract.maximum_channel_magnitude() or camera.green > camera_contract.maximum_channel_magnitude() or camera.blue < -camera_contract.maximum_channel_magnitude() or camera.blue > camera_contract.maximum_channel_magnitude() {
                    return CameraStageStatus.malformed as i32;
                }
                if highlight_version == Highlight.neutral_ratio as u32 {
                    camera = highlight_recovery.reconstruct(camera, neutral);
                } else if highlight_version == Highlight.saturated_neutral as u32 {
                    camera = highlight_recovery.reconstruct_with_saturated_neutral(camera, neutral);
                } else if highlight_version == Highlight.two_channel_neutral as u32 {
                    camera = highlight_recovery.reconstruct_with_two_channel_neutral(camera, neutral);
                }
                const working = color_matrix.camera_to_working(matrix, camera.red, camera.green, camera.blue);
                if working.red != working.red or working.green != working.green or working.blue != working.blue {
                    return CameraStageStatus.malformed as i32;
                }
                red = red + working.red as f64;
                green = green + working.green as f64;
                blue = blue + working.blue as f64;
                column = column + 1;
            }
            row = row + 1;
        }
        const count = ((bottom - top) * (right - left)) as f64;
        if output_bits == OutputDepth.working_f64 as u32 {
            const out = pixel * 3;
            write_double(output, out, red / count);
            write_double(output, out + 1, green / count);
            write_double(output, out + 2, blue / count);
        } else if output_bits == OutputDepth.rgb16 as u32 {
            const encoded = working_pixel.encode_working_pixel((red / count) as f64, (green / count) as f64, (blue / count) as f64, exposure_ev, 1.0, 1.0, 1.0);
            const out = pixel * 3;
            render.write_word(output, out, render.quantize16(encoded.red));
            render.write_word(output, out + 1, render.quantize16(encoded.green));
            render.write_word(output, out + 2, render.quantize16(encoded.blue));
        } else {
            const encoded = working_pixel.encode_working_pixel((red / count) as f64, (green / count) as f64, (blue / count) as f64, exposure_ev, 1.0, 1.0, 1.0);
            const out = pixel * 4;
            render.write_byte(output, out, render.quantize(encoded.red));
            render.write_byte(output, out + 1, render.quantize(encoded.green));
            render.write_byte(output, out + 2, render.quantize(encoded.blue));
            render.write_byte(output, out + 3, 255);
        }
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// Fitted, oriented scene-linear Rec.2020/D65 RGB. Output has exactly
// width * height * 3 f64 samples. The caller owns the output and its lifetime.
// highlight_version 0 disables reconstruction and preserves the pinned output
// of earlier callers; version 3 uses the two-channel neutral rule.
pub fn prepare_oriented_working_preview_highlight(normalized: []const f32, source_width: usize, source_height: usize, cfa: [4]u32, matrix: [9]f64, neutral: [3]f64, output: []f64, width: usize, height: usize, orientation: u32, highlight_version: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width;
    var visual_height = source_height;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height;
        visual_height = source_width;
    }
    return render_normalized_bayer(normalized.ptr as! *const f32, normalized.len(), source_width, source_height, cfa[0..].ptr as! *const u32, 4, matrix[0..].ptr as! *const f64, 9, output.ptr as! *u8, output.len(), width, height, 0.0, 0.0, Demosaic.malvar_he_cutler as u32, OutputDepth.working_f64 as u32, orientation, 0, 0, visual_width, visual_height, cancelled, context, highlight_version, neutral[0..].ptr as! *const f64, 3);
}

pub fn prepare_oriented_working_preview(normalized: []const f32, source_width: usize, source_height: usize, cfa: [4]u32, matrix: [9]f64, output: []f64, width: usize, height: usize, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    const neutral: [3]f64 = [1.0, 1.0, 1.0];
    return prepare_oriented_working_preview_highlight(normalized, source_width,
        source_height, cfa, matrix, neutral, output, width, height, orientation,
        0, cancelled, context
    );
}

// Source visual-pixel rectangle -> scene-linear Rec.2020/D65 working RGB.
// At equal input/output extents each output pixel represents exactly one
// oriented source pixel. The caller bounds the decoded mosaic separately.
// Output has width * height * 3 samples and is invalid on nonzero status.
pub fn prepare_oriented_working_region_highlight(normalized: []const f32,
    source_width: usize, source_height: usize, cfa: [4]u32,
    matrix: [9]f64, neutral: [3]f64, orientation: u32, left: usize, top: usize,
    region_width: usize, region_height: usize, output: []f64,
    width: usize, height: usize, highlight_version: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_normalized_bayer(normalized.ptr as! *const f32,
        normalized.len(), source_width, source_height,
        cfa[0..].ptr as! *const u32, 4,
        matrix[0..].ptr as! *const f64, 9,
        output.ptr as! *u8, output.len(), width, height, 0.0, 0.0,
        Demosaic.malvar_he_cutler as u32, OutputDepth.working_f64 as u32,
        orientation, left, top, region_width, region_height,
        cancelled, context, highlight_version, neutral[0..].ptr as! *const f64, 3
    );
}

pub fn prepare_oriented_working_region(normalized: []const f32,
    source_width: usize, source_height: usize, cfa: [4]u32,
    matrix: [9]f64, orientation: u32, left: usize, top: usize,
    region_width: usize, region_height: usize, output: []f64,
    width: usize, height: usize, cancelled: fn (usize): bool,
    context: usize
): i32 {
    const neutral: [3]f64 = [1.0, 1.0, 1.0];
    return prepare_oriented_working_region_highlight(normalized,
        source_width, source_height, cfa, matrix, neutral, orientation, left,
        top, region_width, region_height, output, width, height, 0,
        cancelled, context
    );
}

// Version 2 keeps the original bilinear output stable for existing callers.
fn render_normalized_bayer_preview(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64): i32 {
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, 1, 8, 1, 0, 0, source_width as usize, source_height as usize, never_poll, 0, 0, 0 as! *const f64, 0);
}

// Version 3 chooses the explicit demosaic version: 1 bilinear, 2 MHC 5x5,
// 3 Hamilton-Adams directional reconstruction.
fn render_normalized_bayer_preview_v3(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32): i32 {
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, 1, 0, 0, source_width as usize, source_height as usize, never_poll, 0, 0, 0 as! *const f64, 0);
}

// Version 4 keeps the same color and exposure path for 16-bit encoded sRGB.
// The output length is a count of RGB16 samples, not bytes.
fn render_normalized_bayer_rgb16(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32): i32 {
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, 1, 0, 0, source_width as usize, source_height as usize, never_poll, 0, 0, 0 as! *const f64, 0);
}

// Versions 5 and 6 map visual coordinates back to the sensor raster before
// demosaic. Fitted previews average the visual image, including mirrored or
// rotated orientations, in scene-linear working space.
fn render_oriented_bayer_preview(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, 0, 0, visual_width, visual_height, never_poll, 0, 0, 0 as! *const f64, 0);
}

fn render_oriented_bayer_rgb16(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, orientation as u32, 0, 0, visual_width, visual_height, never_poll, 0, 0, 0 as! *const f64, 0);
}

// Version 7 renders a 1:1 viewport in visual coordinates without changing the
// shared camera-to-working, exposure, or output-color sequence.
fn render_oriented_bayer_viewport(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, view_left: usize, view_top: usize, view_width: usize, view_height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32): i32 {
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, view_width, view_height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, view_left as usize, view_top as usize, view_width as usize, view_height as usize, never_poll, 0, 0, 0 as! *const f64, 0);
}

// Diagnostic 1:1 camera-to-working boundary. Coordinates are in the oriented
// visual image; output is interleaved signed scene-linear Rec.2020/D65 f32.
// Each pixel is demosaiced from the full normalized mosaic, preserving
// neighbors across viewport edges without a full-frame RGB allocation.
fn bayer_to_working_viewport(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *f32, output_len: usize, view_left: usize, view_top: usize, view_width: usize, view_height: usize, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    const sw = source_width as usize;
    const sh = source_height as usize;
    const left = view_left as usize;
    const top = view_top as usize;
    const w = view_width as usize;
    const h = view_height as usize;
    if sw < 2 or sh < 2 or sw > camera_contract.max_camera_source_pixels / sh or input_len as usize != sw * sh or cfa_len as usize != 4 or matrix_len as usize != 9 or orientation < 1 or orientation > 8 or (demosaic_version as u32 != Demosaic.bilinear as u32 and demosaic_version as u32 != Demosaic.malvar_he_cutler as u32 and demosaic_version as u32 != Demosaic.hamilton_adams as u32) {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var visual_width = sw;
    var visual_height = sh;
    if orientation >= 5 {
        visual_width = sh;
        visual_height = sw;
    }
    if w == 0 or h == 0 or w > 4194304 / h or left >= visual_width or top >= visual_height or w > visual_width - left or h > visual_height - top or output_len as usize != w * h * 3 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const cfa: [4]u32 = [read_word(cfa_input, 0), read_word(cfa_input, 1), read_word(cfa_input, 2), read_word(cfa_input, 3)];
    if not bayer.valid_pattern(cfa) {
        return CameraStageStatus.unsupported as i32;
    }
    var matrix: [9]f64 = [0.0] ** 9;
    var index: usize = 0;
    while index < 9 {
        const value = read_double(matrix_input, index);
        if value != value or value < -32.0 or value > 32.0 {
            return CameraStageStatus.unsupported as i32;
        }
        matrix[index] = value;
        index = index + 1;
    }
    var pixel: usize = 0;
    while pixel < w * h {
        if pixel % w == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const sensor = camera_contract.sensor_position(top + pixel / w, left + pixel % w, sw, sh, orientation as u32);
        var camera: camera_rgb.CameraRgb = {
            red: 0.0,
            green: 0.0,
            blue: 0.0
        };
        if demosaic_version as u32 == Demosaic.malvar_he_cutler as u32 {
            camera = bayer.normalized_mhc_pixel(input, sw, sh, cfa, sensor.row, sensor.column);
        } else if demosaic_version as u32 == Demosaic.hamilton_adams as u32 {
            camera = bayer.normalized_ha_pixel(input, sw, sh, cfa, sensor.row, sensor.column);
        } else {
            camera = bayer.normalized_pixel(input, sw, sh, cfa, sensor.row, sensor.column);
        }
        if camera.red != camera.red or camera.green != camera.green or camera.blue != camera.blue or camera.red < -camera_contract.maximum_channel_magnitude() or camera.red > camera_contract.maximum_channel_magnitude() or camera.green < -camera_contract.maximum_channel_magnitude() or camera.green > camera_contract.maximum_channel_magnitude() or camera.blue < -camera_contract.maximum_channel_magnitude() or camera.blue > camera_contract.maximum_channel_magnitude() {
            return CameraStageStatus.malformed as i32;
        }
        const working = color_matrix.camera_to_working(matrix, camera.red, camera.green, camera.blue);
        if working.red != working.red or working.green != working.green or working.blue != working.blue {
            return CameraStageStatus.malformed as i32;
        }
        const out = pixel * 3;
        write_float(output, out, working.red as f32);
        write_float(output, out + 1, working.green as f32);
        write_float(output, out + 2, working.blue as f32);
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// Typed Cyna entry for an already prepared cropped Bayer mosaic. The callback
// still crosses the native host boundary; the renderer owns all C conversions.
pub fn render_oriented_rgba8(normalized: []const f32, source_width: usize,
    source_height: usize, cfa: [4]u32, matrix: [9]f64, output: []u8,
    width: usize, height: usize, default_exposure_ev: f64,
    user_exposure_ev: f64, demosaic_version: u32, orientation: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_oriented_bayer_preview_v8(normalized.ptr as! *const f32,
        normalized.len() as usize, source_width as usize, source_height as usize,
        cfa[0..].ptr as! *const u32, 4,
        matrix[0..].ptr as! *const f64, 9,
        output.ptr as! *u8, output.len() as usize,
        width as usize, height as usize,
        default_exposure_ev as f64, user_exposure_ev as f64,
        demosaic_version as u32, orientation as u32, cancelled, context
    );
}

pub fn render_oriented_rgb16(normalized: []const f32, source_width: usize,
    source_height: usize, cfa: [4]u32, matrix: [9]f64, output: []u16,
    width: usize, height: usize, default_exposure_ev: f64,
    user_exposure_ev: f64, demosaic_version: u32, orientation: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_oriented_bayer_rgb16_v8(normalized.ptr as! *const f32,
        normalized.len() as usize, source_width as usize, source_height as usize,
        cfa[0..].ptr as! *const u32, 4,
        matrix[0..].ptr as! *const f64, 9,
        output.ptr as! *u16, output.len() as usize,
        width as usize, height as usize,
        default_exposure_ev as f64, user_exposure_ev as f64,
        demosaic_version as u32, orientation as u32, cancelled, context
    );
}

// Fitted MHC sRGB output with two-channel neutral highlight reconstruction.
// The neutral is in pre-matrix camera-channel units.
pub fn render_oriented_rgba8_highlight(normalized: []const f32, source_width: usize,
    source_height: usize, cfa: [4]u32, matrix: [9]f64, neutral: [3]f64,
    output: []u8, width: usize, height: usize, default_exposure_ev: f64,
    user_exposure_ev: f64, orientation: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_oriented_bayer_preview_highlight_v12(normalized.ptr as! *const f32,
        normalized.len() as usize, source_width as usize, source_height as usize,
        cfa[0..].ptr as! *const u32, 4,
        matrix[0..].ptr as! *const f64, 9,
        neutral[0..].ptr as! *const f64, 3,
        output.ptr as! *u8, output.len() as usize,
        width as usize, height as usize,
        default_exposure_ev as f64, user_exposure_ev as f64,
        Demosaic.malvar_he_cutler as u32, orientation as u32,
        cancelled, context
    );
}

pub fn render_oriented_rgb16_highlight(normalized: []const f32, source_width: usize,
    source_height: usize, cfa: [4]u32, matrix: [9]f64, neutral: [3]f64,
    output: []u16, width: usize, height: usize, default_exposure_ev: f64,
    user_exposure_ev: f64, orientation: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_oriented_bayer_rgb16_highlight_v12(normalized.ptr as! *const f32,
        normalized.len() as usize, source_width as usize, source_height as usize,
        cfa[0..].ptr as! *const u32, 4,
        matrix[0..].ptr as! *const f64, 9,
        neutral[0..].ptr as! *const f64, 3,
        output.ptr as! *u16, output.len() as usize,
        width as usize, height as usize,
        default_exposure_ev as f64, user_exposure_ev as f64,
        Demosaic.malvar_he_cutler as u32, orientation as u32,
        cancelled, context
    );
}

// Version 8 retains the checked pointer implementation for existing callers.
// Status 7 discards the partial output. The caller keeps its context alive.
pub fn render_oriented_bayer_preview_v8(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 0, 0 as! *const f64, 0);
}

pub fn render_oriented_bayer_rgb16_v8(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 0, 0 as! *const f64, 0);
}

// Version 9 is an opt-in neutral-ratio highlight experiment. The caller supplies
// the as-shot camera neutral; earlier versions and their pinned output stay stable.
fn render_oriented_bayer_preview_highlight_v9(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 1, neutral_input, neutral_len);
}

fn render_oriented_bayer_rgb16_highlight_v9(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 1, neutral_input, neutral_len);
}

// Version 11 adds a fully-clipped neutral fallback to the v9 rule.
// The product renderer and v9 outputs remain unchanged.
fn render_oriented_bayer_preview_highlight_v11(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 2, neutral_input, neutral_len);
}

fn render_oriented_bayer_rgb16_highlight_v11(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 2, neutral_input, neutral_len);
}

// Version 12 adds a two-channel neutral fallback to the earlier rule.
// The product renderer and earlier diagnostic outputs remain unchanged.
fn render_oriented_bayer_preview_highlight_v12(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgba8 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 3, neutral_input, neutral_len);
}

fn render_oriented_bayer_rgb16_highlight_v12(input: *const f32, input_len: usize, source_width: usize, source_height: usize, cfa_input: *const u32, cfa_len: usize, matrix_input: *const f64, matrix_len: usize, neutral_input: *const f64, neutral_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, demosaic_version: u32, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width as usize;
    var visual_height = source_height as usize;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height as usize;
        visual_height = source_width as usize;
    }
    return render_normalized_bayer(input, input_len, source_width, source_height, cfa_input, cfa_len, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, demosaic_version as u32, OutputDepth.rgb16 as u32, orientation as u32, 0, 0, visual_width, visual_height, cancelled, context, 3, neutral_input, neutral_len);
}
