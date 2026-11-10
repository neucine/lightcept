import std.fs;
import std.process;
import .engine.pipeline.develop_region;
import .engine.pipeline.preview_develop_plan;
import .engine.develop.hsl_grading;
import .engine.develop.tonal_color_grade;
import .tools.grading_request;
import .engine.develop.rgb_gradation;
import .tools.hsl_request;
import .tools.curve_request;
import .engine.pipeline.nef.nef_pipeline;
import .engine.pipeline.dng.dng_pipeline;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.raw.dng.dng_orientation;
import .engine.raw.camera_mosaic;
import .engine.develop.straighten;
import .engine.develop.orthogonal_transform;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

// Request v1: format (1 compressed DNG, 2 lossless Z8 NEF), twelve signed
// controls, then left/top/width/height in upright source pixels (68 bytes).
// Request v2: version 2, format, twelve controls, tile rectangle in the
// cropped canvas, crop left/top/width/height, angle millidegrees (92 bytes).
// Request v3 adds the user transform code after the angle (96 bytes).
// All fields are little-endian i32. Output is opaque sRGB RGBA8.
fn integer(bytes: []const u8, offset: usize): i32 {
    const raw = (bytes[offset] as u64) | ((bytes[offset + 1] as u64) << 8)
    | ((bytes[offset + 2] as u64) << 16) | ((bytes[offset + 3] as u64) << 24);
    if raw >= 2147483648 {
        return (raw as i64 - 4294967296) as i32;
    }
    return raw as i32;
}

fn controls(request: []const u8, offset: usize): preview_develop_plan.Controls {
    return {
        exposure_tenths: integer(request, offset),
        contrast_percent: integer(request, offset + 4),
        shadows_percent: integer(request, offset + 8),
        highlights_percent: integer(request, offset + 12),
        blacks_percent: integer(request, offset + 16),
        whites_percent: integer(request, offset + 20),
        warmth_percent: integer(request, offset + 24),
        tint_percent: integer(request, offset + 28),
        vibrance_percent: integer(request, offset + 32),
        saturation_percent: integer(request, offset + 36),
        clarity_percent: integer(request, offset + 40),
        texture_percent: integer(request, offset + 44)
    };
}

fn translated_crop_region(source: []const u8, format: i32,
    requested: develop_region.Rect, left: i32, top: i32,
    width: i32, height: i32, angle: i32, transform_code: i32,
    edits: preview_develop_plan.Controls
): ?develop_region.Region {
    if angle < -17000 or angle > 17000 or
    transform_code < 1 or transform_code > 8 or
    left < 0 or top < 0 or width < 0 or height < 0 {
        return none;
    }
    var visual_width: usize = 0;
    var visual_height: usize = 0;
    if format == 1 {
        const size = dng_pipeline.inspect(source, 33554432);
        if size.status != 0 {
            return none;
        }
        var orientation: [1]u32 = [0];
        if dng_orientation.probe(source.ptr as! *const u8, source.len(),
            orientation[0..].ptr as! *u32, 1
        ) != 0 {
            return none;
        }
        visual_width = size.crop_width;
        visual_height = size.crop_height;
        if orientation[0] >= 5 {
            visual_width = size.crop_height;
            visual_height = size.crop_width;
        }
    } else {
        const info = nef_pipeline.inspect_preview(source);
        if info.status != 0 {
            return none;
        }
        visual_width = info.visual_width;
        visual_height = info.visual_height;
    }
    const transform: orthogonal_transform.Transform = {
        version: 1,
        code: transform_code as u32
    };
    const shape = orthogonal_transform.extent(transform, visual_width,
        visual_height
    );
    if shape.status != 0 {
        return none;
    }
    var crop_left: usize = 0;
    var crop_top: usize = 0;
    var crop_width = shape.width;
    var crop_height = shape.height;
    if width != 0 or height != 0 {
        if width <= 0 or height <= 0 {
            return none;
        }
        crop_left = left as usize;
        crop_top = top as usize;
        crop_width = width as usize;
        crop_height = height as usize;
    } else if left != 0 or top != 0 {
        return none;
    }
    if crop_left >= shape.width or crop_top >= shape.height or
    crop_width > shape.width - crop_left or
    crop_height > shape.height - crop_top {
        return none;
    }
    var region = develop_region.bounds(crop_width, crop_height,
        requested, edits
    );
    if region.status != 0 {
        return none;
    }
    region.source.left = region.source.left + crop_left;
    region.source.top = region.source.top + crop_top;
    region.requested.left = region.requested.left + crop_left;
    region.requested.top = region.requested.top + crop_top;
    return region;
}

