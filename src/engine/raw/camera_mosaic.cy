// Common handoff from a format-specific RAW decoder to a headless render plan.
// The caller-owned image is a cropped, row-major, camera-linear Bayer f32
// mosaic. width/height and CFA use the unrotated cropped sensor coordinates.
// CFA entries are the 2x2 color indices (0 red, 1 green, 2 blue).
// camera_to_xyz_d50 is a row-major 3x3 matrix for camera RGB to XYZ D50;
// neutral is the source's camera-channel neutral. Baseline exposure is in EV.
// Orientation is TIFF 1..8. On a nonzero status all fields and pixel output
// are invalid. The source bytes are immutable and cancellation is forwarded.
pub struct CameraMosaic {
    pub width: usize;
    pub height: usize;
    pub cfa: [4]u32;
    pub camera_to_xyz_d50: [9]f64;
    pub neutral: [3]f64;
    pub baseline_exposure_ev: f64;
    pub orientation: u32;
    pub status: i32;
}

pub fn failed(status: i32): CameraMosaic {
    return {
        width: 0,
        height: 0,
        cfa: [0, 0, 0, 0],
        camera_to_xyz_d50: [0.0] ** 9,
        neutral: [1.0, 1.0, 1.0],
        baseline_exposure_ev: 0.0,
        orientation: 1,
        status: status
    };
}
