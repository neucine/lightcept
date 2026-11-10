import { CameraMosaic } from .engine.raw.camera_mosaic;
import .engine.render.mosaic_render;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.develop.contrast;

// Versioned render choices for an already decoded camera-linear Bayer mosaic.
// These preserve the qualified DNG baseline, Z8 fitted, and Ricoh spatial
// sequences. A source adapter never chooses adjustment order or output depth.
pub const baseline_bilinear_v1: u32 = 1;
pub const fitted_mhc_v1: u32 = 2;
pub const spatial_headroom_v5: u32 = 3;

pub struct DevelopSettings {
    pub exposure_ev: f64;
    pub contrast_percent: f64;
}

// Only spatial_headroom_v5 uses these caller-owned buffers. Other modes may
// supply zero-length slices. All scratch and output are invalid on failure.
pub struct SpatialScratch {
    pub camera: []f32;
    pub band: []f64;
    pub source_pyramid: []f32;
    pub rim: []f32;
    pub lum: []f32;
    pub touched: []u8;
    pub near: []u8;
}

fn valid_mosaic(image: CameraMosaic, normalized: []const f32,
    width: usize, height: usize, output_length: usize, channels: usize
): bool {
    if image.width < 2 or image.height < 2 or
    image.height > 50000000 / image.width or
    normalized.len() != image.width * image.height or
    image.orientation < 1 or image.orientation > 8 or
    width == 0 or height == 0 or height > 4194304 / width or
    output_length != width * height * channels {
        return false;
    }
    var visual_width = image.width;
    var visual_height = image.height;
    if image.orientation >= 5 {
        visual_width = image.height;
        visual_height = image.width;
    }
    return width <= visual_width and height <= visual_height;
}

// Opaque, oriented sRGB RGBA8. Exposure is EV; contrast is percent.
// Mode and control validation precedes every pixel write.
pub fn render_rgba8(image: CameraMosaic, normalized: []const f32,
    output: []u8, width: usize, height: usize, mode: u32,
    edit: DevelopSettings, scratch: SpatialScratch,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if image.status != 0 {
        return image.status;
    }
    if not valid_mosaic(image, normalized, width, height, output.len(), 4) {
        return 4;
    }
    if mode == baseline_bilinear_v1 {
        if edit.exposure_ev != 0.0 or edit.contrast_percent != 0.0 {
            return 4;
        }
    } else if mode == fitted_mhc_v1 {
        if not (edit.exposure_ev >= -4.0 and edit.exposure_ev <= 4.0) or
        edit.contrast_percent != 0.0 {
            return 4;
        }
    } else if mode == spatial_headroom_v5 {
        if not (edit.exposure_ev >= -16.0 and edit.exposure_ev <= 16.0) or
        not (edit.contrast_percent >= -100.0 and edit.contrast_percent <= 100.0) {
            return 4;
        }
        return spatial_camera_pipeline.render_with_develop(normalized,
            image.width, image.height, image.cfa, image.camera_to_xyz_d50[0..],
            image.neutral, image.baseline_exposure_ev, edit.exposure_ev,
            contrast.slope_from_percent_native(edit.contrast_percent), image.orientation,
            scratch.camera, scratch.band, scratch.source_pyramid, scratch.rim,
            scratch.lum, scratch.touched, scratch.near, output, width, height,
            cancelled, context
        );
    } else {
        return 4;
    }
    var demosaic_version: u32 = 1;
    if mode == fitted_mhc_v1 {
        demosaic_version = 2;
    }
    return mosaic_render.render_oriented_rgba8(normalized,
        image.width, image.height, image.cfa, image.camera_to_xyz_d50,
        output, width, height, image.baseline_exposure_ev, edit.exposure_ev,
        demosaic_version, image.orientation, cancelled, context
    );
}

// Full oriented, encoded sRGB RGB16. The current qualified variant is the
// fitted MHC sequence used by the experimental Z8 TIFF route.
pub fn render_rgb16(image: CameraMosaic, normalized: []const f32,
    output: []u16, width: usize, height: usize, mode: u32,
    edit: DevelopSettings,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if image.status != 0 {
        return image.status;
    }
    if mode != fitted_mhc_v1 or
    not (edit.exposure_ev >= -4.0 and edit.exposure_ev <= 4.0) or
    edit.contrast_percent != 0.0 or
    not valid_mosaic(image, normalized, width, height, output.len(), 3) {
        return 4;
    }
    return mosaic_render.render_oriented_rgb16(normalized,
        image.width, image.height, image.cfa, image.camera_to_xyz_d50,
        output, width, height, image.baseline_exposure_ev, edit.exposure_ev,
        2, image.orientation, cancelled, context
    );
}
