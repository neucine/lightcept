import std.fs;
import std.process;
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
import .engine.pipeline.photo_geometry_pipeline;
import .engine.develop.photo_geometry;
import .engine.develop.orthogonal_transform;
import .engine.raw.dng.dng_orientation;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn render_hsl(working: []const f64, output: []u8, width: usize,
    height: usize, baseline: f64, edits: preview_develop_plan.Controls,
    hsl: hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const graded = hsl_request.apply_with_grade(working, width, height, hsl, grade);
    if graded.status != 0 {
        return graded.status;
    }
    return preview_develop_plan.render(graded.pixels[..].ptr,
        graded.pixels.len(), output.ptr, output.len(), width, height,
        baseline, edits, no_cancel, 0
    );
}

// Request v1 is format, twelve edit values, width and height in 60
// little-endian bytes. Request v2 is 84 bytes: version 2, format, twelve
// controls, fitted width and height, crop left/top/width/height and signed
// millidegrees. Request v3 adds a user transform code for 88 bytes. For a
// cached v8 request, format 3 reads fitted f64 working RGB from the source
// path and a single f64 baseline exposure from the fourth output path.
// Output is raw opaque sRGB RGBA8; RAW requests also write fitted working RGB.
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

struct GeometryFields {
    v3: bool;
    transform_code: i32;
    left: i32;
    top: i32;
    width: i32;
    height: i32;
    millidegrees: i32;
}

fn geometry_v2(fields: GeometryFields, width: usize,
    height: usize
): ?photo_geometry.RecipeV2 {
    if width == 0 or height == 0 or width > 10000 or height > 10000 or
    width > 50000000 / height or
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
    if width == 0 or height == 0 or width > 10000 or height > 10000 or
    width > 50000000 / height or
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

fn write_working(path: string, working: []f64): i32 {
    const length = working.len() * 8;
    var bytes: [:]u8 = [: length]u8;
    const pointer = working.ptr as! usize;
    var index: usize = 0;
    while index < length {
        unchecked {
            bytes.push(*((pointer + index) as! *const u8));
        }
        index = index + 1;
    }
    fs.write_bytes(path, bytes[..]) catch (error) {
        return 1;
    };
    return 0;
}

fn render_nef(source: []const u8, width: usize, height: usize,
    edits: preview_develop_plan.Controls, output: []u8, working_path: string,
    hsl: ?hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const info = nef_pipeline.inspect_preview(source);
    if info.status != 0 {
        return info.status;
    }
    var samples = zeros_u16(info.stored_pixels);
    var normalized = zeros_f32(info.crop_pixels);
    var working = zeros_f64(width * height * 3);
    const status = nef_pipeline.prepare_working(source, samples[..],
        normalized[..], working[..], width, height, no_cancel, 0
    );
    if status != 0 {
        return status;
    }
    const written = write_working(working_path, working[..]);
    if written != 0 {
        return written;
    }
    if hsl is asset {
        return render_hsl(working[..], output, width, height, 0.0, edits, asset, grade);
    }
    return preview_develop_plan.render(working[..].ptr, working.len(),
        output.ptr, output.len(), width, height, 0.0, edits, no_cancel, 0
    );
}

fn render_nef_geometry(source: []const u8, width: usize, height: usize,
    edits: preview_develop_plan.Controls, fields: GeometryFields,
    output: []u8, working_path: string, hsl: ?hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const info = nef_pipeline.inspect_preview(source);
    if info.status != 0 {
        return info.status;
    }
    var recipe = photo_geometry.neutral(info.visual_width, info.visual_height);
    var recipe_v2: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: recipe.straighten,
        transform: {
            version: 1,
            code: 1
        },
        crop: recipe.crop
    };
    if fields.v3 {
        const candidate = geometry_v2(fields, info.visual_width, info.visual_height);
        if candidate is none {
            return 4;
        }
        recipe_v2 = candidate;
        recipe.crop = recipe_v2.crop;
    } else {
        const candidate = geometry(fields, info.visual_width, info.visual_height);
        if candidate is none {
            return 4;
        }
        recipe = candidate;
    }
    if width > recipe.crop.width or height > recipe.crop.height {
        return 4;
    }
    var samples = zeros_u16(info.stored_pixels);
    var normalized = zeros_f32(info.crop_pixels);
    const channels = info.visual_width * info.visual_height * 3;
    var full = zeros_f64(channels);
    const prepared = nef_pipeline.prepare_working_full(source, samples[..],
        normalized[..], full[..], info.visual_width, info.visual_height,
        no_cancel, 0
    );
    if prepared != 0 {
        return prepared;
    }
    var rotated_count: usize = 0;
    if fields.millidegrees != 0 {
        rotated_count = channels;
    }
    var rotated = zeros_f64(rotated_count);
    var cropped = zeros_f64(recipe.crop.width * recipe.crop.height * 3);
    var fitted = zeros_f64(width * height * 3);
    var status: i32 = 0;
    if fields.v3 {
        status = photo_geometry_pipeline.render_preview_v2(full[..],
            info.visual_width, info.visual_height, recipe_v2, rotated[..],
            cropped[..], fitted[..], output, width, height, 0.0, edits,
            no_cancel, 0
        );
    } else {
        status = photo_geometry_pipeline.render_preview(full[..],
            info.visual_width, info.visual_height, recipe, rotated[..],
            cropped[..], fitted[..], output, width, height, 0.0, edits,
            no_cancel, 0
        );
    }
    if status != 0 {
        return status;
    }
    const written = write_working(working_path, fitted[..]);
    if written != 0 {
        return written;
    }
    if hsl is asset {
        return render_hsl(fitted[..], output, width, height, 0.0, edits, asset, grade);
    }
    return 0;
}

