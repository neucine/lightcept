import .engine.core.camera_contract;
import { CameraStageStatus, Demosaic, Highlight, OutputDepth } from .engine.core.camera_contract;
import .engine.color.color_matrix;
import .engine.develop.control_bounds;
import .engine.develop.exposure;
import .engine.develop.black_point;
import .engine.develop.whites;
import .engine.render.working_pixel;
import .engine.render.render;

fn read_float(input: *const f32, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 4) as! *const f32) as f64;
    }
}
fn read_double(input: *const f64, index: usize): f64 {
    unchecked {
        return *(((input as! usize) + index * 8) as! *const f64) as f64;
    }
}

fn write_double(output: *f64, index: usize, value: f64): void {
    unchecked {
        *(((output as! usize) + index * 8) as! *f64) = value;
    }
}

// Version 13 consumes a fully demosaiced and spatially reconstructed camera-RGB
// raster. Reconstruction runs before this stage; color conversion,
// orientation, scene-linear area resampling and encoding remain in Cyna.
fn render_camera_rgb(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64, orientation: u32, output_bits: u32, cancelled: fn (usize): bool, context: usize): i32 {
    const sw = source_width as usize;
    const sh = source_height as usize;
    const w = width as usize;
    const h = height as usize;
    if sw < 2 or sh < 2 or sw > camera_contract.max_camera_pixels / sh or input_len as usize != sw * sh * 3 or matrix_len as usize != 9 or orientation < 1 or orientation > 8 or w == 0 or h == 0 or w > camera_contract.max_camera_pixels / h {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var visual_width = sw;
    var visual_height = sh;
    if orientation >= 5 {
        visual_width = sh;
        visual_height = sw;
    }
    if w > visual_width or h > visual_height {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var channels: usize = 4;
    if output_bits == OutputDepth.rgb16 as u32 {
        channels = 3;
    }
    if (output_bits != OutputDepth.rgba8 as u32 and output_bits != OutputDepth.rgb16 as u32) or output_len as usize != w * h * channels {
        return CameraStageStatus.shape_mismatch as i32;
    }
    const exposure_ev = exposure.compose(default_exposure_ev, user_exposure_ev);
    if not control_bounds.valid_parameters(default_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_parameters(user_exposure_ev, 1.0, 1.0, 1.0) or not control_bounds.valid_contrast_plan_parameters(exposure_ev, 1.0, 1.0, 1.0, 1.0, contrast_slope) {
        return CameraStageStatus.invalid_parameters as i32;
    }
    const develop_plan = working_pixel.working_srgb_plan(exposure_ev, 1.0, 1.0, 1.0);
    var matrix: [9]f64 = [0.0] ** 9;
    var k: usize = 0;
    while k < 9 {
        const value = read_double(matrix_input, k);
        if value != value or value < -32.0 or value > 32.0 {
            return CameraStageStatus.unsupported as i32;
        }
        matrix[k] = value;
        k = k + 1;
    }
    var pixel: usize = 0;
    while pixel < w * h {
        const output_row = pixel / w;
        if pixel % w == 0 and cancelled(context) {
            return CameraStageStatus.cancelled as i32;
        }
        const output_column = pixel % w;
        const top = output_row * visual_height / h;
        const bottom = (output_row + 1) * visual_height / h;
        const left = output_column * visual_width / w;
        const right = (output_column + 1) * visual_width / w;
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
                const sensor = camera_contract.sensor_position(row, column, sw, sh, orientation as u32);
                const sensor_row = sensor.row;
                const sensor_column = sensor.column;
                const base = (sensor_row * sw + sensor_column) * 3;
                const camera_red = read_float(input, base);
                const camera_green = read_float(input, base + 1);
                const camera_blue = read_float(input, base + 2);
                if camera_red != camera_red or camera_green != camera_green or camera_blue != camera_blue or camera_red < -camera_contract.maximum_channel_magnitude() or camera_red > camera_contract.maximum_channel_magnitude() or camera_green < -camera_contract.maximum_channel_magnitude() or camera_green > camera_contract.maximum_channel_magnitude() or camera_blue < -camera_contract.maximum_channel_magnitude() or camera_blue > camera_contract.maximum_channel_magnitude() {
                    return CameraStageStatus.malformed as i32;
                }
                const working = color_matrix.camera_to_working(matrix, camera_red, camera_green, camera_blue);
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
        const encoded = working_pixel.encode_working_pixel_with_contrast((red / count) as f64, (green / count) as f64, (blue / count) as f64, develop_plan, contrast_slope);
        if output_bits == OutputDepth.rgb16 as u32 {
            const out = pixel * 3;
            render.write_word(output, out, render.quantize16(encoded.red));
            render.write_word(output, out + 1, render.quantize16(encoded.green));
            render.write_word(output, out + 2, render.quantize16(encoded.blue));
        } else {
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

pub fn render_preview(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    return render_camera_rgb(input, input_len, source_width, source_height, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, 1.0, orientation, 8, cancelled, context);
}

// Contrast slope follows the Cyna develop contract and operates on resampled
// scene-linear Rec.2020/D65 RGB after exposure, before sRGB encoding.
pub fn render_rgba8_with_contrast(camera: []const f32, source_width: usize,
    source_height: usize, matrix: [9]f64, output: []u8,
    width: usize, height: usize, default_exposure_ev: f64,
    user_exposure_ev: f64, contrast_slope: f64, orientation: u32,
    cancelled: fn (usize): bool, context: usize
): i32 {
    return render_preview_with_contrast(camera.ptr as! *const f32,
        camera.len() as usize, source_width as usize, source_height as usize,
        matrix[0..].ptr as! *const f64, 9,
        output.ptr as! *u8, output.len() as usize,
        width as usize, height as usize,
        default_exposure_ev as f64, user_exposure_ev as f64,
        contrast_slope as f64, orientation as u32, cancelled, context
    );
}

pub fn render_preview_with_contrast(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *u8, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, contrast_slope: f64, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    return render_camera_rgb(input, input_len, source_width, source_height, matrix_input, matrix_len, output, output_len, width, height, default_exposure_ev, user_exposure_ev, contrast_slope, orientation, 8, cancelled, context);
}

fn render_rgb16(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *u16, output_len: usize, width: usize, height: usize, default_exposure_ev: f64, user_exposure_ev: f64, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    return render_camera_rgb(input, input_len, source_width, source_height, matrix_input, matrix_len, output as! *u8, output_len, width, height, default_exposure_ev, user_exposure_ev, 1.0, orientation, 16, cancelled, context);
}

// A preview-sized scene-linear Rec.2020/D65 f64 boundary. This repeats
// the fused v13 camera-to-working and area-average mathematics without its
// exposure or output encoding. The fused contract remains available.

// Source visual-pixel rectangle in upright coordinates. Equal rectangle/output
// extents reconstruct one source pixel per output pixel. The caller owns a
// bounded f64 scene-linear Rec.2020/D65 output and the full camera RGB source.
pub fn camera_rgb_to_working_region(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *f64, output_len: usize, width: usize, height: usize, orientation: u32, view_left: usize, view_top: usize, view_width: usize, view_height: usize, cancelled: fn (usize): bool, context: usize): i32 {
    const sw = source_width as usize;
    const sh = source_height as usize;
    const w = width as usize;
    const h = height as usize;
    if sw < 2 or sh < 2 or sw > camera_contract.max_camera_source_pixels / sh or input_len as usize != sw * sh * 3 or matrix_len as usize != 9 or orientation < 1 or orientation > 8 or w == 0 or h == 0 or w > camera_contract.max_camera_pixels / h or output_len as usize != w * h * 3 {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var visual_width = sw;
    var visual_height = sh;
    if orientation >= 5 {
        visual_width = sh;
        visual_height = sw;
    }
    if view_left >= visual_width or view_top >= visual_height or view_width == 0 or view_height == 0 or view_width > visual_width - view_left or view_height > visual_height - view_top or w > view_width or h > view_height {
        return CameraStageStatus.shape_mismatch as i32;
    }
    var matrix: [9]f64 = [0.0] ** 9;
    var k: usize = 0;
    while k < 9 {
        const value = read_double(matrix_input, k);
        if value != value or value < -32.0 or value > 32.0 {
            return CameraStageStatus.unsupported as i32;
        }
        matrix[k] = value;
        k = k + 1;
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
                const sensor = camera_contract.sensor_position(row, column, sw, sh, orientation as u32);
                const base = (sensor.row * sw + sensor.column) * 3;
                const camera_red = read_float(input, base);
                const camera_green = read_float(input, base + 1);
                const camera_blue = read_float(input, base + 2);
                if camera_red != camera_red or camera_green != camera_green or camera_blue != camera_blue or camera_red < -camera_contract.maximum_channel_magnitude() or camera_red > camera_contract.maximum_channel_magnitude() or camera_green < -camera_contract.maximum_channel_magnitude() or camera_green > camera_contract.maximum_channel_magnitude() or camera_blue < -camera_contract.maximum_channel_magnitude() or camera_blue > camera_contract.maximum_channel_magnitude() {
                    return CameraStageStatus.malformed as i32;
                }
                const working = color_matrix.camera_to_working(matrix, camera_red, camera_green, camera_blue);
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
        const out = pixel * 3;
        write_double(output, out, red / count);
        write_double(output, out + 1, green / count);
        write_double(output, out + 2, blue / count);
        pixel = pixel + 1;
    }
    return CameraStageStatus.ok as i32;
}

// Fitted whole-image preview retains its existing area-average behavior.
pub fn camera_rgb_to_working_preview(input: *const f32, input_len: usize, source_width: usize, source_height: usize, matrix_input: *const f64, matrix_len: usize, output: *f64, output_len: usize, width: usize, height: usize, orientation: u32, cancelled: fn (usize): bool, context: usize): i32 {
    var visual_width = source_width;
    var visual_height = source_height;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height;
        visual_height = source_width;
    }
    return camera_rgb_to_working_region(input, input_len, source_width,
        source_height, matrix_input, matrix_len, output, output_len,
        width, height, orientation, 0, 0, visual_width, visual_height,
        cancelled, context
    );
}
