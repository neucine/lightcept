import .engine.raw.bayer;
import .engine.color.spatial_highlight;
import .engine.color.white_balance;
import .engine.render.camera_rgb_preview;
import .engine.core.float_round;

pub struct SpatialRequirements {
    pub camera_channels: usize;
    pub band_channels: usize;
    pub source_channels: usize;
    pub rim_channels: usize;
    pub coarse_pixels: usize;
    pub source_levels: usize;
    pub rim_levels: usize;
    pub status: c_int;
}

pub const max_spatial_scratch_bytes: usize = 768 * 1024 * 1024;

fn pyramid_length(width: usize, height: usize, channels: usize): [2]usize {
    var w = width;
    var h = height;
    var length: usize = 0;
    var levels: usize = 0;
    var done = false;
    while not done {
        length = length + w * h * channels;
        levels = levels + 1;
        if w == 1 and h == 1 {
            done = true;
        } else {
            w = (w + 1) / 2;
            h = (h + 1) / 2;
        }
    }
    return [length, levels];
}

pub fn spatial_requirements(width: usize, height: usize): SpatialRequirements {
    var result: SpatialRequirements = {
        camera_channels: 0,
        band_channels: 0,
        source_channels: 0,
        rim_channels: 0,
        coarse_pixels: 0,
        source_levels: 0,
        rim_levels: 0,
        status: 4
    };
    if width < 2 or height < 2 or height > 33554432 / width {
        return result;
    }
    const coarse_width = (width + 1) / 2;
    const coarse_height = (height + 1) / 2;
    const source = pyramid_length(coarse_width, coarse_height, 3);
    const rim = pyramid_length((width + 3) / 4, (height + 3) / 4, 4);
    if source[1] > 32 or rim[1] > 32 {
        return result;
    }
    const scratch_bytes = width * height * 3 * 4 + width * 32 * 3 * 8 + source[0] * 4 + rim[0] * 4 + coarse_width * coarse_height * 6;
    if scratch_bytes > max_spatial_scratch_bytes {
        result.status = 3;
        return result;
    }
    result.camera_channels = width * height * 3;
    result.band_channels = width * 32 * 3;
    result.source_channels = source[0];
    result.rim_channels = rim[0];
    result.coarse_pixels = coarse_width * coarse_height;
    result.source_levels = source[1];
    result.rim_levels = rim[1];
    result.status = 0;
    return result;
}

fn level_metadata(meta: []usize, width: usize, height: usize, channels: usize): void {
    var w = width;
    var h = height;
    var offset: usize = 0;
    var level: usize = 0;
    var done = false;
    while level < meta.len() / 3 and not done {
        meta[level * 3] = offset;
        meta[level * 3 + 1] = w;
        meta[level * 3 + 2] = h;
        offset = offset + w * h * channels;
        if w == 1 and h == 1 {
            done = true;
        } else {
            w = (w + 1) / 2;
            h = (h + 1) / 2;
            level = level + 1;
        }
    }
}

// SpatialHeadroomV5 camera stage. Input is cropped, headroom-preserving,
// black-subtracted Bayer f32. The output is encoded sRGB RGBA8. All scratch
// remains caller-owned and is undefined after a nonzero result.
pub fn render(normalized: []const f32, source_width: usize, source_height: usize, cfa: [4]u32, matrix: []const f64, neutral: [3]f64, default_exposure: f64, orientation: u32, camera: []f32, band: []f64, source: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar): c_int {
    return render_with_exposure(normalized, source_width, source_height, cfa, matrix, neutral, default_exposure, 0.0, orientation, camera, band, source, rim, lum, touched, near, output, width, height, cancelled, context);
}

pub fn render_with_exposure(normalized: []const f32, source_width: usize, source_height: usize, cfa: [4]u32, matrix: []const f64, neutral: [3]f64, default_exposure: f64, user_exposure: f64, orientation: u32, camera: []f32, band: []f64, source: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar): c_int {
    return render_with_develop(normalized, source_width, source_height, cfa, matrix, neutral, default_exposure, user_exposure, 1.0, orientation, camera, band, source, rim, lum, touched, near, output, width, height, cancelled, context);
}

