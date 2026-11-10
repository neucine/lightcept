import .engine.develop.chroma_map;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}
fn close(left: f32, right: f64): bool {
    const difference = (left as f64) - right;
    return difference > -0.00001 and difference < 0.00001;
}

fn fixture(primaries: u32): chroma_map.ChromaMapAsset {
    const table: [:]chroma_map.Delta = [{
            cb: 0.0,
            cr: 0.0
        }, {
            cb: 0.0,
            cr: 0.0
        }, {
            cb: 0.2,
            cr: 0.0
        }, {
            cb: 0.2,
            cr: 0.0
        }
    ];
    return {
        version: chroma_map.algorithm_version,
        primaries: primaries,
        to_opponent: [0.3333333333333333, 0.3333333333333333,
            0.3333333333333333, 1.0, -1.0, 0.0, 0.0, 1.0, -1.0
        ],
        from_opponent: [1.0, 0.6666666666666666, 0.3333333333333333,
            1.0, -0.3333333333333333, 0.3333333333333333,
            1.0, -0.3333333333333333, -0.6666666666666666
        ],
        cb_origin: -2.0,
        cr_origin: -2.0,
        cb_step: 4.0,
        cr_step: 4.0,
        cb_count: 2,
        cr_count: 2,
        deltas: table,
        neutral_radius: 0.5,
        strength: 1.0
    };
}

test "generic chroma grid preserves neutral and maps saturated and out-of-grid patches" {
    const asset = fixture(chroma_map.REC2020_D65);
    assert(chroma_map.valid(&asset));
    const input: [12]f32 = [
        0.5, 0.5, 0.5, 0.8, 0.2, 0.2,
        1.0, 0.0, 0.0, -0.1, -0.1, -0.1
    ];
    var output: [12]f32 = [9.0] ** 12;
    assert(chroma_map.apply_image(input[..], 2, 2, &asset,
        output[..], no_cancel, 0
    ) == 0);
    assert(close(output[0], 0.5) and close(output[1], 0.5)
        and close(output[2], 0.5)
    );
    assert(close(output[3], 0.8466666666666667)
        and close(output[4], 0.1766666666666667)
        and close(output[5], 0.1766666666666667)
    );
    assert(close(output[6], 1.0444444444444445)
        and close(output[7], -0.0222222222222222)
        and close(output[8], -0.0222222222222222)
    );
    assert(output[9] == -0.1 and output[10] == -0.1 and output[11] == -0.1);
}

test "chroma asset identity includes domain and invalid matrices reject before writes" {
    const rec2020 = fixture(chroma_map.REC2020_D65);
    var srgb = fixture(chroma_map.LINEAR_SRGB_D65);
    var first: [32]u8 = [0] ** 32;
    var second: [32]u8 = [0] ** 32;
    assert(chroma_map.digest(&rec2020, first[0..], no_cancel, 0) == 0);
    assert(chroma_map.digest(&srgb, second[0..], no_cancel, 0) == 0);
    assert(first != second);
    srgb.from_opponent[0] = 2.0;
    const input: [3]f32 = [0.5, 0.5, 0.5];
    var output: [3]f32 = [9.0] ** 3;
    assert(chroma_map.apply_image(input[..], 1, 1, &srgb,
        output[..], no_cancel, 0
    ) == 1 and output[0] == 9.0);
    assert(chroma_map.apply_image(input[..], 1, 1, &rec2020,
        output[..], cancel, 0
    ) == 7 and output[0] == 9.0);
}
