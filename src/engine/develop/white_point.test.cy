import .engine.develop.white_point;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn patch(): white_point.Region {
    return {
        left: 0,
        top: 0,
        width: 2,
        height: 1
    };
}

test "sampled white point maps measured patch to neutral at full confidence" {
    const input: [6]f32 = [0.4, 0.2, 0.2, 0.4, 0.2, 0.2];
    const sampled = white_point.sample_patch(input[0..], 2, 1,
        patch(), 99, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    );
    assert(sampled.status == 0 and sampled.asset.matrix_hash == 99);
    assert(sampled.asset.sample[0] > 0.39 and sampled.asset.sample[0] < 0.41);
    var output: [6]f32 = [9.0] ** 6;
    assert(white_point.apply(input[0..], 2, 1, sampled.asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] > 0.25 and output[0] < 0.27);
    assert(output[1] > 0.25 and output[1] < 0.27);
    assert(output[2] > 0.25 and output[2] < 0.27);
}

test "zero-confidence white point preserves signed scene samples" {
    const reference: [3]f32 = [0.25, 0.5, 0.75];
    const sampled = white_point.sample_patch(reference[0..], 1, 1, {
            left: 0,
            top: 0,
            width: 1,
            height: 1
        },
        11, [0.25, 0.5, 0.75], 0.0, no_cancel, 0
    );
    assert(sampled.status == 0);
    const input: [3]f32 = [-0.2, 0.4, 1.5];
    var output: [3]f32 = [9.0] ** 3;
    assert(white_point.apply(input[0..], 1, 1, sampled.asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[1] == input[1]
        and output[2] == input[2]
    );
}

test "white point samples only the named offset patch" {
    const image: [12]f32 = [
        0.1, 0.1, 0.1, 0.4, 0.2, 0.2,
        0.2, 0.2, 0.2, 0.4, 0.2, 0.2
    ];
    const region: white_point.Region = {
        left: 1,
        top: 0,
        width: 1,
        height: 2
    };
    const sampled = white_point.sample_patch(image[0..], 2, 2,
        region, 27, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    );
    assert(sampled.status == 0 and sampled.asset.region.left == 1);
    assert(sampled.asset.sample[0] > 0.399999
        and sampled.asset.sample[0] < 0.400001
    );
    assert(sampled.asset.sample[1] > 0.199999
        and sampled.asset.sample[1] < 0.200001
    );
    var output: [12]f32 = [9.0] ** 12;
    assert(white_point.apply(image[0..], 2, 2, sampled.asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[3] > 0.25 and output[3] < 0.27);
    assert(output[9] > 0.25 and output[9] < 0.27);
}

test "white point reports invalid region provenance dark reference and cancellation" {
    const dark: [3]f32 = [0.0, 0.0, 0.0];
    const region: white_point.Region = {
        left: 0,
        top: 0,
        width: 1,
        height: 1
    };
    assert(white_point.sample_patch(dark[0..], 2, 1,
        region, 1, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    ).status == 1);
    assert(white_point.sample_patch(dark[0..], 1, 1,
        region, 0, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    ).status == 2);
    assert(white_point.sample_patch(dark[0..], 1, 1,
        region, 1, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    ).status == 4);
    assert(white_point.sample_patch(dark[0..], 1, 1,
        region, 1, [1.0, 1.0, 1.0], 1.0, cancel, 0
    ).status == 7);
    const biased: [3]f32 = [0.02, 1.0, 1.0];
    assert(white_point.sample_patch(biased[0..], 1, 1,
        region, 1, [1.0, 1.0, 1.0], 1.0, no_cancel, 0
    ).status == 5);
}
