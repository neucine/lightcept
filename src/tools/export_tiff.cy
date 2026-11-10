import std.fs;
import std.process;
import .engine.pipeline.preview_develop_plan;
import .engine.develop.hsl_grading;
import .engine.develop.tonal_color_grade;
import .engine.develop.rgb_gradation;
import .tools.hsl_request;
import .tools.curve_request;
import .tools.grading_request;
import .engine.pipeline.nef.nef_pipeline;
import .engine.pipeline.nef.nef_tiff16_pipeline;
import .engine.pipeline.dng.dng_pipeline;
import .engine.pipeline.dng.dng_tiff16_pipeline;
import .engine.pipeline.spatial_camera_pipeline;
import .engine.pipeline.photo_geometry_pipeline;
import .engine.develop.photo_geometry;
import .engine.develop.orthogonal_transform;
import .engine.raw.dng.dng_orientation;
import .engine.tiff.rgb16_writer;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn rerender_hsl(working: []const f64, width: usize, height: usize,
    rgb16: []u16, icc: []const u8, tiff: []u8, baseline: f64,
    edits: preview_develop_plan.Controls, hsl: hsl_grading.EightBandEdit,
    grade: ?grading_request.GradingRecipe
): i32 {
    const mixed = hsl_request.apply_with_grade(working, width, height, hsl,
        grade
    );
    if mixed.status != 0 {
        return mixed.status;
    }
    const status = preview_develop_plan.render_rgb16(mixed.pixels[..].ptr,
        mixed.pixels.len(), rgb16.ptr, rgb16.len(), width, height,
        baseline, edits, no_cancel, 0
    );
    if status != 0 {
        return status;
    }
    return rgb16_writer.encode(rgb16, width, height, icc, tiff, no_cancel, 0);
}

// The standalone route currently holds the working frame, RGB16, and TIFF in
// memory at once. Bound the image before allocating those full-size buffers.
fn supported_geometry(width: usize, height: usize): bool {
    return width > 0 and height > 0 and width <= 10000 and height <= 10000
    and width * height <= 50000000;
}

fn integer(bytes: []const u8, offset: usize): i32 {
    const raw = (bytes[offset] as u64) | ((bytes[offset + 1] as u64) << 8)
    | ((bytes[offset + 2] as u64) << 16) | ((bytes[offset + 3] as u64) << 24);
    if raw >= 2147483648 {
        return (raw as i64 - 4294967296) as i32;
    }
    return raw as i32;
}

// Request v1 is a 52-byte little-endian record: format 1 DNG or 2 NEF,
// followed by the twelve schema-6 controls in project entry order. The native
// product boundary validates project/source identity before invoking this tool.
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

// Request v2 is 76 bytes: version 2, format, twelve controls, then left,
// top, width, height and signed millidegrees. Request v3 adds the user
// transform code for 80 bytes. A zero extent means full current canvas.
struct GeometryFields {
    enabled: bool;
    v3: bool;
    transform_code: i32;
    left: i32;
    top: i32;
    width: i32;
    height: i32;
    millidegrees: i32;
}

// Request v3 adds a user transform code after v2 millidegrees. Crop pixels
// are measured in the transformed upright canvas.
fn geometry_v2(fields: GeometryFields, width: usize,
    height: usize
): ?photo_geometry.RecipeV2 {
    if not supported_geometry(width, height) or
    fields.millidegrees < -17000 or fields.millidegrees > 17000 or
    fields.left < 0 or fields.top < 0 or
    fields.width < 0 or fields.height < 0 or
    fields.transform_code < 1 or fields.transform_code > 8 {
        return none;
    }
    const neutral = photo_geometry.neutral(width, height);
    const transform: orthogonal_transform.Transform = {
        version: 1,
        code: fields.transform_code as u32
    };
    const shape = orthogonal_transform.extent(transform, width, height);
    if shape.status != 0 {
        return none;
    }
    var recipe: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: neutral.straighten,
        transform: transform,
        crop: {
            version: 1,
            left: 0,
            top: 0,
            width: shape.width,
            height: shape.height
        }
    };
    if fields.width == 0 or fields.height == 0 {
        if fields.left != 0 or fields.top != 0 or
        fields.width != 0 or fields.height != 0 {
            return none;
        }
    } else {
        recipe.crop.left = fields.left as usize;
        recipe.crop.top = fields.top as usize;
        recipe.crop.width = fields.width as usize;
        recipe.crop.height = fields.height as usize;
    }
    recipe.straighten.angle_radians =
    (fields.millidegrees as f64) * 3.141592653589793 / 180000.0;
    if not photo_geometry.valid_v2(recipe, width, height) {
        return none;
    }
    return recipe;
}

