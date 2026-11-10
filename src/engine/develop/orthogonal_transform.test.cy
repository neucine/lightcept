import .engine.develop.orthogonal_transform;

test "changing orientation retains the exact selected source pixels" {
    const turned = orthogonal_transform.remap_rect(selected(1), selected(6),
        6, 4, 1, 1, 3, 2
    );
    assert(turned.status == 0);
    assert(turned.left == 1 and turned.top == 1);
    assert(turned.width == 2 and turned.height == 3);
    const restored = orthogonal_transform.remap_rect(selected(6), selected(1),
        6, 4, turned.left, turned.top, turned.width, turned.height
    );
    assert(restored.status == 0);
    assert(restored.left == 1 and restored.top == 1);
    assert(restored.width == 3 and restored.height == 2);
}

test "Ricoh quarter turn crop maps to horizontal mirror canvas" {
    const mapped = orthogonal_transform.remap_rect(selected(6), selected(2),
        6000, 4000, 1000, 2000, 128, 96
    );
    assert(mapped.status == 0);
    assert(mapped.left == 3904 and mapped.top == 2872);
    assert(mapped.width == 96 and mapped.height == 128);
}

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn selected(code: u32): orthogonal_transform.Transform {
    return {
        version: 1,
        code: code
    };
}

test "quarter turns and mirrors exactly map rectangular working pixels" {
    const input: [18]f64 = [
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0,
        3.0, 3.0, 3.0, 4.0, 4.0, 4.0, 5.0, 5.0, 5.0
    ];
    const expected: [48]f64 = [
        0.0, 1.0, 2.0, 3.0, 4.0, 5.0,
        2.0, 1.0, 0.0, 5.0, 4.0, 3.0,
        5.0, 4.0, 3.0, 2.0, 1.0, 0.0,
        3.0, 4.0, 5.0, 0.0, 1.0, 2.0,
        0.0, 3.0, 1.0, 4.0, 2.0, 5.0,
        3.0, 0.0, 4.0, 1.0, 5.0, 2.0,
        5.0, 2.0, 4.0, 1.0, 3.0, 0.0,
        2.0, 5.0, 1.0, 4.0, 0.0, 3.0
    ];
    var code: u32 = 1;
    while code <= 8 {
        const shape = orthogonal_transform.extent(selected(code), 3, 2);
        assert(shape.status == 0);
        assert((code <= 4 and shape.width == 3 and shape.height == 2)
            or (code >= 5 and shape.width == 2 and shape.height == 3)
        );
        var output: [18]f64 = [99.0] ** 18;
        assert(orthogonal_transform.apply_f64(input[0..], 3, 2,
            selected(code), output[0..], no_cancel, 0
        ) == 0);
        var pixel: usize = 0;
        while pixel < 6 {
            const actual = output[pixel * 3];
            assert(actual == expected[((code - 1) as usize) * 6 + pixel]);
            assert(output[pixel * 3 + 1] == actual and output[pixel * 3 + 2] == actual);
            pixel = pixel + 1;
        }
        const corner = orthogonal_transform.map_source_point(selected(code),
            3, 2, 2.0, 1.0
        );
        assert(corner.inside and corner.x >= 0.0 and corner.y >= 0.0
            and corner.x < shape.width as f64 and corner.y < shape.height as f64
        );
        code = code + 1;
    }
}

test "orthogonal transform validates shape source values and cancellation" {
    const input: [3]f64 = [1.0, 2.0, 3.0];
    var output: [3]f64 = [99.0] ** 3;
    assert(orthogonal_transform.apply_f64(input[0..], 1, 1,
        selected(9), output[0..], no_cancel, 0
    ) == 1);
    assert(orthogonal_transform.apply_f64(input[0..], 2, 1,
        selected(1), output[0..], no_cancel, 0
    ) == 2);
    assert(orthogonal_transform.apply_f64(input[0..], 1, 1,
        selected(1), output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 99.0);
    const outside = orthogonal_transform.map_source_point(selected(1),
        1, 1, 1.0, 0.0
    );
    assert(not outside.inside);
}

test "quarter turn selects exact output region without full transformed scratch" {
    const input: [18]f64 = [
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0,
        3.0, 3.0, 3.0, 4.0, 4.0, 4.0, 5.0, 5.0, 5.0
    ];
    var output: [12]f64 = [99.0] ** 12;
    assert(orthogonal_transform.apply_region_f64(input[0..], 3, 2,
        selected(6), 0, 1, 2, 2, output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == 4.0 and output[3] == 1.0
        and output[6] == 5.0 and output[9] == 2.0
    );
    assert(orthogonal_transform.apply_region_f64(input[0..], 3, 2,
        selected(6), 1, 2, 2, 1, output[0..], no_cancel, 0
    ) == 1);
}

test "inverse rectangles select the exact source pixel in all eight transforms" {
    const input: [18]f64 = [
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0,
        3.0, 3.0, 3.0, 4.0, 4.0, 4.0, 5.0, 5.0, 5.0
    ];
    var code: u32 = 1;
    while code <= 8 {
        const source = orthogonal_transform.inverse_rect(selected(code),
            3, 2, 1, 1, 1, 1
        );
        assert(source.status == 0 and source.width == 1 and source.height == 1);
        var output: [3]f64 = [99.0] ** 3;
        assert(orthogonal_transform.apply_region_f64(input[0..], 3, 2,
            selected(code), 1, 1, 1, 1, output[0..], no_cancel, 0
        ) == 0);
        assert(output[0] == input[(source.top * 3 + source.left) * 3]);
        code = code + 1;
    }
    const bad = orthogonal_transform.inverse_rect(selected(6),
        3, 2, 2, 0, 1, 1
    );
    assert(bad.status == 1);
}