fn rotation(angle: i32): straighten.StraightenAsset {
    return {
        version: straighten.algorithm_version,
        angle_radians: (angle as f64) * 3.141592653589793 / 180000.0,
        boundary_fill: [0.0, 0.0, 0.0]
    };
}

fn zeros_u16(count: usize): [:]u16 {
    var result: [:]u16 = [: count]u16;
    while result.len() < count {
        result.push(0);
    }
    return result;
}
fn zeros_f32(count: usize): [:]f32 {
    var result: [:]f32 = [: count]f32;
    while result.len() < count {
        result.push(0.0);
    }
    return result;
}
fn zeros_f64(count: usize): [:]f64 {
    var result: [:]f64 = [: count]f64;
    while result.len() < count {
        result.push(0.0);
    }
    return result;
}
fn zeros_u8(count: usize): [:]u8 {
    var result: [:]u8 = [: count]u8;
    while result.len() < count {
        result.push(0);
    }
    return result;
}

fn prepare_nef_region(source: []const u8, samples: []u16,
    normalized: []f32, visual_width: usize, visual_height: usize,
    rectangle: develop_region.Rect, angle: i32, working: []f64
): i32 {
    var prepared: i32 = 0;
    if angle == 0 {
        prepared = nef_pipeline.prepare_working_region(source, samples,
            normalized, rectangle.left, rectangle.top,
            rectangle.width, rectangle.height, working, no_cancel, 0
        );
    } else {
        const asset = rotation(angle);
        const window = straighten.source_window(visual_width,
            visual_height, asset, rectangle.left, rectangle.top,
            rectangle.width, rectangle.height
        );
        if window.status != 0 {
            return window.status as i32;
        }
        var source_window = zeros_f64(window.width * window.height * 3);
        prepared = nef_pipeline.prepare_working_region(source, samples,
            normalized, window.left, window.top, window.width,
            window.height, source_window[..], no_cancel, 0
        );
        if prepared == 0 {
            prepared = straighten.apply_window_region_f64(source_window[..],
                visual_width, visual_height, asset, window,
                rectangle.left, rectangle.top, rectangle.width,
                rectangle.height, working, no_cancel, 0
            ) as i32;
        }
    }
    return prepared;
}

fn render_nef(source: []const u8, requested: develop_region.Rect,
    edits: preview_develop_plan.Controls, output: []u8,
    selected: ?develop_region.Region, angle: i32, transform_code: i32,
    hsl: ?hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const info = nef_pipeline.inspect_preview(source);
    if info.status != 0 {
        return info.status;
    }
    var region = develop_region.bounds(info.visual_width,
        info.visual_height, requested, edits
    );
    if selected is override {
        region = override;
    }
    if region.status != 0 {
        return region.status;
    }
    var samples = zeros_u16(info.stored_pixels);
    var normalized = zeros_f32(info.crop_pixels);
    var working = zeros_f64(region.source.width * region.source.height * 3);
    var prepared: i32 = 0;
    if transform_code == 1 {
        prepared = prepare_nef_region(source, samples[..], normalized[..],
            info.visual_width, info.visual_height, region.source, angle,
            working[..]
        );
    } else {
        const transform: orthogonal_transform.Transform = {
            version: 1,
            code: transform_code as u32
        };
        const source_rect = orthogonal_transform.inverse_rect(transform,
            info.visual_width, info.visual_height, region.source.left,
            region.source.top, region.source.width, region.source.height
        );
        if source_rect.status != 0 {
            return 4;
        }
        const rectangle: develop_region.Rect = {
            left: source_rect.left,
            top: source_rect.top,
            width: source_rect.width,
            height: source_rect.height
        };
        var source_working = zeros_f64(rectangle.width * rectangle.height * 3);
        prepared = prepare_nef_region(source, samples[..], normalized[..],
            info.visual_width, info.visual_height, rectangle, angle,
            source_working[..]
        );
        if prepared == 0 {
            prepared = orthogonal_transform.apply_f64(source_working[..],
                rectangle.width, rectangle.height, transform, working[..],
                no_cancel, 0
            ) as i32;
        }
    }
    if prepared != 0 {
        return prepared;
    }
    if hsl is asset {
        const graded = hsl_request.apply_with_grade(working[..], region.source.width,
            region.source.height, asset, grade
        );
        if graded.status != 0 {
            return graded.status;
        }
        return develop_region.render(region, graded.pixels[..], output, 0.0,
            edits, no_cancel, 0
        );
    }
    return develop_region.render(region, working[..], output, 0.0,
        edits, no_cancel, 0
    );
}

