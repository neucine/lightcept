import .engine.raw.camera_mosaic;
import .engine.raw.dng.dng_source;
import .engine.raw.dng.dng_sensor_geometry;
import .engine.color.dng.dng_color;
import .engine.raw.dng.dng_profile;
import .engine.color.dng.dng_color_matrix;
import .engine.raw.dng.dng_exposure;
import .engine.raw.dng.dng_orientation;

// Source-specific DNG preparation. Decodes stored sensor codes and produces a
// cropped camera-linear Bayer mosaic plus source color and orientation data.
// Caller owns the exact sample and mosaic buffers. Discard on nonzero status.
pub struct DngMosaicSize {
    pub stored_pixels: usize;
    pub crop_pixels: usize;
    pub crop_width: usize;
    pub crop_height: usize;
    pub status: i32;
}

// Resource contract for caller-owned scratch. A successful result describes
// unsigned stored sensor codes and cropped camera-linear Bayer f32 sample counts.
pub fn inspect(source: []const u8, max_pixels: usize): DngMosaicSize {
    var result: DngMosaicSize = {
        stored_pixels: 0,
        crop_pixels: 0,
        crop_width: 0,
        crop_height: 0,
        status: 1
    };
    if source.len() < 8 or source.len() > 512 * 1024 * 1024 {
        return result;
    }
    const storage = dng_source.inspect_storage(source.ptr as! *const u8, source.len());
    if storage.status != 0 {
        result.status = storage.status;
        return result;
    }
    if storage.compression != 7 or storage.photometric != 32803 {
        result.status = 2;
        return result;
    }
    if storage.width == 0 or storage.height == 0 or max_pixels == 0 or storage.height as usize > max_pixels or storage.width as usize > max_pixels / storage.height as usize {
        result.status = 3;
        return result;
    }
    const geometry = dng_sensor_geometry.inspect(source.ptr as! *const u8, source.len());
    if geometry.status != 0 {
        result.status = geometry.status;
        return result;
    }
    if geometry.stored_width != storage.width as usize or geometry.stored_height != storage.height as usize or geometry.crop_width == 0 or geometry.crop_height == 0 or geometry.crop_height > max_pixels / geometry.crop_width {
        result.status = 4;
        return result;
    }
    if geometry.stored_height > 33554432 / geometry.stored_width or geometry.crop_height > 33554432 / geometry.crop_width {
        result.status = 3;
        return result;
    }
    result.stored_pixels = geometry.stored_width * geometry.stored_height;
    result.crop_pixels = geometry.crop_width * geometry.crop_height;
    result.crop_width = geometry.crop_width;
    result.crop_height = geometry.crop_height;
    result.status = 0;
    return result;
}

// version 2 preserves the baseline normalization; version 3 retains
// headroom for the spatial correction route. Both use the same source probe.
pub fn decode_normalized(source: []const u8, samples: []u16, normalized: []f32,
    max_pixels: usize, normalization_version: u32,
    cancelled: fn (usize): bool, context: usize
): camera_mosaic.CameraMosaic {
    const size = inspect(source, max_pixels);
    if size.status != 0 {
        return camera_mosaic.failed(size.status);
    }
    if samples.len() != size.stored_pixels or normalized.len() != size.crop_pixels {
        return camera_mosaic.failed(4);
    }
    if normalization_version != 2 and normalization_version != 3 {
        return camera_mosaic.failed(4);
    }
    const source_ptr = source.ptr as! *const u8;
    var geometry: [16]u32 = [0] ** 16;
    var profile: [23]f64 = [0.0] ** 23;
    var matrix: [13]f64 = [0.0] ** 13;
    var exposure: [3]f64 = [0.0] ** 3;
    var orientation: [1]u32 = [0];
    var status = dng_sensor_geometry.probe(source_ptr, source.len() as usize, geometry[0..].ptr as! *u32, 16);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    status = dng_profile.probe_color_matrices(source_ptr, source.len() as usize, profile[0..].ptr as! *f64, 23);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    status = dng_color_matrix.derive(profile[0..].ptr as! *const f64, 23, matrix[0..].ptr as! *f64, 13);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    status = dng_exposure.probe(source_ptr, source.len() as usize, exposure[0..].ptr as! *f64, 3);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    status = dng_orientation.probe(source_ptr, source.len() as usize, orientation[0..].ptr as! *u32, 1);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    if cancelled(context) {
        return camera_mosaic.failed(7);
    }
    status = dng_source.decode_lossless_bayer(source, samples, max_pixels, cancelled, context);
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    if normalization_version == 2 {
        status = dng_sensor_geometry.normalize_v2(source_ptr, source.len() as usize, samples.ptr as! *const u16, samples.len() as usize, normalized.ptr as! *f32, normalized.len() as usize, cancelled, context);
    } else {
        status = dng_sensor_geometry.normalize_v3(source_ptr, source.len() as usize, samples.ptr as! *const u16, samples.len() as usize, normalized.ptr as! *f32, normalized.len() as usize, cancelled, context);
    }
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    return {
        width: size.crop_width,
        height: size.crop_height,
        cfa: [geometry[6], geometry[7], geometry[8], geometry[9]],
        camera_to_xyz_d50: [matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6], matrix[7], matrix[8]],
        neutral: [profile[18], profile[19], profile[20]],
        baseline_exposure_ev: exposure[2],
        orientation: orientation[0],
        status: 0
    };
}
