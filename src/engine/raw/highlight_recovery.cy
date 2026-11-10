import .engine.core.camera_rgb;

// Neutral-ratio highlight reconstruction v1, experimental. Camera samples are
// black-subtracted, white-normalized scene-linear values. A single channel at
// white may be increased only when the other two imply similar scene intensity
// relative to the DNG as-shot neutral. This does not recover the true color of
// a clipped pixel; it makes a conservative neutral estimate for testing.
fn estimate(clipped: f64, first: f64, second: f64, clipped_neutral: f64, first_neutral: f64, second_neutral: f64): f64 {
    if clipped < 0.999 or first >= 0.999 or second >= 0.999 {
        return clipped;
    }
    const first_intensity = first / first_neutral;
    const second_intensity = second / second_neutral;
    var lower = first_intensity;
    var upper = second_intensity;
    if lower > upper {
        lower = second_intensity;
        upper = first_intensity;
    }
    if lower < 0.5 or upper > lower * 1.15 {
        return clipped;
    }
    const estimate_value = (first_intensity + second_intensity) * 0.5 * clipped_neutral;
    if estimate_value <= clipped {
        return clipped;
    }
    if estimate_value > 8.0 {
        return 8.0;
    }
    return estimate_value;
}

pub fn valid_neutral(neutral: [3]f64): bool {
    return neutral[0] >= 0.05 and neutral[0] <= 8.0 and neutral[1] >= 0.05 and neutral[1] <= 8.0 and neutral[2] >= 0.05 and neutral[2] <= 8.0;
}

pub fn reconstruct(camera: camera_rgb.CameraRgb, neutral: [3]f64): camera_rgb.CameraRgb {
    return {
        red: estimate(camera.red, camera.green, camera.blue, neutral[0], neutral[1], neutral[2]),
        green: estimate(camera.green, camera.red, camera.blue, neutral[1], neutral[0], neutral[2]),
        blue: estimate(camera.blue, camera.red, camera.green, neutral[2], neutral[0], neutral[1])
    };
}

// Experimental v2: when all three channels have reached sensor white, no
// chromatic ratio survives. Use the dimmest neutral signal consistent with
// all three channels being clipped. This is a rendering policy, not recovery
// of the original scene color or brightness.
pub fn reconstruct_with_saturated_neutral(camera: camera_rgb.CameraRgb, neutral: [3]f64): camera_rgb.CameraRgb {
    if camera.red >= 0.999 and camera.green >= 0.999 and camera.blue >= 0.999 {
        var intensity = 1.0 / neutral[0];
        if 1.0 / neutral[1] > intensity {
            intensity = 1.0 / neutral[1];
        }
        if 1.0 / neutral[2] > intensity {
            intensity = 1.0 / neutral[2];
        }
        return {
            red: intensity * neutral[0],
            green: intensity * neutral[1],
            blue: intensity * neutral[2]
        };
    }
    return reconstruct(camera, neutral);
}

// Experimental v3: only neutralize two-channel clipping when the surviving
// channel is already close to the minimum neutral signal implied by the two
// clipped channels. A dark survivor may carry real chromatic information.
pub fn reconstruct_with_two_channel_neutral(camera: camera_rgb.CameraRgb, neutral: [3]f64): camera_rgb.CameraRgb {
    if camera.red >= 0.999 and camera.green >= 0.999 and camera.blue >= 0.999 {
        return reconstruct_with_saturated_neutral(camera, neutral);
    }
    var floor: f64 = 0.0;
    var survivor: f64 = 0.0;
    var survivor_neutral: f64 = 1.0;
    var clipped: u32 = 0;
    if camera.red >= 0.999 {
        floor = 1.0 / neutral[0];
        clipped = clipped + 1;
    } else {
        survivor = camera.red;
        survivor_neutral = neutral[0];
    }
    if camera.green >= 0.999 {
        if 1.0 / neutral[1] > floor {
            floor = 1.0 / neutral[1];
        }
        clipped = clipped + 1;
    } else {
        survivor = camera.green;
        survivor_neutral = neutral[1];
    }
    if camera.blue >= 0.999 {
        if 1.0 / neutral[2] > floor {
            floor = 1.0 / neutral[2];
        }
        clipped = clipped + 1;
    } else {
        survivor = camera.blue;
        survivor_neutral = neutral[2];
    }
    if clipped != 2 or survivor < floor * survivor_neutral * 0.85 {
        return reconstruct(camera, neutral);
    }
    var intensity = survivor / survivor_neutral;
    if intensity < floor {
        intensity = floor;
    }
    if intensity > 8.0 {
        intensity = 8.0;
    }
    return {
        red: intensity * neutral[0],
        green: intensity * neutral[1],
        blue: intensity * neutral[2]
    };
}
