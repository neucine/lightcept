import .engine.core.core;
import .engine.develop.control_bounds;
import .engine.develop.exposure;
import .engine.render.working_pixel;
import .engine.develop.contrast;

import std.math;

fn read_sample(input: *const f32, index: usize): f32 {
    unchecked {
        const address = (input as! usize) + index * 4;
        return *(address as! *const f32);
    }
}

fn write_sample(output: *f32, index: usize, value: f32): void {
    unchecked {
        const address = (output as! usize) + index * 4;
        *(address as! *f32) = value;
    }
}

// Headless scene-linear contrast stage. Input and output have identical geometry
// and Rec.2020/D65 meaning. Status 5 covers nonfinite input or output samples.
fn apply_working_contrast(input: *const f32, input_len: usize, output: *f32, output_len: usize, width: usize, height: usize, max_pixels: usize, slope: f64): i32 {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not contrast.valid_slope(slope) {
        return 4;
    }
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const adjusted = contrast.apply(red as f64, green as f64, blue as f64, slope);
        const r = adjusted.red as f32;
        const g = adjusted.green as f32;
        const b = adjusted.blue as f32;
        if not core.finite_sample(r) or not core.finite_sample(g) or not core.finite_sample(b) {
            return 5;
        }
        write_sample(output, offset, r);
        write_sample(output, offset + 1, g);
        write_sample(output, offset + 2, b);
        pixel = pixel + 1;
    }
    return 0;
}

pub fn write_byte(output: *u8, index: usize, value: u8): void {
    unchecked {
        const address = (output as! usize) + index;
        *(address as! *u8) = value;
    }
}

pub fn write_word(output: *u8, index: usize, value: u16): void {
    unchecked {
        const address = (output as! usize) + index * 2;
        *(address as! *u16) = value;
    }
}

pub fn quantize(value: f64): u8 {
    return math.round_f64(value * (255.0 as f64)) as u8;
}

pub fn quantize16(value: f64): u16 {
    return math.round_f64(value * (65535.0 as f64)) as u16;
}

// Status: 0 success, 1 extent, 2 limit, 3 shape, 4 parameters, 5 samples.
// The caller provides bounded, valid pointer storage to this legacy function.
fn render_preview(input: *const f32, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): i32 {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, red_gain, green_gain, blue_gain);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const in_offset = pixel * 3;
        const out_offset = pixel * 4;
        const red = read_sample(input, in_offset);
        const green = read_sample(input, in_offset + 1);
        const blue = read_sample(input, in_offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_byte(output, out_offset, math.round_f64(encoded.red * (255.0 as f64)) as u8);
        write_byte(output, out_offset + 1, math.round_f64(encoded.green * (255.0 as f64)) as u8);
        write_byte(output, out_offset + 2, math.round_f64(encoded.blue * (255.0 as f64)) as u8);
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

// Companion branch for the same fixed working-pixel plan. Output is encoded
// sRGB RGB16; the TIFF writer only packs these already developed samples.
fn render_working_rgb16(input: *const f32, input_len: usize, output: *u16, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64): i32 {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan(exposure_ev, red_gain, green_gain, blue_gain);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_word(output as! *u8, offset, quantize16(encoded.red));
        write_word(output as! *u8, offset + 1, quantize16(encoded.green));
        write_word(output as! *u8, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Versioned develop-plan entry points preserve their neutral output.
fn render_working_rgba8_chroma(input: *const f32, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): i32 {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const input_offset = pixel * 3;
        const output_offset = pixel * 4;
        const red = read_sample(input, input_offset);
        const green = read_sample(input, input_offset + 1);
        const blue = read_sample(input, input_offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_byte(output, output_offset, quantize(encoded.red));
        write_byte(output, output_offset + 1, quantize(encoded.green));
        write_byte(output, output_offset + 2, quantize(encoded.blue));
        write_byte(output, output_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

fn render_working_rgb16_chroma(input: *const f32, input_len: usize, output: *u16, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): i32 {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_word(output as! *u8, offset, quantize16(encoded.red));
        write_word(output as! *u8, offset + 1, quantize16(encoded.green));
        write_word(output as! *u8, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Diagnostic contrast-plan branches. Their neutral slope delegates to the
// existing v1 pixel operation for exact neutral replay.
fn render_working_rgba8_contrast(input: *const f32, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, slope: f64): i32 {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const out_offset = pixel * 4;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_pixel_with_contrast(red as f64, green as f64, blue as f64, plan, slope);
        write_byte(output, out_offset, quantize(encoded.red));
        write_byte(output, out_offset + 1, quantize(encoded.green));
        write_byte(output, out_offset + 2, quantize(encoded.blue));
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

fn render_working_rgb16_contrast(input: *const f32, input_len: usize, output: *u16, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64, slope: f64): i32 {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_pixel_with_contrast(red as f64, green as f64, blue as f64, plan, slope);
        write_word(output as! *u8, offset, quantize16(encoded.red));
        write_word(output as! *u8, offset + 1, quantize16(encoded.green));
        write_word(output as! *u8, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Explicit SDR output branch. The accepted fused entrypoints remain intact.
fn render_working_rgba8_split(input: *const f32, input_len: usize, output: *u8, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): i32 {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const out_offset = pixel * 4;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_pixel_split(red as f64, green as f64, blue as f64, plan);
        write_byte(output, out_offset, quantize(encoded.red));
        write_byte(output, out_offset + 1, quantize(encoded.green));
        write_byte(output, out_offset + 2, quantize(encoded.blue));
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

fn render_working_rgb16_split(input: *const f32, input_len: usize, output: *u16, output_len: usize, width: usize, height: usize, max_pixels: usize, exposure_ev: f64, red_gain: f64, green_gain: f64, blue_gain: f64, chroma: f64): i32 {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not control_bounds.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = working_pixel.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
    const count = (width as usize) * (height as usize);
    var pixel: usize = 0;
    while pixel < count {
        const offset = pixel * 3;
        const red = read_sample(input, offset);
        const green = read_sample(input, offset + 1);
        const blue = read_sample(input, offset + 2);
        if not core.finite_sample(red) or not core.finite_sample(green) or not core.finite_sample(blue) {
            return 5;
        }
        const encoded = working_pixel.encode_working_pixel_split(red as f64, green as f64, blue as f64, plan);
        write_word(output as! *u8, offset, quantize16(encoded.red));
        write_word(output as! *u8, offset + 1, quantize16(encoded.green));
        write_word(output as! *u8, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}
