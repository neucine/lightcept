import .engine.core.camera_rgb;
import .engine.raw.highlight_recovery;

test "green-only clipping uses agreeing neutral ratios" {
    const camera: camera_rgb.CameraRgb = {
        red: 0.49,
        green: 1.0,
        blue: 0.75
    };
    const result = highlight_recovery.reconstruct(camera, [0.372, 1.0, 0.607]);
    assert(result.green > 1.2 and result.green < 1.3);
    assert(result.red == camera.red and result.blue == camera.blue);
}

test "unclipped and strongly chromatic pixels are unchanged" {
    const neutral: [3]f64 = [0.372, 1.0, 0.607];
    const unclipped: camera_rgb.CameraRgb = {
        red: 0.2,
        green: 0.5,
        blue: 0.3
    };
    const unchanged = highlight_recovery.reconstruct(unclipped, neutral);
    assert(unchanged.red == unclipped.red and unchanged.green == unclipped.green and unchanged.blue == unclipped.blue);
    const yellow: camera_rgb.CameraRgb = {
        red: 0.8,
        green: 1.0,
        blue: 0.1
    };
    const preserved = highlight_recovery.reconstruct(yellow, neutral);
    assert(preserved.red == yellow.red and preserved.green == yellow.green and preserved.blue == yellow.blue);
    const two_clipped: camera_rgb.CameraRgb = {
        red: 0.59,
        green: 1.0,
        blue: 1.0
    };
    const unresolved = highlight_recovery.reconstruct(two_clipped, neutral);
    assert(unresolved.red == two_clipped.red and unresolved.green == two_clipped.green and unresolved.blue == two_clipped.blue);
}

test "fully clipped channels use minimum neutral signal" {
    const neutral: [3]f64 = [0.5, 1.0, 0.4];
    const saturated: camera_rgb.CameraRgb = {
        red: 1.0,
        green: 1.0,
        blue: 1.0
    };
    const result = highlight_recovery.reconstruct_with_saturated_neutral(saturated, neutral);
    assert(result.red == 1.25 and result.green == 2.5 and result.blue == 1.0);
    const partial: camera_rgb.CameraRgb = {
        red: 1.0,
        green: 1.0,
        blue: 0.9
    };
    const unchanged = highlight_recovery.reconstruct_with_saturated_neutral(partial, neutral);
    assert(unchanged.red == partial.red and unchanged.green == partial.green and unchanged.blue == partial.blue);
}

test "two clipped channels use neutral floor only with a bright survivor" {
    const neutral: [3]f64 = [0.372, 1.0, 0.607];
    const sky: camera_rgb.CameraRgb = {
        red: 0.59,
        green: 1.0,
        blue: 1.0
    };
    const recovered = highlight_recovery.reconstruct_with_two_channel_neutral(sky, neutral);
    assert(recovered.red > 0.6 and recovered.red < 0.62);
    assert(recovered.green > 1.64 and recovered.green < 1.66);
    assert(recovered.blue == 1.0);
    const yellow: camera_rgb.CameraRgb = {
        red: 1.0,
        green: 1.0,
        blue: 0.1
    };
    const preserved = highlight_recovery.reconstruct_with_two_channel_neutral(yellow, neutral);
    assert(preserved.red == yellow.red and preserved.green == yellow.green and preserved.blue == yellow.blue);
}