fn geometry(fields: GeometryFields, width: usize,
    height: usize
): ?photo_geometry.Recipe {
    if not supported_geometry(width, height) or
    fields.millidegrees < -17000 or fields.millidegrees > 17000 or
    fields.left < 0 or fields.top < 0 or
    fields.width < 0 or fields.height < 0 {
        return none;
    }
    var recipe = photo_geometry.neutral(width, height);
    if fields.width == 0 or fields.height == 0 {
        if fields.left != 0 or fields.top != 0 or
        fields.width != 0 or fields.height != 0 {
            return none;
        }
    } else {
        var crop = recipe.crop;
        crop.left = fields.left as usize;
        crop.top = fields.top as usize;
        crop.width = fields.width as usize;
        crop.height = fields.height as usize;
        recipe.crop = crop;
    }
    var straighten = recipe.straighten;
    straighten.angle_radians =
    (fields.millidegrees as f64) * 3.141592653589793 / 180000.0;
    recipe.straighten = straighten;
    if not photo_geometry.valid(recipe, width, height) {
        return none;
    }
    return recipe;
}

fn zeros_u16(count: usize): [:]u16 {
    var output: [:]u16 = [: count]u16;
    var index: usize = 0;
    while index < count {
        output.push(0);
        index = index + 1;
    }
    return output;
}

fn zeros_f32(count: usize): [:]f32 {
    var output: [:]f32 = [: count]f32;
    var index: usize = 0;
    while index < count {
        output.push(0.0);
        index = index + 1;
    }
    return output;
}

fn zeros_f64(count: usize): [:]f64 {
    var output: [:]f64 = [: count]f64;
    var index: usize = 0;
    while index < count {
        output.push(0.0);
        index = index + 1;
    }
    return output;
}

fn zeros_u8(count: usize): [:]u8 {
    var output: [:]u8 = [: count]u8;
    var index: usize = 0;
    while index < count {
        output.push(0);
        index = index + 1;
    }
    return output;
}