pub fn render_with_develop(normalized: []const f32, source_width: usize, source_height: usize, cfa: [4]u32, matrix: []const f64, neutral: [3]f64, default_exposure: f64, user_exposure: f64, contrast_slope: f64, orientation: u32, camera: []f32, band: []f64, source: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, cancelled: c fn (*const c_uchar): c_int, context: *const c_uchar): c_int {
    const need = spatial_requirements(source_width, source_height);
    if need.status != 0 {
        return need.status;
    }
    if normalized.len() != source_width * source_height or matrix.len() != 9 or camera.len() != need.camera_channels or band.len() != need.band_channels or source.len() != need.source_channels or rim.len() != need.rim_channels or lum.len() != need.coarse_pixels or touched.len() != need.coarse_pixels or near.len() != need.coarse_pixels or width == 0 or height == 0 or height > 4194304 / width or output.len() != width * height * 4 {
        return 4;
    }
    var visual_width = source_width;
    var visual_height = source_height;
    if orientation >= 5 and orientation <= 8 {
        visual_width = source_height;
        visual_height = source_width;
    }
    if orientation < 1 or orientation > 8 or width > visual_width or height > visual_height {
        return 4;
    }
    var source_meta: [96]usize = [0] ** 96;
    var rim_meta: [96]usize = [0] ** 96;
    level_metadata(source_meta[0..need.source_levels * 3], (source_width + 1) / 2, (source_height + 1) / 2, 3);
    level_metadata(rim_meta[0..need.rim_levels * 3], (source_width + 3) / 4, (source_height + 3) / 4, 4);
    var row: usize = 0;
    while row < source_height {
        if cancelled(context) != 0 {
            return 7;
        }
        var rows: usize = 32;
        if rows > source_height - row {
            rows = source_height - row;
        }
        const channels = rows * source_width * 3;
        const status = bayer.demosaic_normalized_bayer_rows_camera(normalized.ptr as! *const c_float, normalized.len() as c_size_t,
            source_width as c_size_t, source_height as c_size_t, cfa[0..].ptr as! *const c_uint, 4,
            row as c_size_t, rows as c_size_t, band.ptr as! *c_double, channels as c_size_t, 1
        );
        if status != 0 {
            return status;
        }
        var index: usize = 0;
        while index < channels {
            const rounded = float_round.to_f32(band[index]);
            if rounded is value {
                camera[row * source_width * 3 + index] = value;
            } else {
                return 2;
            }
            index = index + 1;
        }
        row = row + rows;
    }
    if neutral[0] < 0.05 or neutral[0] > 8.0 or neutral[1] < 0.05 or neutral[1] > 8.0 or neutral[2] < 0.05 or neutral[2] > 8.0 {
        return 5;
    }
    const red_gain = float_round.to_f32(white_balance.camera_neutral_gain(neutral[0] as c_double) as f64);
    const green_gain = float_round.to_f32(white_balance.camera_neutral_gain(neutral[1] as c_double) as f64);
    const blue_gain = float_round.to_f32(white_balance.camera_neutral_gain(neutral[2] as c_double) as f64);
    var gain: [3]f32 = [0.0, 0.0, 0.0];
    if red_gain is red {
        gain[0] = red;
    } else {
        return 5;
    }
    if green_gain is green {
        gain[1] = green;
    } else {
        return 5;
    }
    if blue_gain is blue {
        gain[2] = blue;
    } else {
        return 5;
    }
    if cancelled(context) != 0 {
        return 7;
    }
    const spatial_status = spatial_highlight.reconstruct(camera.ptr as! *c_float, source_width as c_size_t, source_height as c_size_t,
        gain[0..].ptr as! *const c_float, source.ptr as! *c_float, source_meta[0..].ptr as! *const c_size_t, need.source_levels as c_size_t,
        rim.ptr as! *c_float, rim_meta[0..].ptr as! *const c_size_t, need.rim_levels as c_size_t,
        lum.ptr as! *c_float, touched.ptr as! *c_uchar, near.ptr as! *c_uchar,
        camera.len() as c_size_t, 3, source.len() as c_size_t, (need.source_levels * 3) as c_size_t,
        rim.len() as c_size_t, (need.rim_levels * 3) as c_size_t, lum.len() as c_size_t, touched.len() as c_size_t, near.len() as c_size_t
    );
    if spatial_status != 0 {
        return spatial_status;
    }
    if cancelled(context) != 0 {
        return 7;
    }
    return camera_rgb_preview.render_preview_with_contrast(camera.ptr as! *const c_float, camera.len() as c_size_t, source_width as c_size_t, source_height as c_size_t,
        matrix.ptr as! *const c_double, 9, output.ptr as! *c_uchar, output.len() as c_size_t,
        width as c_size_t, height as c_size_t, default_exposure as c_double, user_exposure as c_double, contrast_slope as c_double, orientation as c_uint, cancelled, context
    );
}
