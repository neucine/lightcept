import .engine.analysis.region_statistics;
import .engine.color.output_color;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "region statistics measure a photographic patch in source coordinates" {
    // Two rows: dark surround, then neutral shadow, colored midtone, highlight.
    const input: [18]f32 = [0.01, 0.01, 0.01, 0.02, 0.02, 0.02,
        0.03, 0.03, 0.03, 0.18, 0.18, 0.18, 0.6, 0.3, 0.1,
        1.2, 1.2, 1.2
    ];
    const region: region_statistics.Region = {
        left: 1,
        top: 1,
        width: 2,
        height: 1
    };
    const result = region_statistics.measure(input[0..], 3, 2, region, no_cancel, 0);
    assert(result.status == 0 and result.version == 1 and result.pixels == 2);
    assert(result.mean_red > 0.899999 and result.mean_red < 0.900001);
    assert(result.mean_green > 0.749999 and result.mean_green < 0.750001);
    assert(result.mean_blue > 0.649999 and result.mean_blue < 0.650001);
    assert(result.minimum_y > 0.366 and result.minimum_y < 0.368);
    assert(result.maximum_y > 1.199 and result.maximum_y < 1.201);
}

test "region statistics reject bounds samples and cancellation without a partial value" {
    const input: [6]f32 = [0.2, 0.2, 0.2, 0.3, 0.3, 0.3];
    const region: region_statistics.Region = {
        left: 0,
        top: 0,
        width: 2,
        height: 1
    };
    assert(region_statistics.measure(input[0..], 3, 1, region, no_cancel, 0).status == 1);
    const outside: region_statistics.Region = {
        left: 1,
        top: 0,
        width: 2,
        height: 1
    };
    assert(region_statistics.measure(input[0..], 2, 1, outside, no_cancel, 0).status == 2);
    const infinity = output_color.exposure_gain_native(1024.0) as f32;
    const nonfinite: [6]f32 = [0.2, 0.2, 0.2, infinity, 0.3, 0.3];
    const bad = region_statistics.measure(nonfinite[0..], 2, 1, region, no_cancel, 0);
    assert(bad.status == 3 and bad.pixels == 0 and bad.mean_red == 0.0);
    const out_of_domain: [6]f32 = [0.2, 0.2, 0.2, -0.3, 0.3, 0.3];
    assert(region_statistics.measure(out_of_domain[0..], 2, 1,
        region, no_cancel, 0
    ).status == 3);
    const stopped = region_statistics.measure(input[0..], 2, 1, region, cancel, 0);
    assert(stopped.status == 7 and stopped.pixels == 0 and stopped.mean_red == 0.0);
}
