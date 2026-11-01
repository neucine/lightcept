import .engine.core.core;
import .engine.pipeline.pipeline;
import .engine.develop.contrast;

extern c("round") fn round(value: c_double): c_double;

fn read_sample(input: *const c_float, index: usize): c_float {
    unchecked {
        const address = (input as! usize) + index * 4;
        return *(address as! *const c_float);
    }
}

fn write_sample(output: *c_float, index: usize, value: c_float): void {
    unchecked {
        const address = (output as! usize) + index * 4;
        *(address as! *c_float) = value;
    }
}

// Headless scene-linear contrast stage. Input and output have identical geometry
// and Rec.2020/D65 meaning. Status 5 covers nonfinite input or output samples.
export c("lc_cyna_img_v1_apply_working_contrast") fn apply_working_contrast(input: *const c_float, input_len: c_size_t, output: *c_float, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, slope: c_double): c_int {
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
        const adjusted = contrast.apply(red as c_double, green as c_double, blue as c_double, slope);
        const r = adjusted.red as c_float;
        const g = adjusted.green as c_float;
        const b = adjusted.blue as c_float;
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

pub fn write_byte(output: *c_uchar, index: usize, value: c_uchar): void {
    unchecked {
        const address = (output as! usize) + index;
        *(address as! *c_uchar) = value;
    }
}

pub fn write_word(output: *c_uchar, index: usize, value: c_ushort): void {
    unchecked {
        const address = (output as! usize) + index * 2;
        *(address as! *c_ushort) = value;
    }
}

pub fn quantize(value: c_double): c_uchar {
    return round(value * (255.0 as c_double)) as c_uchar;
}

pub fn quantize16(value: c_double): c_ushort {
    return round(value * (65535.0 as c_double)) as c_ushort;
}

// Status: 0 success, 1 extent, 2 limit, 3 shape, 4 parameters, 5 samples.
// The Rust caller checks pointer storage before crossing the ABI.
export c("lc_cyna_img_v2_render_preview") fn render_preview(input: *const c_float, input_len: c_size_t, output: *c_uchar, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): c_int {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan(exposure_ev, red_gain, green_gain, blue_gain);
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
        const encoded = pipeline.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_byte(output, out_offset, round(encoded.red * (255.0 as c_double)) as c_uchar);
        write_byte(output, out_offset + 1, round(encoded.green * (255.0 as c_double)) as c_uchar);
        write_byte(output, out_offset + 2, round(encoded.blue * (255.0 as c_double)) as c_uchar);
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

// Companion branch for the same fixed working-pixel plan. Output is encoded
// sRGB RGB16; the TIFF writer only packs these already developed samples.
export c("lc_cyna_img_v3_render_working_rgb16") fn render_working_rgb16(input: *const c_float, input_len: c_size_t, output: *c_ushort, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double): c_int {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_parameters(exposure_ev, red_gain, green_gain, blue_gain) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan(exposure_ev, red_gain, green_gain, blue_gain);
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
        const encoded = pipeline.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_word(output as! *c_uchar, offset, quantize16(encoded.red));
        write_word(output as! *c_uchar, offset + 1, quantize16(encoded.green));
        write_word(output as! *c_uchar, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Versioned develop-plan entrypoints. The prior neutral ABIs remain stable.
export c("lc_cyna_img_v4_render_working_rgba8") fn render_working_rgba8_chroma(input: *const c_float, input_len: c_size_t, output: *c_uchar, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): c_int {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_byte(output, output_offset, quantize(encoded.red));
        write_byte(output, output_offset + 1, quantize(encoded.green));
        write_byte(output, output_offset + 2, quantize(encoded.blue));
        write_byte(output, output_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

export c("lc_cyna_img_v5_render_working_rgb16") fn render_working_rgb16_chroma(input: *const c_float, input_len: c_size_t, output: *c_ushort, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): c_int {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_srgb_plan_pixel(red, green, blue, plan);
        write_word(output as! *c_uchar, offset, quantize16(encoded.red));
        write_word(output as! *c_uchar, offset + 1, quantize16(encoded.green));
        write_word(output as! *c_uchar, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Diagnostic contrast-plan branches. Their neutral slope delegates to the
// existing v1 pixel operation for exact neutral replay.
export c("lc_cyna_img_v6_render_working_rgba8") fn render_working_rgba8_contrast(input: *const c_float, input_len: c_size_t, output: *c_uchar, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, slope: c_double): c_int {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_pixel_with_contrast(red as c_double, green as c_double, blue as c_double, plan, slope);
        write_byte(output, out_offset, quantize(encoded.red));
        write_byte(output, out_offset + 1, quantize(encoded.green));
        write_byte(output, out_offset + 2, quantize(encoded.blue));
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

export c("lc_cyna_img_v7_render_working_rgb16") fn render_working_rgb16_contrast(input: *const c_float, input_len: c_size_t, output: *c_ushort, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double, slope: c_double): c_int {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_contrast_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma, slope) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_pixel_with_contrast(red as c_double, green as c_double, blue as c_double, plan, slope);
        write_word(output as! *c_uchar, offset, quantize16(encoded.red));
        write_word(output as! *c_uchar, offset + 1, quantize16(encoded.green));
        write_word(output as! *c_uchar, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}

// Explicit SDR output branch. The accepted fused entrypoints remain intact.
export c("lc_cyna_img_v8_render_working_rgba8") fn render_working_rgba8_split(input: *const c_float, input_len: c_size_t, output: *c_uchar, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): c_int {
    const valid = core.validate_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_pixel_split(red as c_double, green as c_double, blue as c_double, plan);
        write_byte(output, out_offset, quantize(encoded.red));
        write_byte(output, out_offset + 1, quantize(encoded.green));
        write_byte(output, out_offset + 2, quantize(encoded.blue));
        write_byte(output, out_offset + 3, 255);
        pixel = pixel + 1;
    }
    return 0;
}

export c("lc_cyna_img_v9_render_working_rgb16") fn render_working_rgb16_split(input: *const c_float, input_len: c_size_t, output: *c_ushort, output_len: c_size_t, width: c_size_t, height: c_size_t, max_pixels: c_size_t, exposure_ev: c_double, red_gain: c_double, green_gain: c_double, blue_gain: c_double, chroma: c_double): c_int {
    const valid = core.validate_rgb16_image(width as usize, height as usize, max_pixels as usize, input_len as usize, output_len as usize);
    if valid != 0 {
        return valid;
    }
    if not pipeline.valid_working_plan_parameters(exposure_ev, red_gain, green_gain, blue_gain, chroma) {
        return 4;
    }
    const plan = pipeline.working_srgb_plan_with_chroma(exposure_ev, red_gain, green_gain, blue_gain, chroma);
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
        const encoded = pipeline.encode_working_pixel_split(red as c_double, green as c_double, blue as c_double, plan);
        write_word(output as! *c_uchar, offset, quantize16(encoded.red));
        write_word(output as! *c_uchar, offset + 1, quantize16(encoded.green));
        write_word(output as! *c_uchar, offset + 2, quantize16(encoded.blue));
        pixel = pixel + 1;
    }
    return 0;
}
