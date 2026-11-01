import .engine.develop.exposure;
import .engine.color.output_color;
import .engine.pipeline.pipeline;

test "G2 signed linear exposure preserves retained headroom at minus two zero plus two EV" {
    const values: [8]f64 = [-0.25, 0.0, 0.00000001, 0.18, 0.99, 1.0, 1.25, 4.0];
    const stops: [3]f64 = [-2.0, 0.0, 2.0];
    const expected_gains: [3]f64 = [0.25, 1.0, 4.0];
    var i: usize = 0;
    while i < 3 {
        const composed = pipeline.compose_exposure(0.0, stops[i] as c_double);
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
