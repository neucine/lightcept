import .engine.color.nef.nikon_z8_profile;

fn close(actual: f64, expected: f64): bool {
    const delta = actual - expected;
    return delta > -0.000000000001 and delta < 0.000000000001;
}

test "Z8 camera reference matrix composes white and D50 characterization" {
    if nikon_z8_profile.camera_to_xyz_d50(1.0, 1.0) is neutral {
        assert(close(neutral[0], 0.5512238787769542));
        assert(close(neutral[4], 0.9925788622226075));
        assert(close(neutral[8], 0.9262558173814218));
    } else {
        assert(false);
    }
    if nikon_z8_profile.camera_to_xyz_d50(2.0, 1.5) is shot {
        assert(close(shot[0], 1.1024477575539084));
        assert(close(shot[1], 0.42939963404219933));
        assert(close(shot[2], -0.02464456286710818));
    } else {
        assert(false);
    }
}