fn export_nef(source: []const u8, icc: []const u8,
    output_path: string, edits: preview_develop_plan.Controls,
    fields: GeometryFields, hsl: ?hsl_grading.EightBandEdit,
    curve: ?rgb_gradation.FivePointEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const info = nef_pipeline.inspect_preview(source);
    if info.status != 0 {
        return info.status;
    }
    if not supported_geometry(info.visual_width, info.visual_height) {
        return 3;
    }
    var selected = photo_geometry.neutral(info.visual_width, info.visual_height);
    var selected_v2: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: selected.straighten,
        transform: {
            version: 1,
            code: 1
        },
        crop: selected.crop
    };
    if fields.v3 {
        const candidate = geometry_v2(fields, info.visual_width, info.visual_height);
        if candidate is none {
            return 4;
        }
        selected_v2 = candidate;
        selected.crop = selected_v2.crop;
    } else {
        const candidate = geometry(fields, info.visual_width, info.visual_height);
        if candidate is none {
            return 4;
        }
        selected = candidate;
    }
    const plan = rgb16_writer.layout(selected.crop.width, selected.crop.height,
        icc.len()
    );
    if plan.status != 0 {
        return plan.status;
    }
    var samples: [:]u16 = [: info.stored_pixels]u16;
    var normalized: [:]f32 = [: info.crop_pixels]f32;
    const channels = info.visual_width * info.visual_height * 3;
    var working: [:]f64 = [: channels]f64;
    const output_channels = selected.crop.width * selected.crop.height * 3;
    var rgb16: [:]u16 = [: output_channels]u16;
    var tiff: [:]u8 = [: plan.total_bytes]u8;
    var index: usize = 0;
    while index < info.stored_pixels {
        samples.push(0);
        index = index + 1;
    }
    index = 0;
    while index < info.crop_pixels {
        normalized.push(0.0);
        index = index + 1;
    }
    index = 0;
    while index < channels {
        working.push(0.0);
        index = index + 1;
    }
    index = 0;
    while index < output_channels {
        rgb16.push(0);
        index = index + 1;
    }
    index = 0;
    while index < plan.total_bytes {
        tiff.push(0);
        index = index + 1;
    }
    var status: i32 = 0;
    if fields.enabled {
        status = nef_pipeline.prepare_working_full(source, samples[..],
            normalized[..], working[..], info.visual_width, info.visual_height,
            no_cancel, 0
        );
        if status == 0 {
            var rotated_count: usize = 0;
            if fields.millidegrees != 0 {
                rotated_count = channels;
            }
            var rotated = zeros_f64(rotated_count);
            var cropped = zeros_f64(output_channels);
            if fields.v3 {
                status = photo_geometry_pipeline.render_tiff_v2(working[..],
                    info.visual_width, info.visual_height, selected_v2,
                    rotated[..], cropped[..], rgb16[..], icc, tiff[..],
                    0.0, edits, no_cancel, 0
                );
            } else {
                status = photo_geometry_pipeline.render_tiff(working[..],
                    info.visual_width, info.visual_height, selected, rotated[..],
                    cropped[..], rgb16[..], icc, tiff[..], 0.0, edits,
                    no_cancel, 0
                );
            }
            if status == 0 {
                if hsl is asset {
                    status = rerender_hsl(cropped[..], selected.crop.width,
                        selected.crop.height, rgb16[..], icc, tiff[..],
                        0.0, edits, asset, grade
                    );
                }
            }
        }
    } else {
        status = nef_tiff16_pipeline.render_developed(source, samples[..],
            normalized[..], working[..], rgb16[..], icc, tiff[..], edits,
            no_cancel, 0
        );
    }
    if status != 0 {
        return status;
    }
    if curve is edit {
        const curve_status = rgb_gradation.apply_rgb16_in_place(rgb16[..],
            selected.crop.width, selected.crop.height, edit, no_cancel, 0
        );
        if curve_status != 0 {
            return curve_status as i32;
        }
        status = rgb16_writer.encode(rgb16[..], selected.crop.width,
            selected.crop.height, icc, tiff[..], no_cancel, 0
        );
        if status != 0 {
            return status;
        }
    }
    fs.write_bytes(output_path, tiff[..]) catch (error) {
        return 1;
    };
    return 0;
}