fn render_dng(source: []const u8, width: usize, height: usize,
    edits: preview_develop_plan.Controls, output: []u8, working_path: string,
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
    var samples = zeros_u16(size.stored_pixels);
    var normalized = zeros_f32(size.crop_pixels);
    var camera = zeros_f32(need.camera_channels);
    var band = zeros_f64(need.band_channels);
    var pyramid = zeros_f32(need.source_channels);
    var rim = zeros_f32(need.rim_channels);
    var lum = zeros_f32(need.coarse_pixels);
    var touched = zeros_u8(need.coarse_pixels);
    var near = zeros_u8(need.coarse_pixels);
    const prepared = dng_pipeline.prepare_spatial_camera(source, samples[..],
        normalized[..], camera[..], band[..], pyramid[..], rim[..], lum[..],
        touched[..], near[..], 33554432, no_cancel, 0
    );
    if prepared.status != 0 {
        return prepared.status;
    }
    var working = zeros_f64(width * height * 3);
    const status = spatial_camera_pipeline.prepare_working_preview(camera[..],
        prepared.width, prepared.height, prepared.camera_to_xyz_d50,
        prepared.orientation, working[..], width, height, no_cancel, 0
    );
    if status != 0 {
        return status;
    }
    const written = write_working(working_path, working[..]);
    if written != 0 {
        return written;
    }
    if hsl is asset {
        return render_hsl(working[..], output, width, height,
            prepared.baseline_exposure_ev, edits, asset, grade
        );
    }
    return preview_develop_plan.render(working[..].ptr, working.len(),
        output.ptr, output.len(), width, height,
        prepared.baseline_exposure_ev, edits, no_cancel, 0
    );
}

