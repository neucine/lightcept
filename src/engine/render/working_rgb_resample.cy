import .engine.core.core;

// Integer-area reduction of upright scene-linear Rec.2020/D65 f64 RGB.
// Output pixel (x,y) averages the nonempty source block delimited by
// floor(x*source_width/width) and floor((x+1)*source_width/width), and likewise
// for y. Input is immutable and output is disjoint. Status 2 rejects shape,
// 3 rejects nonfinite input, 7 reports cancellation. Output is invalid after
// any nonzero status. This matches the current camera preview's area partition.
pub const algorithm_version: u32 = 1;

pub fn reduce(input: []const f64, source_width: usize, source_height: usize,
    output: []f64, width: usize, height: usize,
    cancelled: fn (usize): bool, context: usize
): i32 {
    if source_width == 0 or source_height == 0 or
    source_width > 50000000 / source_height or
    width == 0 or height == 0 or width > source_width or height > source_height or
    width > 4194304 / height or
    input.len() != source_width * source_height * 3 or
    output.len() != width * height * 3 {
        return 2;
    }
    var source_row: usize = 0;
    while source_row < source_height {
        if cancelled(context) {
            return 7;
        }
        var source_column: usize = 0;
        while source_column < source_width * 3 {
            if not core.finite_sample64(input[source_row * source_width * 3 + source_column]) {
                return 3;
            }
            source_column = source_column + 1;
        }
        source_row = source_row + 1;
    }
    var row: usize = 0;
    while row < height {
        if cancelled(context) {
            return 7;
        }
        const top = row * source_height / height;
        const bottom = (row + 1) * source_height / height;
        var column: usize = 0;
        while column < width {
            const left = column * source_width / width;
            const right = (column + 1) * source_width / width;
            const count = ((bottom - top) * (right - left)) as f64;
            var channel: usize = 0;
            while channel < 3 {
                var total: f64 = 0.0;
                var y = top;
                while y < bottom {
                    var x = left;
                    while x < right {
                        total = total + input[(y * source_width + x) * 3 + channel];
                        x = x + 1;
                    }
                    y = y + 1;
                }
                output[(row * width + column) * 3 + channel] = total / count;
                channel = channel + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