fn export_dng(source: []const u8, icc: []const u8,
    output_path: string, edits: preview_develop_plan.Controls,
    fields: GeometryFields, hsl: ?hsl_grading.EightBandEdit,
    curve: ?rgb_gradation.FivePointEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const size = dng_pipeline.inspect(source, 33554432);
    if size.status != 0 {
        return size.status;
    }
    if not supported_geometry(size.crop_width, size.crop_height) {
        return 3;
    }
    var orientation: [1]u32 = [0];
    const orientation_status = dng_orientation.probe(source.ptr as! *const u8,
        source.len(), orientation[0..].ptr as! *u32, 1
    );
    if orientation_status != 0 {
        return orientation_status;
    }
    var visual_width = size.crop_width;
    var visual_height = size.crop_height;
    if orientation[0] >= 5 {
        visual_width = size.crop_height;
        visual_height = size.crop_width;
    }
    var selected = photo_geometry.neutral(visual_width, visual_height);
    var selected_v2: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: selected.straighten,
        transform: {
            version: 1,
            code: 1
        },
        crop: selected.crop
    };
    if fields.v3 {
        const candidate = geometry_v2(fields, visual_width, visual_height);
        if candidate is none {
            return 4;
        }
        selected_v2 = candidate;
        selected.crop = selected_v2.crop;
    } else {
        const candidate = geometry(fields, visual_width, visual_height);
        if candidate is none {
            return 4;
        }
        selected = candidate;
    }
    const need = spatial_camera_pipeline.spatial_requirements(
        size.crop_width, size.crop_height
    );
    if need.status != 0 {
        return need.status;
    }
    const plan = rgb16_writer.layout(selected.crop.width, selected.crop.height,
        icc.len()
    );
    if plan.status != 0 {
        return plan.status;
    }
    var samples = zeros_u16(size.stored_pixels);
    var normalized = zeros_f32(size.crop_pixels);
    var camera = zeros_f32(need.camera_channels);
    var band = zeros_f64(need.band_channels);
    var pyramid = zeros_f32(need.source_channels);
    var rim = zeros_f32(need.rim_channels);
    var lum = zeros_f32(need.coarse_pixels);
    var touched = zeros_u8(need.coarse_pixels);
    var near = zeros_u8(need.coarse_pixels);
    const channels = size.crop_width * size.crop_height * 3;
    var working = zeros_f64(channels);
    const output_channels = selected.crop.width * selected.crop.height * 3;
    var rgb16 = zeros_u16(output_channels);
    var tiff = zeros_u8(plan.total_bytes);
    var status: i32 = 0;
    if fields.enabled {
        const prepared = dng_pipeline.prepare_spatial_camera(source, samples[..],
            normalized[..], camera[..], band[..], pyramid[..], rim[..], lum[..],
            touched[..], near[..], 33554432, no_cancel, 0
        );
        status = prepared.status;
        if status == 0 and prepared.orientation != orientation[0] {
            status = 4;
        }
        if status == 0 {
            status = spatial_camera_pipeline.prepare_working_preview(camera[..],
                prepared.width, prepared.height, prepared.camera_to_xyz_d50,
                prepared.orientation, working[..], visual_width, visual_height,
                no_cancel, 0
            );
        }
        if status == 0 {
            var rotated_count: usize = 0;
            if fields.millidegrees != 0 {
                rotated_count = channels;
            }
            var rotated = zeros_f64(rotated_count);
            var cropped = zeros_f64(output_channels);
            if fields.v3 {
                status = photo_geometry_pipeline.render_tiff_v2(working[..],
                    visual_width, visual_height, selected_v2, rotated[..],
                    cropped[..], rgb16[..], icc, tiff[..],
                    prepared.baseline_exposure_ev, edits, no_cancel, 0
                );
            } else {
                status = photo_geometry_pipeline.render_tiff(working[..],
                    visual_width, visual_height, selected, rotated[..], cropped[..],
                    rgb16[..], icc, tiff[..], prepared.baseline_exposure_ev, edits,
                    no_cancel, 0
                );
            }
            if status == 0 {
                if hsl is asset {
                    status = rerender_hsl(cropped[..], selected.crop.width,
                        selected.crop.height, rgb16[..], icc, tiff[..],
                        prepared.baseline_exposure_ev, edits, asset, grade
                    );
                }
            }
        }
    } else {
        status = dng_tiff16_pipeline.render_developed(source, samples[..],
            normalized[..], camera[..], band[..], pyramid[..], rim[..], lum[..],
            touched[..], near[..], working[..], rgb16[..], icc, tiff[..], edits,
            no_cancel, 0
        );
    }
    if status != 0 {
        return status;
    }
    if curve is edit {
        const curve_status = rgb_gradation.apply_rgb16_in_place(rgb16[..],
            selected.crop.width, selected.crop.height, edit, no_cancel, 0
        );
        if curve_status != 0 {
            return curve_status as i32;
        }
        status = rgb16_writer.encode(rgb16[..], selected.crop.width,
            selected.crop.height, icc, tiff[..], no_cancel, 0
        );
        if status != 0 {
            return status;
        }
    }
    fs.write_bytes(output_path, tiff[..]) catch (error) {
        return 1;
    };
    return 0;
}

