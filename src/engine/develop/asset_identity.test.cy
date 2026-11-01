import .engine.develop.asset_identity;
import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;

fn sample_curve(mid: f64): tone_curve.CurveAsset {
    const nodes: [:]tone_curve.CurveNode = [{
            input: 0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: mid
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    return {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
}

test "curve key matches identical node bits" {
    const asset = sample_curve(0.6);
    const key = asset_identity.capture_curve(sample_curve(0.6));
    assert(asset_identity.matches_curve(&key, &asset));
}

test "curve key rejects one-bit node change" {
    const key = asset_identity.capture_curve(sample_curve(0.6));
    const changed = sample_curve(0.6000000000000001);
    assert(tone_curve.valid(&changed));
    assert(not asset_identity.matches_curve(&key, &changed));
}

test "curve key distinguishes negative zero endpoint" {
    const key = asset_identity.capture_curve(sample_curve(0.6));
    const nodes: [:]tone_curve.CurveNode = [{
            input: -0.0,
            output: 0.0
        }, {
            input: 0.5,
            output: 0.6
        }, {
            input: 1.0,
            output: 1.0
        }
    ];
    const changed: tone_curve.CurveAsset = {
        version: 1,
        strength: 1.0,
        nodes: nodes
    };
    assert(tone_curve.valid(&changed));
    assert(not asset_identity.matches_curve(&key, &changed));
}

test "mixer key sees a one-bit coefficient change" {
    var mixer = channel_mixer.neutral_asset();
    mixer.red_from_green = 0.25;
    const key = asset_identity.capture_mixer(mixer);
    assert(key.valid and asset_identity.matches_mixer(key, mixer));
    const bits = asset_identity.float_bits(mixer.red_from_green);
    mixer.red_from_green = (bits + 1) as! f64;
    assert(channel_mixer.valid(mixer) and not asset_identity.matches_mixer(key, mixer));
}
