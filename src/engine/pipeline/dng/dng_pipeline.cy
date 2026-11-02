import .engine.raw.dng.dng_mosaic;
import .engine.pipeline.camera_mosaic_pipeline;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.develop.contrast;
import .engine.raw.camera_mosaic;
import { CameraMosaic } from .engine.raw.camera_mosaic;

pub fn inspect(source: []const u8, max_pixels: usize): dng_mosaic.DngMosaicSize {
    return dng_mosaic.inspect(source, max_pixels);
}

// Baseline v1: SOF3 sensor codes -> normalized cropped Bayer -> interpolated
// camera-to-XYZ D50 -> oriented bilinear preview -> opaque sRGB RGBA8.
// Scratch and output are caller-owned. Discard all buffers on failure.
pub fn render_baseline(source: []const u8, samples: []u16, normalized: []f32, output: []u8, width: usize, height: usize, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    const size = inspect(source, max_pixels);
    if size.status != 0 {
        return size.status;
    }
    if samples.len() != size.stored_pixels or normalized.len() != size.crop_pixels or width == 0 or height == 0 or height > 4194304 / width or output.len() != width * height * 4 {
        return 4;
    }
    const mosaic = dng_mosaic.decode_normalized(source, samples, normalized,
        max_pixels, 2, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    var visual_width = mosaic.width;
    var visual_height = mosaic.height;
    if mosaic.orientation >= 5 {
        visual_width = mosaic.height;
        visual_height = mosaic.width;
    }
    if width > visual_width or height > visual_height {
        return 4;
    }
    var empty_band: [0]f64 = [];
    const scratch: camera_mosaic_pipeline.SpatialScratch = {
        camera: normalized[0..0],
        band: empty_band[0..],
        source_pyramid: normalized[0..0],
        rim: normalized[0..0],
        lum: normalized[0..0],
        touched: output[0..0],
        near: output[0..0]
    };
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: 0.0,
        contrast_percent: 0.0
    };
    return camera_mosaic_pipeline.render_rgba8(mosaic, normalized, output,
        width, height, camera_mosaic_pipeline.baseline_bilinear_v1,
        edit, scratch, cancelled, context
    );
}

// SpatialHeadroomV5 product sequence, with explicit caller-owned scratch.
// The normalized mosaic retains sensor values above white; spatial correction
// runs on full camera RGB before orientation, resampling and sRGB encoding.
pub fn render_spatial_headroom(source: []const u8, samples: []u16, normalized: []f32, camera: []f32, band: []f64, source_pyramid: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    return render_spatial_headroom_with_exposure(source, samples, normalized, camera, band, source_pyramid, rim, lum, touched, near, output, width, height, 0.0, max_pixels, cancelled, context);
}

// User exposure is in EV stops relative to the DNG baseline exposure.
// The allowed -16..+16 range matches the Cyna develop edit contract.
pub fn render_spatial_headroom_with_exposure(source: []const u8, samples: []u16, normalized: []f32, camera: []f32, band: []f64, source_pyramid: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, user_exposure_ev: f64, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    return render_spatial_headroom_with_develop(source, samples, normalized, camera, band, source_pyramid, rim, lum, touched, near, output, width, height, user_exposure_ev, 0.0, max_pixels, cancelled, context);
}

