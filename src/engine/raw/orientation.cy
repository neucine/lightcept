import .engine.core.camera_contract;

// TIFF visual orientation v1 for immutable row-major u16 sensor codes.
// This component changes raster geometry and preserves exact code values.
pub const algorithm_version: u32 = 1;
pub const maximum_pixels: usize = 16777216;

pub struct OrientedShape {
    pub status: u32;
    pub version: u32;
    pub width: usize;
    pub height: usize;
}

pub struct OrientedCfa {
    pub status: u32;
    pub version: u32;
    // Output 2x2 tile, 0 red, 1 green, 2 blue.
    pub colors: [4]u32;
}

pub fn valid_orientation(value: u32): bool {
    return value >= 1 and value <= 8;
}

pub fn shape(width: usize, height: usize, orientation: u32): OrientedShape {
    if not valid_orientation(orientation) {
        return {
            status: 1,
            version: algorithm_version,
            width: 0,
            height: 0
        };
    }
    if width < 2 or height < 2 or width > maximum_pixels
    or height > maximum_pixels / width {
        return {
            status: 2,
            version: algorithm_version,
            width: 0,
            height: 0
        };
    }
    if orientation >= 5 {
        return {
            status: 0,
            version: algorithm_version,
            width: height,
            height: width
        };
    }
    return {
        status: 0,
        version: algorithm_version,
        width: width,
        height: height
    };
}

fn source_index(row: usize, column: usize, width: usize, height: usize,
    orientation: u32
): usize {
    const position = camera_contract.sensor_position(row, column,
        width, height, orientation
    );
    return position.row * width + position.column;
}

// Source CFA tile is relative to the first stored sensor pixel. The returned
// tile starts at the first oriented output pixel; dimensions must be >=2.
pub fn cfa_after(width: usize, height: usize, orientation: u32,
    source: [4]u32
): OrientedCfa {
    const visual = shape(width, height, orientation);
    if visual.status != 0 {
        return {
            status: visual.status,
            version: algorithm_version,
            colors: [0, 0, 0, 0]
        };
    }
    var counts: [3]u32 = [0, 0, 0];
    var index: usize = 0;
    while index < 4 {
        if source[index] > 2 {
            return {
                status: 3,
                version: algorithm_version,
                colors: [0, 0, 0, 0]
            };
        }
        counts[source[index] as usize] = counts[source[index] as usize] + 1;
        index = index + 1;
    }
    if counts[0] != 1 or counts[1] != 2 or counts[2] != 1
    or not ((source[0] == 1 and source[3] == 1)
        or (source[1] == 1 and source[2] == 1)
    ) {
        return {
            status: 3,
            version: algorithm_version,
            colors: [0, 0, 0, 0]
        };
    }
    var output: [4]u32 = [0, 0, 0, 0];
    var row: usize = 0;
    while row < 2 {
        var column: usize = 0;
        while column < 2 {
            const position = camera_contract.sensor_position(row, column,
                width, height, orientation
            );
            output[row * 2 + column] = source[(position.row % 2) * 2
                + position.column % 2
            ];
            column = column + 1;
        }
        row = row + 1;
    }
    return {
        status: 0,
        version: algorithm_version,
        colors: output
    };
}

// Input and output are disjoint exact-sized u16 buffers. Status 0 success,
// 1 invalid orientation, 2 extent/shape/limit, 7 cancelled. Poll each visual
// row before copying. Any nonzero status invalidates output, including partial
// writes. No sampling halo, rescaling, or pixel-value interpretation.
pub fn apply(input: []const u16, width: usize, height: usize,
    orientation: u32, output: []u16,
    cancelled: fn (usize): bool, context: usize
): u32 {
    const visual = shape(width, height, orientation);
    if visual.status != 0 {
        return visual.status;
    }
    const pixels = width * height;
    if input.len() != pixels or output.len() != pixels {
        return 2;
    }
    var row: usize = 0;
    while row < visual.height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < visual.width {
            output[row * visual.width + column] = input[source_index(row,
                column, width, height, orientation
            )];
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
