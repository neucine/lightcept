import .engine.pipeline.color_solution_plan;
import .engine.develop.rgb_gradation;
import .engine.color.working_to_linear_srgb;
import .engine.color.srgb_clip;
import .engine.color.srgb_transfer;
import .engine.develop.chroma_map;

// Immutable prepared scene frame v1. The producer verifies the SHA-256
// identities against its source and camera-characterization contract before
// handing this value to the headless executor.
pub struct SceneFrame {
    pub version: u32;
    pub domain: u32;
    pub source_sha256: [32]u8;
    pub source_profile_sha256: [32]u8;
    pub width: usize;
    pub height: usize;
    pub samples: []const f32;
}

fn same(left: [32]u8, right: [32]u8): bool {
    var index: usize = 0;
    while index < 32 {
        if left[index] != right[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

fn valid_scene_frame(plan: color_solution_plan.Plan, frame: &const SceneFrame): bool {
    return frame.version == 1
    and frame.domain == color_solution_plan.SCENE_LINEAR_REC2020_D65
    and frame.width == plan.width and frame.height == plan.height
    and same(frame.source_sha256, plan.source_sha256)
    and same(frame.source_profile_sha256, plan.source_profile_sha256);
}

fn finish_scene(width: usize, height: usize, asset: &const rgb_gradation.Asset,
    input: []const f32, linear: []f32, clipped: []f32,
    encoded: []f32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    var status = working_to_linear_srgb.apply(input, width, height,
        linear, cancelled, context
    );
    if status == 7 {
        return 7;
    }
    if status != 0 {
        return 4;
    }
    status = srgb_clip.apply(linear[..], width, height,
        clipped, cancelled, context
    );
    if status == 7 {
        return 7;
    }
    if status != 0 {
        return 4;
    }
    status = srgb_transfer.apply(clipped[..], width, height,
        encoded, cancelled, context
    );
    if status == 7 {
        return 7;
    }
    if status != 0 {
        return 4;
    }
    status = rgb_gradation.apply_image(encoded[..], width, height,
        asset, output, cancelled, context
    );
    if status == 7 {
        return 7;
    }
    if status != 0 {
        return 5;
    }
    return 0;
}

// Executes route v2 on immutable, interleaved encoded sRGB/D65 f32 samples.
// The caller verifies source_sha256 against the input frame's immutable source
// contract. The engine verifies the supplied gradation asset against its pin.
// Output is disjoint and caller-owned; publish only status 0. Status 1 rejects
// route/replay/domain, 2 rejects asset identity, 3 rejects shape or input,
// 7 reports cancellation. No source pixels are modified.
pub fn render(plan: color_solution_plan.Plan,
    request: &const color_solution_plan.Request,
    asset: &const rgb_gradation.Asset,
    input: []const f32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if plan.route_version != 2 or not color_solution_plan.matches(plan, request) {
        return 1;
    }
    var digest: [32]u8 = [0] ** 32;
    const digest_status = rgb_gradation.digest(asset, digest[0..], cancelled, context);
    if digest_status == 7 {
        return 7;
    }
    if digest_status != 0 or not rgb_gradation.is_srgb(asset.domain)
    or not same(digest, plan.operations[0].asset_sha256) {
        return 2;
    }
    const result = rgb_gradation.apply_image(input, plan.width, plan.height,
        asset, output, cancelled, context
    );
    if result == 0 or result == 7 {
        return result;
    }
    return 3;
}

// Route v3 composes the color component's version-1 Rec.2020/D65 matrix,
// linear sRGB destination clip, IEC sRGB transfer, then develop gradation.
// Source is immutable scene-linear Rec.2020/D65 f32 RGB in [-0.25,8]. The
// three disjoint scratch buffers and final output are caller-owned and have
// exactly width*height*3 samples. The caller verifies source_sha256 against
// the prepared frame and source_profile_sha256 against its characterization.
// Status 0 success, 1 plan/replay/domain, 2 asset, 3 shape, 4 conversion or
// source range, 5 gradation input, 7 cancellation. Any failure invalidates
// final output; stages only write scratch until the last kernel succeeds.
pub fn render_scene(plan: color_solution_plan.Plan,
    request: &const color_solution_plan.Request,
    asset: &const rgb_gradation.Asset,
    frame: &const SceneFrame, linear: []f32, clipped: []f32,
    encoded: []f32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if plan.route_version != 3 or not color_solution_plan.matches(plan, request) {
        return 1;
    }
    if not valid_scene_frame(plan, frame) {
        return 1;
    }
    const count = plan.width * plan.height * 3;
    if frame.samples.len() != count or linear.len() != count or clipped.len() != count
    or encoded.len() != count or output.len() != count {
        return 3;
    }
    var digest: [32]u8 = [0] ** 32;
    const digest_status = rgb_gradation.digest(asset, digest[0..], cancelled, context);
    if digest_status == 7 {
        return 7;
    }
    if digest_status != 0 or not rgb_gradation.is_srgb(asset.domain)
    or not same(digest, plan.operations[1].asset_sha256) {
        return 2;
    }
    return finish_scene(plan.width, plan.height, asset, frame.samples,
        linear, clipped, encoded, output, cancelled, context
    );
}

// Route v4 validates two caller assets before composing chroma correction,
// view conversion, and per-channel gradation. Chroma uses scene-linear
// Rec.2020/D65 reference-white units; other declared chroma primaries are
// accepted by the component but cannot enter this route. `mapped` is a fourth
// disjoint caller-owned scratch buffer. Status 6 identifies chroma input or
// result failure; all other statuses match render_scene. Publish only status 0.
pub fn render_scene_chroma(plan: color_solution_plan.Plan,
    request: &const color_solution_plan.Request,
    chroma: &const chroma_map.ChromaMapAsset, gradation: &const rgb_gradation.Asset,
    frame: &const SceneFrame, mapped: []f32, linear: []f32,
    clipped: []f32, encoded: []f32, output: []f32,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if plan.route_version != 4 or not color_solution_plan.matches(plan, request)
    or not valid_scene_frame(plan, frame) {
        return 1;
    }
    const count = plan.width * plan.height * 3;
    if frame.samples.len() != count or mapped.len() != count
    or linear.len() != count or clipped.len() != count
    or encoded.len() != count or output.len() != count {
        return 3;
    }
    var chroma_digest: [32]u8 = [0] ** 32;
    const chroma_status = chroma_map.digest(chroma, chroma_digest[0..],
        cancelled, context
    );
    if chroma_status == 7 {
        return 7;
    }
    if chroma_status != 0 or chroma.primaries != chroma_map.REC2020_D65
    or not same(chroma_digest, plan.operations[0].asset_sha256) {
        return 2;
    }
    var gradation_digest: [32]u8 = [0] ** 32;
    const gradation_status = rgb_gradation.digest(gradation,
        gradation_digest[0..], cancelled, context
    );
    if gradation_status == 7 {
        return 7;
    }
    if gradation_status != 0 or not rgb_gradation.is_srgb(gradation.domain)
    or not same(gradation_digest, plan.operations[2].asset_sha256) {
        return 2;
    }
    const status = chroma_map.apply_image(frame.samples, plan.width,
        plan.height, chroma, mapped, cancelled, context
    );
    if status == 7 {
        return 7;
    }
    if status != 0 {
        return 6;
    }
    return finish_scene(plan.width, plan.height, gradation, mapped[..],
        linear, clipped, encoded, output, cancelled, context
    );
}