// Keep the full sensor decode and spatial scratch out of the tile conversion
// lifetime. Only the prepared camera raster and its metadata leave this call.
fn prepare_dng_camera(source: []const u8, stored_pixels: usize,
    crop_pixels: usize, camera: []f32,
    need: spatial_camera_pipeline.SpatialRequirements
): camera_mosaic.CameraMosaic {
    var samples = zeros_u16(stored_pixels);
    var normalized = zeros_f32(crop_pixels);
    var band = zeros_f64(need.band_channels);
    var pyramid = zeros_f32(need.source_channels);
    var rim = zeros_f32(need.rim_channels);
    var lum = zeros_f32(need.coarse_pixels);
    var touched = zeros_u8(need.coarse_pixels);
    var near = zeros_u8(need.coarse_pixels);
    return dng_pipeline.prepare_spatial_camera(source, samples[..],
        normalized[..], camera, band[..], pyramid[..], rim[..], lum[..],
        touched[..], near[..], 33554432, no_cancel, 0
    );
}

fn prepare_dng_region(camera: []const f32,
    prepared: camera_mosaic.CameraMosaic, visual_width: usize,
    visual_height: usize, rectangle: develop_region.Rect,
    angle: i32, working: []f64
): i32 {
    var status: i32 = 0;
    if angle == 0 {
        status = spatial_camera_pipeline.prepare_working_region(camera,
            prepared.width, prepared.height, prepared.camera_to_xyz_d50,
            prepared.orientation, rectangle.left, rectangle.top,
            rectangle.width, rectangle.height, working, no_cancel, 0
        );
    } else {
        const asset = rotation(angle);
        const window = straighten.source_window(visual_width,
            visual_height, asset, rectangle.left, rectangle.top,
            rectangle.width, rectangle.height
        );
        if window.status != 0 {
            return window.status as i32;
        }
        var source_window = zeros_f64(window.width * window.height * 3);
        status = spatial_camera_pipeline.prepare_working_region(camera,
            prepared.width, prepared.height, prepared.camera_to_xyz_d50,
            prepared.orientation, window.left, window.top, window.width,
            window.height, source_window[..], no_cancel, 0
        );
        if status == 0 {
            status = straighten.apply_window_region_f64(source_window[..],
                visual_width, visual_height, asset, window,
                rectangle.left, rectangle.top, rectangle.width,
                rectangle.height, working, no_cancel, 0
            ) as i32;
        }
    }
    return status;
}

fn render_dng(source: []const u8, requested: develop_region.Rect,
    edits: preview_develop_plan.Controls, output: []u8,
    selected: ?develop_region.Region, angle: i32, transform_code: i32,
    hsl: ?hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const size = dng_pipeline.inspect(source, 33554432);
    if size.status != 0 {
        return size.status;
    }
    const need = spatial_camera_pipeline.spatial_requirements(
        size.crop_width, size.crop_height
    );
    if need.status != 0 {
        return need.status;
    }
    var camera = zeros_f32(need.camera_channels);
    const prepared = prepare_dng_camera(source, size.stored_pixels,
        size.crop_pixels, camera[..], need
    );
    if prepared.status != 0 {
        return prepared.status;
    }
    var visual_width = prepared.width;
    var visual_height = prepared.height;
    if prepared.orientation >= 5 {
        visual_width = prepared.height;
        visual_height = prepared.width;
    }
    var region = develop_region.bounds(visual_width, visual_height,
        requested, edits
    );
    if selected is override {
        region = override;
    }
    if region.status != 0 {
        return region.status;
    }
    var working = zeros_f64(region.source.width * region.source.height * 3);
    var status: i32 = 0;
    if transform_code == 1 {
        status = prepare_dng_region(camera[..], prepared, visual_width,
            visual_height, region.source, angle, working[..]
        );
    } else {
        const transform: orthogonal_transform.Transform = {
            version: 1,
            code: transform_code as u32
        };
        const source_rect = orthogonal_transform.inverse_rect(transform,
            visual_width, visual_height, region.source.left,
            region.source.top, region.source.width, region.source.height
        );
        if source_rect.status != 0 {
            return 4;
        }
        const rectangle: develop_region.Rect = {
            left: source_rect.left,
            top: source_rect.top,
            width: source_rect.width,
            height: source_rect.height
        };
        var source_working = zeros_f64(rectangle.width * rectangle.height * 3);
        status = prepare_dng_region(camera[..], prepared, visual_width,
            visual_height, rectangle, angle, source_working[..]
        );
        if status == 0 {
            status = orthogonal_transform.apply_f64(source_working[..],
                rectangle.width, rectangle.height, transform, working[..],
                no_cancel, 0
            ) as i32;
        }
    }
    if status != 0 {
        return status;
    }
    if hsl is asset {
        const graded = hsl_request.apply_with_grade(working[..], region.source.width,
            region.source.height, asset, grade
        );
        if graded.status != 0 {
            return graded.status;
        }
        return develop_region.render(region, graded.pixels[..], output,
            prepared.baseline_exposure_ev, edits, no_cancel, 0
        );
    }
    return develop_region.render(region, working[..], output,
        prepared.baseline_exposure_ev, edits, no_cancel, 0
    );
}