fn render_dng_geometry(source: []const u8, width: usize, height: usize,
    edits: preview_develop_plan.Controls, fields: GeometryFields,
    output: []u8, working_path: string, hsl: ?hsl_grading.EightBandEdit, grade: ?grading_request.GradingRecipe
): i32 {
    const size = dng_pipeline.inspect(source, 33554432);
    if size.status != 0 {
        return size.status;
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
    var recipe = photo_geometry.neutral(visual_width, visual_height);
    var recipe_v2: photo_geometry.RecipeV2 = {
        version: 2,
        straighten: recipe.straighten,
        transform: {
            version: 1,
            code: 1
        },
        crop: recipe.crop
    };
    if fields.v3 {
        const candidate = geometry_v2(fields, visual_width, visual_height);
        if candidate is none {
            return 4;
        }
        recipe_v2 = candidate;
        recipe.crop = recipe_v2.crop;
    } else {
        const candidate = geometry(fields, visual_width, visual_height);
        if candidate is none {
            return 4;
        }
        recipe = candidate;
    }
    if width > recipe.crop.width or height > recipe.crop.height {
        return 4;
    }
    const need = spatial_camera_pipeline.spatial_requirements(
        size.crop_width, size.crop_height
    );
    if need.status != 0 {
        return need.status;
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
    const prepared = dng_pipeline.prepare_spatial_camera(source, samples[..],
        normalized[..], camera[..], band[..], pyramid[..], rim[..], lum[..],
        touched[..], near[..], 33554432, no_cancel, 0
    );
    if prepared.status != 0 {
        return prepared.status;
    }
    if prepared.orientation != orientation[0] {
        return 4;
    }
    const channels = visual_width * visual_height * 3;
    var full = zeros_f64(channels);
    const working_status = spatial_camera_pipeline.prepare_working_preview(
        camera[..], prepared.width, prepared.height,
        prepared.camera_to_xyz_d50, prepared.orientation, full[..],
        visual_width, visual_height, no_cancel, 0
    );
    if working_status != 0 {
        return working_status;
    }
    var rotated_count: usize = 0;
    if fields.millidegrees != 0 {
        rotated_count = channels;
    }
    var rotated = zeros_f64(rotated_count);
    var cropped = zeros_f64(recipe.crop.width * recipe.crop.height * 3);
    var fitted = zeros_f64(width * height * 3);
    var status: i32 = 0;
    if fields.v3 {
        status = photo_geometry_pipeline.render_preview_v2(full[..],
            visual_width, visual_height, recipe_v2, rotated[..], cropped[..],
            fitted[..], output, width, height,
            prepared.baseline_exposure_ev, edits, no_cancel, 0
        );
    } else {
        status = photo_geometry_pipeline.render_preview(full[..],
            visual_width, visual_height, recipe, rotated[..], cropped[..],
            fitted[..], output, width, height,
            prepared.baseline_exposure_ev, edits, no_cancel, 0
        );
    }
    if status != 0 {
        return status;
    }
    const written = write_working(working_path, fitted[..]);
    if written != 0 {
        return written;
    }
    if hsl is asset {
        return render_hsl(fitted[..], output, width, height,
            prepared.baseline_exposure_ev, edits, asset, grade
        );
    }
    return 0;
}

fn main(): i32 {
    const args = process.args();
    if args.len() != 5 {
        return 4;
    }
    const request = fs.read_bytes(args[2]) catch (error) {
        return 1;
    };
    if request.len() != 60 and request.len() != 84 and request.len() != 88
    and request.len() != 184 and request.len() != 220 and request.len() != 232 and request.len() != 284 and request.len() != 312 {
        return 4;
    }
    var format: i32 = 0;
    var width_value: i32 = 0;
    var height_value: i32 = 0;
    var edit_offset: usize = 4;
    var fields: GeometryFields = {
        v3: false,
        transform_code: 1,
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        millidegrees: 0
    };
    if request.len() == 84 or request.len() == 88 or request.len() == 184 or request.len() == 220 or request.len() == 232 or (request.len() == 284 or request.len() == 312) {
        const version = integer(request[..], 0);
        if (request.len() == 84 and version != 2) or
        (request.len() == 88 and version != 3) or
        (request.len() == 184 and version != 4) or
        (request.len() == 220 and version != 5) or
        (request.len() == 232 and version != 6) or
        (((request.len() == 284 and version != 7) or (request.len() == 312 and version != 8))) {
            return 4;
        }
        format = integer(request[..], 4);
        edit_offset = 8;
        width_value = integer(request[..], 56);
        height_value = integer(request[..], 60);
        fields.left = integer(request[..], 64);
        fields.top = integer(request[..], 68);
        fields.width = integer(request[..], 72);
        fields.height = integer(request[..], 76);
        fields.millidegrees = integer(request[..], 80);
        if request.len() == 88 or request.len() == 184 or request.len() == 220 or request.len() == 232 or (request.len() == 284 or request.len() == 312) {
            fields.v3 = true;
            fields.transform_code = integer(request[..], 84);
        }
    } else {
        format = integer(request[..], 0);
        width_value = integer(request[..], 52);
        height_value = integer(request[..], 56);
    }
    if (format != 1 and format != 2 and format != 3) or width_value <= 0 or height_value <= 0 or
    width_value > 2048 or height_value > 2048 or
    width_value > 4194304 / height_value {
        return 4;
    }
    if request.len() != 60 and format == 3 and request.len() != 312 {
        return 4;
    }
    var hsl: ?hsl_grading.EightBandEdit = none;
    if request.len() == 184 or request.len() == 220 or request.len() == 232 or (request.len() == 284 or request.len() == 312) {
        const decoded = hsl_request.decode(request[..], 88);
        if not decoded.valid {
            return 5;
        }
        hsl = decoded.edit;
    }
    var curve: ?rgb_gradation.FivePointEdit = none;
    if request.len() == 220 or request.len() == 232 or (request.len() == 284 or request.len() == 312) {
        const decoded = curve_request.decode(request[..], 184);
        if not decoded.valid {
            return 5;
        }
        curve = decoded.edit;
    }
    var grade: ?grading_request.GradingRecipe = none;
    if (request.len() == 284 or request.len() == 312) {
        const decoded = grading_request.decode(request[..], 232);
        if not decoded.valid {
            return 5;
        }
        grade = decoded.edit;
    }
    const edits = controls(request[..], edit_offset);
    if not preview_develop_plan.valid(edits) {
        return 5;
    }
    const source = fs.read_bytes(args[1]) catch (error) {
        return 1;
    };
    if source.len() < 8 or source.len() > 512 * 1024 * 1024 {
        return 3;
    }
    const width = width_value as usize;
    const height = height_value as usize;
    var output = zeros_u8(width * height * 4);
    var status: i32 = 0;
    if format == 1 {
        if request.len() != 60 {
            status = render_dng_geometry(source[..], width, height, edits,
                fields, output[..], args[4], hsl, grade
            );
        } else {
            status = render_dng(source[..], width, height, edits, output[..], args[4], hsl, grade);
        }
    } else if format == 2 {
        if request.len() != 60 {
            status = render_nef_geometry(source[..], width, height, edits,
                fields, output[..], args[4], hsl, grade
            );
        } else {
            status = render_nef(source[..], width, height, edits, output[..], args[4], hsl, grade);
        }
    } else {
        if source.len() != width * height * 3 * 8 {
            return 4;
        }
        if request.len() == 312 {
            const baseline_bytes = fs.read_bytes(args[4]) catch (error) {
                return 1;
            };
            if baseline_bytes.len() != 8 {
                return 4;
            }
            var baseline: f64 = 0.0;
            unchecked {
                baseline = *(baseline_bytes[..].ptr as! *const f64);
            }
            if hsl is asset {
                var working = zeros_f64(width * height * 3);
                const destination = working[..].ptr as! usize;
                var byte_index: usize = 0;
                while byte_index < source.len() {
                    unchecked {
                        *((destination + byte_index) as! *u8) = source[byte_index];
                    }
                    byte_index = byte_index + 1;
                }
                status = render_hsl(working[..], output[..], width, height, baseline, edits, asset, grade);
            } else {
                status = preview_develop_plan.render(source[..].ptr as! *const f64,
                    width * height * 3, output[..].ptr, output.len(), width, height,
                    baseline, edits, no_cancel, 0
                );
            }
        } else {
            status = preview_develop_plan.render(source[..].ptr as! *const f64,
                width * height * 3, output[..].ptr, output.len(), width, height,
                0.0, edits, no_cancel, 0
            );
        }
    }
    if status != 0 {
        return status;
    }
    if curve is edit {
        const curve_status = rgb_gradation.apply_rgba8_in_place(output[..], width,
            height, edit, no_cancel, 0
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