fn main(): i32 {
    const args = process.args();
    if args.len() != 5 {
        println("usage: export_tiff SOURCE ICC REQUEST OUTPUT");
        return 4;
    }
    const request = fs.read_bytes(args[3]) catch (error) {
        return 1;
    };
    if request.len() != 52 and request.len() != 76 and request.len() != 80
    and request.len() != 176 and request.len() != 212 and request.len() != 224 and request.len() != 276 and request.len() != 304 {
        return 4;
    }
    var format: i32 = 0;
    var offset: usize = 4;
    var fields: GeometryFields = {
        enabled: false,
        v3: false,
        transform_code: 1,
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        millidegrees: 0
    };
    if request.len() == 76 or request.len() == 80 or request.len() == 176 or request.len() == 212 or request.len() == 224 or (request.len() == 276 or request.len() == 304) {
        const version = integer(request[..], 0);
        if (request.len() == 76 and version != 2) or
        (request.len() == 80 and version != 3) or
        (request.len() == 176 and version != 4) or
        (request.len() == 212 and version != 5) or
        (request.len() == 224 and version != 6) or
        (((request.len() == 276 and version != 7) or (request.len() == 304 and version != 8))) {
            return 4;
        }
        format = integer(request[..], 4);
        offset = 8;
        fields.enabled = true;
        fields.left = integer(request[..], 56);
        fields.top = integer(request[..], 60);
        fields.width = integer(request[..], 64);
        fields.height = integer(request[..], 68);
        fields.millidegrees = integer(request[..], 72);
        if request.len() == 80 or request.len() == 176 or request.len() == 212 or request.len() == 224 or (request.len() == 276 or request.len() == 304) {
            fields.v3 = true;
            fields.transform_code = integer(request[..], 76);
        }
    } else {
        format = integer(request[..], 0);
    }
    if format != 1 and format != 2 {
        return 4;
    }
    var hsl: ?hsl_grading.EightBandEdit = none;
    if request.len() == 176 or request.len() == 212 or request.len() == 224 or (request.len() == 276 or request.len() == 304) {
        const decoded = hsl_request.decode(request[..], 80);
        if not decoded.valid {
            return 5;
        }
        hsl = decoded.edit;
    }
    var curve: ?rgb_gradation.FivePointEdit = none;
    if request.len() == 212 or request.len() == 224 or (request.len() == 276 or request.len() == 304) {
        const decoded = curve_request.decode(request[..], 176);
        if not decoded.valid {
            return 5;
        }
        curve = decoded.edit;
    }
    var grade: ?grading_request.GradingRecipe = none;
    if (request.len() == 276 or request.len() == 304) {
        const decoded = grading_request.decode(request[..], 224);
        if not decoded.valid {
            return 5;
        }
        grade = decoded.edit;
    }
    const edits = controls(request[..], offset);
    if not preview_develop_plan.valid(edits) {
        return 5;
    }
    const source = fs.read_bytes(args[1]) catch (error) {
        return 1;
    };
    if source.len() < 8 or source.len() > 512 * 1024 * 1024 {
        return 3;
    }
    const icc = fs.read_bytes(args[2]) catch (error) {
        return 1;
    };
    if format == 1 {
        return export_dng(source[..], icc[..], args[4], edits, fields, hsl, curve, grade);
    }
    return export_nef(source[..], icc[..], args[4], edits, fields, hsl, curve, grade);
}
