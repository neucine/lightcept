import .engine.core.core;
import .engine.develop.perspective;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn identity(): perspective.PerspectiveAsset {
    return {
        version: 1,
        source_corners: [0.0, 0.0, 2.0, 0.0, 2.0, 2.0, 0.0, 2.0],
        boundary_fill: [0.0, 0.0, 0.0]
    };
}

test "perspective identity maps scene pixels and mask coordinates" {
    const input: [27]f32 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5
    ];
    var output: [27]f32 = [9.0] ** 27;
    assert(perspective.apply(input[0..], 3, 3, identity(),
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[0] == input[0] and output[12] == input[12]
        and output[26] == input[26]
    );
    const point = perspective.map_source_point(identity(), 3, 3, 1.0, 1.0);
    assert(point.inside and point.x == 1.0 and point.y == 1.0);
}

test "perspective rectifies a trapezoid with projective sampling" {
    var asset = identity();
    asset.source_corners = [0.0, 0.0, 2.0, 0.0, 1.75, 2.0, 0.25, 2.0];
    const input: [27]f32 = [
        0.0, 0.0, 0.5, 1.0, 0.0, 0.5, 2.0, 0.0, 0.5,
        0.0, 1.0, 0.5, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5,
        0.0, 2.0, 0.5, 1.0, 2.0, 0.5, 2.0, 2.0, 0.5
    ];
    var output: [27]f32 = [9.0] ** 27;
    assert(perspective.apply(input[0..], 3, 3, asset,
        output[0..], no_cancel, 0
    ) == 0);
    assert(output[12] > 0.99 and output[12] < 1.01);
    assert(output[13] > 1.0 and output[13] < 1.2);
    assert(output[18] > 0.24 and output[18] < 0.26);
    const corner = perspective.map_source_point(asset, 3, 3, 0.25, 2.0);
    assert(corner.inside and corner.x > -0.000001 and corner.x < 0.000001);
}

test "perspective rejects invalid quadrilateral shape input and cancellation" {
    const input: [27]f32 = [0.2] ** 27;
    var output: [27]f32 = [9.0] ** 27;
    var bad = identity();
    bad.source_corners = [0.0, 0.0, 2.0, 2.0, 2.0, 0.0, 0.0, 2.0];
    assert(perspective.apply(input[0..], 3, 3, bad,
        output[0..], no_cancel, 0
    ) == 1);
    assert(perspective.apply(input[0..], 3, 3, identity(),
        output[0..3], no_cancel, 0
    ) == 2);
    const infinity = core.positive_infinity32();
    var nonfinite: [27]f32 = [0.2] ** 27;
    nonfinite[0] = infinity;
    assert(perspective.apply(nonfinite[0..], 3, 3, identity(),
        output[0..], no_cancel, 0
    ) == 3);
    assert(perspective.apply(input[0..], 3, 3, identity(),
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9.0 and output[26] == 9.0);
}
