import .engine.develop.tone_curve;
import .engine.color.output_color;

test "two-node identity curve retains signed RGB and headroom" {
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    assert(tone_curve.valid(&asset));
    const result = tone_curve.apply(asset, -0.2, 0.18, 1.5);
    assert(result.valid and result.status == 0);
    assert(result.red > -0.200001 and result.red < -0.199999);
    assert(result.green > 0.179999 and result.green < 0.180001);
    assert(result.blue > 1.499999 and result.blue < 1.500001);
}

test "bounded curve interpolates and extrapolates analytically" {
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.25,
            output: 0.30
        }, {
            input: 0.75,
            output: 0.70
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 0.5,
        nodes: nodes
    };
    const shadow = tone_curve.apply(asset, 0.125, 0.125, 0.125);
    // First segment maps 0.125 to 0.15; half strength gives 0.1375.
    assert(shadow.valid and shadow.red > 0.137499 and shadow.red < 0.137501);
    const nodes2: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.25,
            output: 0.30
        }, {
            input: 0.75,
            output: 0.70
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const full: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes2
    };
    const signed = tone_curve.apply(full, -0.1, -0.1, -0.1);
    assert(signed.valid and signed.red > -0.120001 and signed.red < -0.119999);
    const nodes3: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.25,
            output: 0.30
        }, {
            input: 0.75,
            output: 0.70
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const high_asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes3
    };
    const headroom = tone_curve.apply(high_asset, 1.1, 1.1, 1.1);
    assert(headroom.valid and headroom.red > 1.119999 and headroom.red < 1.120001);
}

test "curve shifts luminance equally without changing channel differences" {
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.6
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    const result = tone_curve.apply(asset, 0.7, 0.4, 0.2);
    assert(result.valid and result.red - result.green > 0.299999 and result.red - result.green < 0.300001);
    assert(result.green - result.blue > 0.199999 and result.green - result.blue < 0.200001);
}

test "curve rejects malformed assets and nonfinite samples" {
    const duplicate: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.4
        }, {
            input: 0.5,
            output: 0.6
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const bad: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: duplicate
    };
    assert(not tone_curve.valid(&bad));
    const rejected = tone_curve.apply(bad, 0.2, 0.2, 0.2);
    assert(not rejected.valid and rejected.status == 1);
    const steep: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.1,
            output: 0.8
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const steep_asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: steep
    };
    assert(not tone_curve.valid(&steep_asset));
    const identity: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const asset: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: identity
    };
    const infinity = output_color.exposure_gain_native(1024.0);
    const invalid = tone_curve.apply(asset, infinity, 0.2, 0.2);
    assert(not invalid.valid and invalid.status == 2);
}
