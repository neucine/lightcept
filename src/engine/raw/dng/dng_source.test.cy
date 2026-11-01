import .engine.raw.dng.dng_source;

fn no_cancel(context: *const c_uchar): c_int {
    const ignored = context;
    return 0;
}

fn cancel(context: *const c_uchar): c_int {
    const ignored = context;
    return 1;
}

fn put16(bytes: []u8, at: usize, value: u16): void {
    bytes[at] = (value % 256) as u8;
    bytes[at + 1] = (value / 256) as u8;
}

fn put32(bytes: []u8, at: usize, value: u32): void {
    put16(bytes, at, (value % 65536) as u16);
    put16(bytes, at + 2, (value / 65536) as u16);
}

fn entry(bytes: []u8, index: usize, tag: u16, kind: u16, value: u32): void {
    const at = 66 + index * 12;
    put16(bytes, at, tag);
    put16(bytes, at + 2, kind);
    put32(bytes, at + 4, 1);
    put32(bytes, at + 8, value);
}

test "typed lossless DNG decoder returns unsigned sensor codes and checks bounds" {
    var bytes: [256]u8 = [0] ** 256;
    bytes[0] = 73;
    bytes[1] = 73;
    bytes[2] = 42;
    put32(bytes[0..], 4, 8);
    put16(bytes[0..], 8, 2);
    put16(bytes[0..], 10, 330);
    put16(bytes[0..], 12, 4);
    put32(bytes[0..], 14, 1);
    put32(bytes[0..], 18, 64);
    put16(bytes[0..], 22, 50706);
    bytes[24] = 1;
    put32(bytes[0..], 26, 4);
    put32(bytes[0..], 30, 0x00000201);
    put16(bytes[0..], 64, 9);
    entry(bytes[0..], 0, 254, 4, 0);
    entry(bytes[0..], 1, 256, 4, 2);
    entry(bytes[0..], 2, 257, 4, 2);
    entry(bytes[0..], 3, 258, 3, 8);
    entry(bytes[0..], 4, 259, 3, 7);
    entry(bytes[0..], 5, 262, 3, 32803);
    entry(bytes[0..], 6, 273, 4, 180);
    entry(bytes[0..], 7, 278, 4, 2);
    entry(bytes[0..], 8, 279, 4, 55);
    const jpeg: [:]u8 = [255, 216, 255, 195, 0, 14, 8, 0, 2, 0, 1, 2, 1, 17, 0, 2, 17, 0,
        255, 196, 0, 20, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        255, 218, 0, 10, 2, 1, 0, 2, 0, 1, 0, 0, 0, 255, 217
    ];
    var i: usize = 0;
    while i < jpeg.len() {
        bytes[180 + i] = jpeg[i];
        i = i + 1;
    }
    var samples: [4]u16 = [0] ** 4;
    const source = bytes[0..235];
    assert(dng_source.decode_lossless_bayer(source, samples[0..], 4, no_cancel, 0 as! *const c_uchar) == 0);
    assert(samples[0] == 128 and samples[1] == 128 and samples[2] == 128 and samples[3] == 128);
    assert(dng_source.decode_lossless_bayer(source, samples[0..], 3, no_cancel, 0 as! *const c_uchar) == 3);
    assert(dng_source.decode_lossless_bayer(source, samples[0..3], 4, no_cancel, 0 as! *const c_uchar) == 4);
    assert(dng_source.decode_lossless_bayer(source, samples[0..], 4, cancel, 0 as! *const c_uchar) == 7);
}
