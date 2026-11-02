import .engine.render.dng.dng_preview_buffer;
import .engine.render.dng.dng_render;
import .engine.raw.dng.dng_source;
import .engine.raw.dng.dng_profile;
import .engine.develop.control_bounds;

// Qualified DNG preview route for LinearRaw and the byte-backed Bayer path.
// Inspect and validate the legacy source before entering the pixel kernel.
fn render_fitted_rgba8(input: *const u8, length: usize, output: *u8,
    output_len: usize, max_pixels: usize, photometric: u32,
    width: usize, height: usize, cancelled: fn (usize): bool, context: usize
): i32 {
    const info = dng_source.inspect(input, length, max_pixels);
    if info.status != 0 {
        return info.status;
    }
    if info.photometric != photometric or not dng_source.has_render_profile(info) {
        return 2;
    }
    if width == 0 or height == 0 or width > info.width or height > info.height or
    output_len != width * height * 4 {
        return 4;
    }
    if not control_bounds.valid_parameters(0.0, 1.0, 1.0, 1.0) {
        return 5;
    }
    if not dng_profile.valid_denominators(input, info.forward_matrix_offset, info.neutral_offset) {
        return 2;
    }
    const profile = dng_profile.load(input, info.forward_matrix_offset, info.neutral_offset);
    if not profile.valid {
        return 2;
    }
    return dng_render.render_prepared(input, output, info, profile,
        width, height, 0.0, photometric, 8, cancelled, context
    );
}

// Output is RGBA8 sRGB with a tightly packed row stride of width * 4 bytes.
// Status 4 means an invalid buffer or preview geometry; status 1 means an
// invalid source size. Status 7 means cancellation. The callback is polled at
// render row boundaries. A nonzero status leaves output undefined; discard it.
pub fn render_fitted_raw(source: *const u8, source_len: usize, output: *u8, output_len: usize, width: usize, height: usize, cancelled: fn (usize): bool, context: usize): i32 {
    if source as! usize == 0 or output as! usize == 0 or source_len < 8 or source_len > dng_preview_buffer.source_byte_limit() {
        return 1;
    }
    if width == 0 or height == 0 or width > dng_preview_buffer.preview_side_limit() or height > dng_preview_buffer.preview_side_limit() {
        return 4;
    }
    const pixel_count = width * height;
    if output_len != pixel_count * 4 {
        return 4;
    }
    const info = dng_preview_buffer.probe_raw(source, source_len);
    if info.status != 0 {
        return info.status;
    }
    if width > info.width or height > info.height {
        return 4;
    }
    return render_fitted_rgba8(source, source_len,
        output, output_len, dng_preview_buffer.source_pixel_limit(),
        info.photometric, width, height, cancelled, context
    );
}

pub fn render_fitted(source: []const u8, output: []u8, width: usize, height: usize, cancelled: fn (usize): bool, context: usize): i32 {
    if source.len() == 0 or output.len() == 0 {
        return 4;
    }
    return render_fitted_raw(source.ptr as! *const u8, source.len(),
        output.ptr as! *u8, output.len(), width, height, cancelled, context
    );
}
