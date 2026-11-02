pub const max_camera_pixels: usize = 50000000; // Bounded full-resolution Z8 output.
pub const max_camera_source_pixels: usize = 50000000; // Bounded full-resolution Z8 Bayer input.
// Validated intermediate camera RGB range. A function keeps this compatible
// with the pinned compiler, which does not accept top-level f64 bindings.
pub fn maximum_channel_magnitude(): f64 {
    return 65536.0;
}

// Stable numeric values for camera-stage choices. Validate integers at entry;
// the names do not change the numeric values.
pub enum Demosaic: u32 {
    bilinear = 1,
    malvar_he_cutler = 2,
    hamilton_adams = 3,
}
pub enum Highlight: u32 {
    disabled = 0,
    neutral_ratio = 1,
    saturated_neutral = 2,
    two_channel_neutral = 3,
}
pub enum OutputDepth: u32 {
    rgba8 = 8,
    rgb16 = 16,
}
pub enum Orientation: u32 {
    top_left = 1,
    top_right = 2,
    bottom_right = 3,
    bottom_left = 4,
    left_top = 5,
    right_top = 6,
    right_bottom = 7,
    left_bottom = 8,
}
pub enum CameraStageStatus: i32 {
    ok = 0,
    malformed = 1,
    unsupported = 2,
    limit_exceeded = 3,
    shape_mismatch = 4,
    invalid_parameters = 5,
    unrecognized_format = 6,
    cancelled = 7,
}

pub struct SensorPosition {
    pub row: usize;
    pub column: usize;
}

// Visual crop coordinates -> stored raster coordinates. Caller validates the
// orientation and visual bounds before requesting this mapping.
pub fn sensor_position(row: usize, column: usize, width: usize, height: usize, orientation: u32): SensorPosition {
    if orientation == Orientation.top_right as u32 {
        return {
            row: row,
            column: width - 1 - column
        };
    }
    if orientation == Orientation.bottom_right as u32 {
        return {
            row: height - 1 - row,
            column: width - 1 - column
        };
    }
    if orientation == Orientation.bottom_left as u32 {
        return {
            row: height - 1 - row,
            column: column
        };
    }
    if orientation == Orientation.left_top as u32 {
        return {
            row: column,
            column: row
        };
    }
    if orientation == Orientation.right_top as u32 {
        return {
            row: height - 1 - column,
            column: row
        };
    }
    if orientation == Orientation.right_bottom as u32 {
        return {
            row: height - 1 - column,
            column: width - 1 - row
        };
    }
    if orientation == Orientation.left_bottom as u32 {
        return {
            row: column,
            column: width - 1 - row
        };
    }
    return {
        row: row,
        column: column
    };
}
