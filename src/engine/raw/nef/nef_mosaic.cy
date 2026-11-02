import .engine.raw.camera_mosaic;
import .engine.raw.nef.nef_source;
import .engine.raw.nef.nef_lossless;
import .engine.raw.nef.nef_sensor;
import .engine.color.nef.nikon_z8_profile;

// Headless Z8 lossless NEF source-to-mosaic v1. Caller-owned sample buffer is
// the full stored sensor raster; normalized is cropped camera-linear Bayer.
// Both lengths are exact photosite counts. Output is valid only on status 0.
// The source is immutable. Cancellation is checked at decode and normalize
// row boundaries. Processing is bounded to 50 million stored photosites.
pub fn decode_normalized(source: []const u8, samples: []u16, normalized: []f32,
    max_pixels: usize, cancelled: fn (usize): bool, context: usize
): camera_mosaic.CameraMosaic {
    const inspected = nef_source.inspect_source(source);
    if inspected.status != 0 {
        return camera_mosaic.failed(inspected.status);
    }
    const storage = inspected.storage;
    const maker = inspected.maker;
    const pixels = (storage.width as usize) * (storage.height as usize);
    const crop_pixels = (maker.crop[2] as usize) * (maker.crop[3] as usize);
    if pixels > max_pixels {
        return camera_mosaic.failed(3);
    }
    if samples.len() != pixels or normalized.len() != crop_pixels {
        return camera_mosaic.failed(4);
    }
    if cancelled(context) {
        return camera_mosaic.failed(7);
    }
    const strip = source[storage.strip_offset as usize..storage.strip_offset as usize + storage.strip_bytes as usize];
    const decoded = nef_lossless.decode(strip.ptr as! *const u8, strip.len() as usize,
        storage.width as usize, storage.height as usize,
        maker.seeds[0] as u32, maker.seeds[1] as u32,
        maker.seeds[2] as u32, maker.seeds[3] as u32,
        samples.ptr as! *u16, samples.len() as usize, cancelled, context
    );
    if decoded != 0 {
        return camera_mosaic.failed(decoded);
    }
    const status = nef_sensor.normalize(samples.ptr as! *const u16, samples.len() as usize,
        storage.width as usize, storage.height as usize,
        maker.crop[0] as usize, maker.crop[1] as usize,
        maker.crop[2] as usize, maker.crop[3] as usize,
        maker.black[0] as u32, maker.black[1] as u32,
        maker.black[2] as u32, maker.black[3] as u32,
        maker.white as u32, normalized.ptr as! *f32,
        normalized.len() as usize, cancelled, context
    );
    if status != 0 {
        return camera_mosaic.failed(status);
    }
    var matrix: [9]f64 = [0.0] ** 9;
    if nikon_z8_profile.camera_to_xyz_d50(maker.red_gain, maker.blue_gain) is values {
        matrix = values;
    } else {
        return camera_mosaic.failed(2);
    }
    const cropped_cfa = nef_sensor.cropped_cfa(storage.cfa, maker.crop[0], maker.crop[1]);
    return {
        width: maker.crop[2] as usize,
        height: maker.crop[3] as usize,
        cfa: [cropped_cfa % 256, (cropped_cfa >> 8) % 256,
            (cropped_cfa >> 16) % 256, (cropped_cfa >> 24) % 256
        ],
        orientation: storage.orientation,
        neutral: [1.0, 1.0, 1.0],
        baseline_exposure_ev: 0.0,
        camera_to_xyz_d50: matrix,
        status: 0
    };
}