// Product contrast is a percentage in -100..+100; its neutral value is zero.
pub fn render_spatial_headroom_with_develop(source: []const u8, samples: []u16, normalized: []f32, camera: []f32, band: []f64, source_pyramid: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, output: []u8, width: usize, height: usize, user_exposure_ev: f64, contrast_percent: f64, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    if not (user_exposure_ev >= -16.0 and user_exposure_ev <= 16.0) {
        return 4;
    }
    if not (contrast_percent >= -100.0 and contrast_percent <= 100.0) {
        return 4;
    }
    const size = inspect(source, max_pixels);
    if size.status != 0 {
        return size.status;
    }
    if samples.len() != size.stored_pixels or normalized.len() != size.crop_pixels or width == 0 or height == 0 or height > 4194304 / width or output.len() != width * height * 4 {
        return 4;
    }
    const need = spatial_camera_pipeline.spatial_requirements(size.crop_width, size.crop_height);
    if need.status != 0 {
        return need.status;
    }
    if camera.len() != need.camera_channels or band.len() != need.band_channels or source_pyramid.len() != need.source_channels or rim.len() != need.rim_channels or lum.len() != need.coarse_pixels or touched.len() != need.coarse_pixels or near.len() != need.coarse_pixels {
        return 4;
    }
    const mosaic = dng_mosaic.decode_normalized(source, samples, normalized,
        max_pixels, 3, cancelled, context
    );
    if mosaic.status != 0 {
        return mosaic.status;
    }
    var visual_width = mosaic.width;
    var visual_height = mosaic.height;
    if mosaic.orientation >= 5 {
        visual_width = mosaic.height;
        visual_height = mosaic.width;
    }
    if width > visual_width or height > visual_height {
        return 4;
    }
    const scratch: camera_mosaic_pipeline.SpatialScratch = {
        camera: camera,
        band: band,
        source_pyramid: source_pyramid,
        rim: rim,
        lum: lum,
        touched: touched,
        near: near
    };
    const edit: camera_mosaic_pipeline.DevelopSettings = {
        exposure_ev: user_exposure_ev,
        contrast_percent: contrast_percent
    };
    return camera_mosaic_pipeline.render_rgba8(mosaic, normalized, output,
        width, height, camera_mosaic_pipeline.spatial_headroom_v5,
        edit, scratch, cancelled, context
    );
}

// SpatialHeadroomV5: decodes a DNG once and prepares its edit-independent camera RGB raster.
// Caller retains camera and may discard all other scratch after success.
pub fn prepare_spatial_camera(source: []const u8, samples: []u16, normalized: []f32, camera: []f32, band: []f64, source_pyramid: []f32, rim: []f32, lum: []f32, touched: []u8, near: []u8, max_pixels: usize, cancelled: fn (usize): bool, context: usize): CameraMosaic {
    const size = inspect(source, max_pixels);
    if size.status != 0 {
        return camera_mosaic.failed(size.status);
    }
    const need = spatial_camera_pipeline.spatial_requirements(size.crop_width, size.crop_height);
    if need.status != 0 {
        return camera_mosaic.failed(need.status);
    }
    if samples.len() != size.stored_pixels or normalized.len() != size.crop_pixels or camera.len() != need.camera_channels or band.len() != need.band_channels or source_pyramid.len() != need.source_channels or rim.len() != need.rim_channels or lum.len() != need.coarse_pixels or touched.len() != need.coarse_pixels or near.len() != need.coarse_pixels {
        return camera_mosaic.failed(4);
    }
    const mosaic = dng_mosaic.decode_normalized(source, samples, normalized, max_pixels, 3, cancelled, context);
    if mosaic.status != 0 {
        return mosaic;
    }
    const status = spatial_camera_pipeline.prepare_camera(normalized, mosaic.width, mosaic.height, mosaic.cfa, mosaic.neutral, camera, band, source_pyramid, rim, lum, touched, near, cancelled, context);
    if status != 0 {
        return {
            width: mosaic.width,
            height: mosaic.height,
            cfa: mosaic.cfa,
            camera_to_xyz_d50: mosaic.camera_to_xyz_d50,
            neutral: mosaic.neutral,
            baseline_exposure_ev: mosaic.baseline_exposure_ev,
            orientation: mosaic.orientation,
            status: status
        };
    }
    return mosaic;
}

// User controls affect only this final stage; prepared pixels remain immutable.
pub fn render_prepared_spatial_camera(mosaic: CameraMosaic, camera: []const f32, output: []u8, width: usize, height: usize, exposure_ev: f64, contrast_percent: f64, cancelled: fn (usize): bool, context: usize): i32 {
    if mosaic.status != 0 {
        return mosaic.status;
    }
    if not (exposure_ev >= -16.0 and exposure_ev <= 16.0) or not (contrast_percent >= -100.0 and contrast_percent <= 100.0) {
        return 4;
    }
    return spatial_camera_pipeline.render_prepared(camera, mosaic.width, mosaic.height, mosaic.camera_to_xyz_d50, mosaic.baseline_exposure_ev, exposure_ev, contrast.slope_from_percent_native(contrast_percent), mosaic.orientation, output, width, height, cancelled, context);
}
