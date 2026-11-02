import .engine.develop.exposure;
import .engine.color.output_color;
import .engine.pipeline.pipeline;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "G2 signed linear exposure preserves retained headroom at minus two zero plus two EV" {
    const values: [8]f64 = [-0.25, 0.0, 0.00000001, 0.18, 0.99, 1.0, 1.25, 4.0];
    const stops: [3]f64 = [-2.0, 0.0, 2.0];
    const expected_gains: [3]f64 = [0.25, 1.0, 4.0];
    var i: usize = 0;
    while i < 3 {
        const composed = pipeline.compose_exposure(0.0, stops[i] as f64);
        const gain = output_color.exposure_gain(composed) as f64;
        var j: usize = 0;
        while j < 8 {
            const actual = exposure.apply(values[j], gain);
            const expected = values[j] * expected_gains[i];
            const difference = actual - expected;
            const magnitude = expected * expected;
            assert(difference * difference <= 0.00000000000001 + magnitude * 0.000000000001);
            // Power-of-two stops are exact here, stronger than the gate bound.
            assert(actual == expected);
            j = j + 1;
        }
        i = i + 1;
    }
}

test "exposure image applies signed EV gain to a representative strip" {
    const input: [9]f32 = [-0.25, 0.0, 0.18,
        0.5, 1.0, 2.0, 4.0, 6.0, 8.0
    ];
    var output: [9]f32 = [99.0] ** 9;
    const asset: exposure.ExposureAsset = {
        version: 1,
        ev: 2.0
    };
    assert(exposure.apply_image(input[0..], 3, 1, asset,
        output[0..], no_cancel, 0
    ) == 0);
    var i: usize = 0;
    while i < 9 {
        const expected = (input[i] as f64) * 4.0;
        const difference = (output[i] as f64) - expected;
        assert(difference > -0.000001 and difference < 0.000001);
        i = i + 1;
    }
    const low: exposure.ExposureAsset = {
        version: 1,
        ev: -16.0
    };
    assert(exposure.apply_image(input[0..], 3, 1, low,
        output[0..], no_cancel, 0
    ) == 0);
    assert((output[0] as f64) > -0.25 / 65536.0 - 0.000000001
        and (output[0] as f64) < -0.25 / 65536.0 + 0.000000001
    );
    const high: exposure.ExposureAsset = {
        version: 1,
        ev: 16.0
    };
    assert(exposure.apply_image(input[0..], 3, 1, high,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == -16384.0 and output[8] == 524288.0);
}

test "exposure image rejects invalid asset input and cancelled work" {
    const input: [3]f32 = [0.18, 0.5, 1.0];
    var output: [3]f32 = [99.0] ** 3;
    var asset: exposure.ExposureAsset = {
        version: 1,
        ev: 0.0
    };
    assert(exposure.apply_image(input[0..], 0, 1, asset,
        output[0..], no_cancel, 0
    ) == 2);
    const bad: [3]f32 = [9.0, 0.5, 1.0];
    assert(exposure.apply_image(bad[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 3);
    assert(exposure.apply_image(input[0..], 1, 1, asset,
        output[0..], cancel, 0
    ) == 7);
    asset.ev = 17.0;
    assert(exposure.apply_image(input[0..], 1, 1, asset,
        output[0..], no_cancel, 0
    ) == 1);
    assert(output[0] == 99.0);
}
