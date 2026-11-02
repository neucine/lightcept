import .engine.core.camera_rgb;
import .engine.raw.dng.dng_source;
import .engine.raw.bayer;

// DNG byte-backed Bayer adapter for the qualified legacy render route.
fn interpolate(input: *const u8, info: dng_source.DngInfo, row: usize, column: usize, channel: u32): f64 {
    if dng_source.mosaic_color(info, row, column) == channel {
        return dng_source.mosaic_sample(input, info, row, column);
    }
    var top = row;
    var bottom = row;
    var left = column;
    var right = column;
    if row > 0 {
        top = row - 1;
    }
    if row + 1 < info.height {
        bottom = row + 1;
    }
    if column > 0 {
        left = column - 1;
    }
    if column + 1 < info.width {
        right = column + 1;
    }
    var sum: f64 = 0.0;
    var count: usize = 0;
    var y = top;
    while y <= bottom {
        var x = left;
        while x <= right {
            if dng_source.mosaic_color(info, y, x) == channel {
                sum = sum + dng_source.mosaic_sample(input, info, y, x);
                count = count + 1;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return sum / (count as f64);
}

pub fn pixel(input: *const u8, info: dng_source.DngInfo, row: usize, column: usize): camera_rgb.CameraRgb {
    return {
        red: interpolate(input, info, row, column, 0),
        green: interpolate(input, info, row, column, 1),
        blue: interpolate(input, info, row, column, 2),
    };
}

fn write_sample(output: *f64, index: usize, value: f64): void {
    unchecked {
        const address = (output as! usize) + index * 8;
        *(address as! *f64) = value as f64;
    }
}

fn decode(input: *const u8, length: usize, output: *f64, output_len: usize, max_pixels: usize): i32 {
    const info = dng_source.inspect(input, length as usize, max_pixels as usize);
    if info.status != 0 {
        return info.status;
    }
    if info.photometric != 32803 {
        return 2;
    }
    if output_len as usize != info.width * info.height * 3 {
        return 4;
    }
    var index: usize = 0;
    while index < info.width * info.height {
        const camera = pixel(input, info, index / info.width, index % info.width);
        write_sample(output, index * 3, camera.red);
        write_sample(output, index * 3 + 1, camera.green);
        write_sample(output, index * 3 + 2, camera.blue);
        index = index + 1;
    }
    return 0;
}
