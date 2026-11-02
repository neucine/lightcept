import .engine.raw.dng.dng_source;
import .engine.raw.dng.dng_bayer;
import .engine.raw.dng.dng_profile;
import .engine.color.dng.dng_color;
import .engine.render.working_pixel;
import .engine.render.render;

// Qualified v10 pixel kernel. Source inspection and profile validation belong
// to the DNG pipeline adapter; a failure invalidates the output buffer.
pub fn render_prepared(input: *const u8, output: *u8, info: dng_source.DngInfo,
    profile: dng_profile.CameraProfile, width: usize, height: usize,
    exposure_ev: f64, expected_photometric: u32, output_bits: u8,
    cancelled: fn (usize): bool, context: usize
): i32 {
    const count = width * height;
    var pixel: usize = 0;
    while pixel < count {
        if pixel % width == 0 and cancelled(context) {
            return 7;
        }
        const out_row = pixel / width;
        const out_column = pixel % width;
        const top = out_row * info.height / height;
        const bottom = (out_row + 1) * info.height / height;
        const left = out_column * info.width / width;
        const right = (out_column + 1) * info.width / width;
        var sum_red: f64 = 0.0;
        var sum_green: f64 = 0.0;
        var sum_blue: f64 = 0.0;
        var row = top;
        while row < bottom {
            if row > top and (row - top) % 64 == 0 and cancelled(context) {
                return 7;
            }
            var column = left;
            while column < right {
                var red: f64 = 0.0;
                var green: f64 = 0.0;
                var blue: f64 = 0.0;
                if expected_photometric == 34892 {
                    const sample = (row * info.width + column) * 3;
                    red = dng_source.normalized_sample(input, info, sample);
                    green = dng_source.normalized_sample(input, info, sample + 1);
                    blue = dng_source.normalized_sample(input, info, sample + 2);
                } else {
                    const camera = dng_bayer.pixel(input, info, row, column);
                    red = camera.red;
                    green = camera.green;
                    blue = camera.blue;
                }
                const working = dng_color.to_working(profile, red, green, blue);
                sum_red = sum_red + (working.red as f64);
                sum_green = sum_green + (working.green as f64);
                sum_blue = sum_blue + (working.blue as f64);
                column = column + 1;
            }
            row = row + 1;
        }
        const source_count = ((bottom - top) * (right - left)) as f64;
        const encoded = working_pixel.encode_working_pixel((sum_red / source_count) as f64, (sum_green / source_count) as f64, (sum_blue / source_count) as f64, exposure_ev, 1.0, 1.0, 1.0);
        if output_bits == 16 {
            const out_offset = pixel * 3;
            render.write_word(output, out_offset, render.quantize16(encoded.red));
            render.write_word(output, out_offset + 1, render.quantize16(encoded.green));
            render.write_word(output, out_offset + 2, render.quantize16(encoded.blue));
        } else {
            const out_offset = pixel * 4;
            render.write_byte(output, out_offset, render.quantize(encoded.red));
            render.write_byte(output, out_offset + 1, render.quantize(encoded.green));
            render.write_byte(output, out_offset + 2, render.quantize(encoded.blue));
            render.write_byte(output, out_offset + 3, 255);
        }
        pixel = pixel + 1;
    }
    return 0;
}
