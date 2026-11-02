import .engine.raw.orientation;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn check_orientation(source: []const u16, value: u32,
    expected: []const u16
): bool {
    var output: [6]u16 = [0] ** 6;
    if orientation.apply(source, 3, 2, value,
        output[0..], no_cancel, 0
    ) != 0 {
        return false;
    }
    var index: usize = 0;
    while index < 6 {
        if output[index] != expected[index] {
            return false;
        }
        index = index + 1;
    }
    return true;
}

test "all eight TIFF orientations map a rectangular sensor raster" {
    const source: [6]u16 = [1, 2, 3, 4, 5, 65535];
    const one: [6]u16 = [1, 2, 3, 4, 5, 65535];
    const two: [6]u16 = [3, 2, 1, 65535, 5, 4];
    const three: [6]u16 = [65535, 5, 4, 3, 2, 1];
    const four: [6]u16 = [4, 5, 65535, 1, 2, 3];
    const five: [6]u16 = [1, 4, 2, 5, 3, 65535];
    const six: [6]u16 = [4, 1, 5, 2, 65535, 3];
    const seven: [6]u16 = [65535, 3, 5, 2, 4, 1];
    const eight: [6]u16 = [3, 65535, 2, 5, 1, 4];
    assert(check_orientation(source[0..], 1, one[0..]));
    assert(check_orientation(source[0..], 2, two[0..]));
    assert(check_orientation(source[0..], 3, three[0..]));
    assert(check_orientation(source[0..], 4, four[0..]));
    assert(check_orientation(source[0..], 5, five[0..]));
    assert(check_orientation(source[0..], 6, six[0..]));
    assert(check_orientation(source[0..], 7, seven[0..]));
    assert(check_orientation(source[0..], 8, eight[0..]));
    const rotated = orientation.shape(3, 2, 6);
    assert(rotated.status == 0 and rotated.width == 2
        and rotated.height == 3
    );
}

test "orientation updates Bayer phase in output coordinates" {
    const source: [4]u32 = [0, 1, 1, 2];
    const rotated = orientation.cfa_after(3, 2, 6, source);
    assert(rotated.status == 0);
    assert(rotated.colors[0] == 1 and rotated.colors[1] == 0);
    assert(rotated.colors[2] == 2 and rotated.colors[3] == 1);
    const invalid: [4]u32 = [0, 2, 1, 1];
    assert(orientation.cfa_after(3, 2, 6, invalid).status == 3);
}

test "orientation rejects bad mode shape and cancellation" {
    const input: [4]u16 = [1, 2, 3, 4];
    var output: [4]u16 = [9] ** 4;
    assert(orientation.apply(input[0..], 2, 2, 9,
        output[0..], no_cancel, 0
    ) == 1);
    assert(orientation.apply(input[0..], 3, 2, 1,
        output[0..], no_cancel, 0
    ) == 2);
    assert(orientation.apply(input[0..], 2, 2, 1,
        output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9 and output[3] == 9);
}