fn main(): i32 {
    const args = process.args();
    if args.len() != 4 {
        return 4;
    }
    const request = fs.read_bytes(args[2]) catch (error) {
        return 1;
    };
    if request.len() != 68 and request.len() != 92 and request.len() != 96
    and request.len() != 192 and request.len() != 228 and request.len() != 240 and request.len() != 292 and request.len() != 320 {
        return 4;
    }
    const versioned = request.len() != 68;
    if (request.len() == 92 and integer(request[..], 0) != 2) or
    (request.len() == 96 and integer(request[..], 0) != 3) or
    (request.len() == 192 and integer(request[..], 0) != 4) or
    (request.len() == 228 and integer(request[..], 0) != 5) or
    (request.len() == 240 and integer(request[..], 0) != 6) or
    (((request.len() == 292 and integer(request[..], 0) != 7) or (request.len() == 320 and integer(request[..], 0) != 8))) {
        return 4;
    }
    var format = integer(request[..], 0);
    var offset: usize = 4;
    if versioned {
        format = integer(request[..], 4);
        offset = 8;
    }
    if format != 1 and format != 2 {
        return 4;
    }
    const left = integer(request[..], offset + 48);
    const top = integer(request[..], offset + 52);
    const width = integer(request[..], offset + 56);
    const height = integer(request[..], offset + 60);
    if left < 0 or top < 0 or width <= 0 or height <= 0 or
    width > 4194304 / height {
        return 4;
    }
    const edits = controls(request[..], offset);
    if not preview_develop_plan.valid(edits) {
        return 5;
    }
    var requested: develop_region.Rect = {
        left: left as usize,
        top: top as usize,
        width: width as usize,
        height: height as usize
    };
    const source = fs.read_bytes(args[1]) catch (error) {
        return 1;
    };
    if source.len() < 8 or source.len() > 512 * 1024 * 1024 {
        return 3;
    }
    var selected: ?develop_region.Region = none;
    var angle: i32 = 0;
    var transform_code: i32 = 1;
    var hsl: ?hsl_grading.EightBandEdit = none;
    if request.len() == 192 or request.len() == 228 or request.len() == 240 or (request.len() == 292 or request.len() == 320) {
        const decoded = hsl_request.decode(request[..], 96);
        if not decoded.valid {
            return 5;
        }
        hsl = decoded.edit;
    }
    var curve: ?rgb_gradation.FivePointEdit = none;
    if request.len() == 228 or request.len() == 240 or (request.len() == 292 or request.len() == 320) {
        const decoded = curve_request.decode(request[..], 192);
        if not decoded.valid {
            return 5;
        }
        curve = decoded.edit;
    }
    var grade: ?grading_request.GradingRecipe = none;
    if (request.len() == 292 or request.len() == 320) {
        const decoded = grading_request.decode(request[..], 240);
        if not decoded.valid {
            return 5;
        }
        grade = decoded.edit;
    }
    if versioned {
        angle = integer(request[..], 88);
        if request.len() == 96 or request.len() == 192 or request.len() == 228 or request.len() == 240 or (request.len() == 292 or request.len() == 320) {
            transform_code = integer(request[..], 92);
        }
        const translated = translated_crop_region(source[..], format,
            requested, integer(request[..], 72), integer(request[..], 76),
            integer(request[..], 80), integer(request[..], 84),
            angle, transform_code, edits
        );
        if translated is none {
            return 4;
        }
        selected = translated;
    }
    var output = zeros_u8(requested.width * requested.height * 4);
    var status: i32 = 0;
    if format == 1 {
        status = render_dng(source[..], requested, edits, output[..], selected,
            angle, transform_code, hsl, grade
        );
    } else {
        status = render_nef(source[..], requested, edits, output[..], selected,
            angle, transform_code, hsl, grade
        );
    }
    if status != 0 {
        return status;
    }
    if curve is edit {
        const curve_status = rgb_gradation.apply_rgba8_in_place(output[..],
            requested.width, requested.height, edit, no_cancel, 0
        );
        if curve_status != 0 {
            return curve_status as i32;
        }
    }
    fs.write_bytes(args[3], output[..]) catch (error) {
        return 1;
    };
    return 0;
}
