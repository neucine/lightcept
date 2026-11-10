import .engine.develop.rgb_gradation;

test "five point editor preserves neutral RGB and isolates a channel" {
    var edit = rgb_gradation.neutral_five_point_edit();
    assert(rgb_gradation.valid_five_point_edit(edit));
    const neutral = rgb_gradation.editor_asset(edit);
    const input: [3]f32 = [0.375, 0.375, 0.375];
    var output: [3]f32 = [0.0] ** 3;
    assert(rgb_gradation.apply_image(input[..], 1, 1, &neutral,
        output[..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[1] == input[1]
        and output[2] == input[2]
    );
    edit.red = [125, 250, 625];
    const changed = rgb_gradation.editor_asset(edit);
    assert(rgb_gradation.apply_image(input[..], 1, 1, &changed,
        output[..], no_cancel, 0
    ) == 0);
    assert(output[0] == 0.1875 and output[1] == 0.375
        and output[2] == 0.375
    );
    edit.red = [501, 500, 750];
    assert(not rgb_gradation.valid_five_point_edit(edit));
    const invalid = rgb_gradation.editor_asset(edit);
    assert(not rgb_gradation.valid(&invalid));
}

test "five point editor maps rendered 8-bit and 16-bit sRGB consistently" {
    var edit = rgb_gradation.neutral_five_point_edit();
    edit.red = [125, 250, 625];
    var rgba: [4]u8 = [128, 128, 128, 255];
    var rgb16: [3]u16 = [32768, 32768, 32768];
    assert(rgb_gradation.apply_rgba8_in_place(rgba[..], 1, 1, edit,
        no_cancel, 0
    ) == 0);
    assert(rgb_gradation.apply_rgb16_in_place(rgb16[..], 1, 1, edit,
        no_cancel, 0
    ) == 0);
    assert(rgba[0] >= 64 and rgba[0] <= 66 and rgba[1] == 128 and rgba[2] == 128 and rgba[3] == 255);
    assert(rgb16[0] >= 16384 and rgb16[0] <= 16400 and rgb16[1] == 32768 and rgb16[2] == 32768);
    edit.red = [501, 500, 750];
    assert(rgb_gradation.apply_rgba8_in_place(rgba[..], 1, 1, edit,
        no_cancel, 0
    ) == 1);
}

test "editor luma changes grayscale brightness and smooth interpolation bends between points" {
    var edit = rgb_gradation.neutral_five_point_edit();
    edit.luma = [250, 600, 750];
    var gray: [4]u8 = [128, 128, 128, 255];
    assert(rgb_gradation.apply_rgba8_in_place(gray[..], 1, 1, edit,
        no_cancel, 0
    ) == 0);
    assert(gray[0] >= 153 and gray[0] <= 155 and gray[0] == gray[1] and gray[1] == gray[2]);
    edit = rgb_gradation.neutral_five_point_edit();
    edit.red = [250, 750, 750];
    var color: [4]u8 = [96, 96, 96, 255];
    assert(rgb_gradation.apply_rgba8_in_place(color[..], 1, 1, edit,
        no_cancel, 0
    ) == 0);
    assert(color[0] > 128 and color[1] == 96 and color[2] == 96);
}

test "version one editor pixels retain linear interpolation" {
    var edit = rgb_gradation.neutral_five_point_edit();
    edit.version = 1;
    edit.red = [250, 750, 750];
    var color: [4]u8 = [96, 96, 96, 255];
    assert(rgb_gradation.apply_rgba8_in_place(color[..], 1, 1, edit,
        no_cancel, 0
    ) == 0);
    assert(color[0] == 128 and color[1] == 96 and color[2] == 96);
}

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn asset(red_mid: f64): rgb_gradation.Asset {
    const red: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: red_mid
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const green: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const blue: [:]rgb_gradation.Node = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.25
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    return {
        version: rgb_gradation.algorithm_version,
        domain: rgb_gradation.srgb_domain(),
        red: red,
        green: green,
        blue: blue
    };
}

test "independent view RGB curves separate channels and preserve endpoints" {
    const curves = asset(0.75);
    const input: [9]f32 = [0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0];
    var output: [9]f32 = [9.0] ** 9;
    assert(rgb_gradation.apply_image(input[..], 3, 1, &curves, output[..], no_cancel, 0) == 0);
    const expected: [9]f32 = [0.0, 0.0, 0.0, 0.75, 0.5, 0.25, 1.0, 1.0, 1.0];
    assert(output == expected);
}

test "invalid input and cancellation prevent publication" {
    const curves = asset(0.75);
    const input: [3]f32 = [0.5, 1.01, 0.5];
    var output: [3]f32 = [9.0] ** 3;
    assert(rgb_gradation.apply_image(input[..], 1, 1, &curves, output[..], no_cancel, 0) == 3);
    assert(output[0] == 9.0);
    const good: [3]f32 = [0.5, 0.5, 0.5];
    assert(rgb_gradation.apply_image(good[..], 1, 1, &curves, output[..], cancel, 0) == 7);
    assert(output[0] == 9.0);
}

test "same curve kernel accepts two declared RGB encodings with distinct identities" {
    const srgb = asset(0.75);
    var p3 = asset(0.75);
    p3.domain = rgb_gradation.display_p3_domain();
    assert(rgb_gradation.valid(&srgb) and rgb_gradation.valid(&p3));
    const input: [3]f32 = [0.5, 0.5, 0.5];
    var srgb_output: [3]f32 = [9.0] ** 3;
    var p3_output: [3]f32 = [9.0] ** 3;
    assert(rgb_gradation.apply_image(input[..], 1, 1, &srgb,
        srgb_output[..], no_cancel, 0
    ) == 0);
    assert(rgb_gradation.apply_image(input[..], 1, 1, &p3,
        p3_output[..], no_cancel, 0
    ) == 0);
    assert(srgb_output == p3_output);
    var srgb_hash: [32]u8 = [0] ** 32;
    var p3_hash: [32]u8 = [0] ** 32;
    assert(rgb_gradation.digest(&srgb, srgb_hash[0..], no_cancel, 0) == 0);
    assert(rgb_gradation.digest(&p3, p3_hash[0..], no_cancel, 0) == 0);
    assert(srgb_hash != p3_hash);
}
