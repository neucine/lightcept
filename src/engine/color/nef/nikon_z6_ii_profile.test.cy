import .engine.color.nef.nikon_z6_ii_profile;

fn close(actual: f64, expected: f64): bool {
    const delta = actual - expected;
    return delta > -0.000000000001 and delta < 0.000000000001;
}

test "Z6 II camera reference matrix composes white and D50 characterization" {
    if nikon_z6_ii_profile.camera_to_xyz_d50(1.0, 1.0) is neutral {
        assert(close(neutral[0], 0.644388671297502));
        assert(close(neutral[4], 0.9638178099159079));
        assert(close(neutral[8], 0.9562984729999999));
    } else {
        assert(false);
    }
    if nikon_z6_ii_profile.camera_to_xyz_d50(2.0, 1.5) is shot {
        assert(close(shot[0], 1.288777342595004));
        assert(close(shot[1], 0.3445381401612482));
        assert(close(shot[2], -0.03709956585534996));
    } else {
        assert(false);
    }
}
