import .engine.develop.hsl_grading;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn neutral_nodes(): [:]hsl_grading.GradeNode {
    var nodes: [:]hsl_grading.GradeNode = [];
    var index: usize = 0;
    while index < hsl_grading.node_count {
        nodes.push(hsl_grading.neutral_node());
        index = index + 1;
    }
    return nodes;
}

test "eight color bands expand to a valid periodic HSL asset" {
    var bands: [8]hsl_grading.GradeNode = [hsl_grading.neutral_node()] ** 8;
    bands[0] = {
        hue_degrees: 0.0,
        chroma_gain: 1.6,
        luminance_ev: 0.0
    };
    bands[7] = {
        hue_degrees: 0.0,
        chroma_gain: 1.0,
        luminance_ev: 0.6
    };
    const expanded = hsl_grading.eight_band_nodes(bands);
    assert(expanded.valid);
    const asset: hsl_grading.GradeAsset = {
        version: 1,
        nodes: expanded.nodes[..]
    };
    assert(hsl_grading.valid(&asset));
    assert(expanded.nodes[0].chroma_gain == 1.6);
    assert(expanded.nodes[25].chroma_gain > 1.0 and expanded.nodes[25].chroma_gain < 1.6);
    assert(expanded.nodes[11 * 25].luminance_ev > 0.0);
    bands[3] = {
        hue_degrees: 0.0,
        chroma_gain: 2.1,
        luminance_ev: 0.0
    };
    assert(not hsl_grading.eight_band_nodes(bands).valid);
}

test "versioned HSL editor values map signed percentages to bounded nodes" {
    var edit = hsl_grading.neutral_eight_band_edit();
    const neutral = hsl_grading.editor_nodes(edit);
    assert(neutral.valid and neutral.nodes.len() == hsl_grading.node_count);
    assert(neutral.nodes[0].hue_degrees == 0.0);
    assert(neutral.nodes[0].chroma_gain == 1.0);
    assert(neutral.nodes[0].luminance_ev == 0.0);
    edit.hue_percent[0] = 100;
    edit.saturation_percent[0] = -100;
    edit.luminance_percent[0] = 100;
    const changed = hsl_grading.editor_nodes(edit);
    assert(changed.valid);
    assert(changed.nodes[0].hue_degrees == 45.0);
    assert(changed.nodes[0].chroma_gain == 0.0);
    assert(changed.nodes[0].luminance_ev == 1.0);
    edit.version = 2;
    assert(not hsl_grading.editor_nodes(edit).valid);
}

test "HSL LUT has complete fixed dimensions and trilinear periodic hue" {
    var nodes = neutral_nodes();
    var h: usize = 0;
    while h < hsl_grading.hue_steps {
        var s: usize = 0;
        while s < hsl_grading.saturation_steps {
            var l: usize = 0;
            while l < hsl_grading.luminance_steps {
                nodes[(h * 5 + s) * 5 + l] = {
                    hue_degrees: 0.0,
                    chroma_gain: 1.0,
                    luminance_ev: h as f64 / 12.0 + s as f64 / 20.0 + l as f64 / 40.0
                };
                l = l + 1;
            }
            s = s + 1;
        }
        h = h + 1;
    }
    const asset: hsl_grading.GradeAsset = {
        version: 1,
        nodes: nodes[..]
    };
    assert(hsl_grading.valid(&asset));
    const between = hsl_grading.lookup_at(&asset, [15.0, 0.375, 0.625]);
    assert(between.status == 0);
    assert(between.node.luminance_ev > 0.17916 and between.node.luminance_ev < 0.17917);
    const seam = hsl_grading.lookup_at(&asset, [345.0, 0.5, 0.5]);
    assert(seam.status == 0);
    assert(seam.node.luminance_ev > 0.60833 and seam.node.luminance_ev < 0.60834);
    assert(hsl_grading.lookup_at(&asset, [360.0, 0.5, 0.5]).status == 2);
    var short_nodes = neutral_nodes();
    const removed = short_nodes.pop();
    assert(removed.chroma_gain == 1.0);
    const short: hsl_grading.GradeAsset = {
        version: 1,
        nodes: short_nodes[..]
    };
    assert(not hsl_grading.valid(&short));
}

test "HSL LUT grades a representative signed scene strip without output clipping" {
    var nodes = neutral_nodes();
    const neutral: hsl_grading.GradeAsset = {
        version: 1,
        nodes: nodes[..]
    };
    const input: [9]f32 = [0.18, 0.18, 0.18, 0.8, 0.2, 0.1, -0.1, 0.4, 2.0];
    var output: [9]f32 = [9.0] ** 9;
    assert(hsl_grading.apply(input[0..], 3, 1, &neutral, output[0..], no_cancel, 0) == 0);
    var index: usize = 0;
    while index < 9 {
        assert(output[index] >= input[index] - 0.000001 and output[index] <= input[index] + 0.000001);
        index = index + 1;
    }
    var graded_nodes = neutral_nodes();
    index = 0;
    while index < graded_nodes.len() {
        graded_nodes[index] = {
            hue_degrees: 0.0,
            chroma_gain: 1.0,
            luminance_ev: 1.0
        };
        index = index + 1;
    }
    const graded: hsl_grading.GradeAsset = {
        version: 1,
        nodes: graded_nodes[..]
    };
    assert(hsl_grading.apply(input[0..], 3, 1, &graded, output[0..], no_cancel, 0) == 0);
    assert(output[3] > 1.59 and output[3] < 1.61);
    assert(output[6] < -0.19 and output[8] > 3.99);
    assert(hsl_grading.apply(input[0..], 3, 1, &neutral, output[0..], cancel, 0) == 7);
}

test "HSL LUT node hue and chroma operations retain declared luminance" {
    var nodes = neutral_nodes();
    var index: usize = 0;
    while index < nodes.len() {
        nodes[index] = {
            hue_degrees: 90.0,
            chroma_gain: 0.0,
            luminance_ev: 0.0
        };
        index = index + 1;
    }
    const asset: hsl_grading.GradeAsset = {
        version: 1,
        nodes: nodes[..]
    };
    const result = hsl_grading.grade_pixel(0.8, 0.2, 0.1, &asset);
    const input_y = 0.2627 * 0.8 + 0.6780 * 0.2 + 0.0593 * 0.1;
    assert(result[0] > input_y - 0.000001 and result[0] < input_y + 0.000001);
    assert(result[1] > input_y - 0.000001 and result[1] < input_y + 0.000001);
    assert(result[2] > input_y - 0.000001 and result[2] < input_y + 0.000001);
}
