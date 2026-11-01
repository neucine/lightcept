import .engine.raw.nef.nef_source;
import .engine.raw.nef.nef_mosaic;
import .engine.pipeline.nef_pipeline;
import .engine.pipeline.nef_tiff16;
import .engine.tiff.tiff;
import std.fs;

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

fn entry(bytes: []u8, at: usize, tag: u16, kind: u16, count: u32, value: u32): void {
    put16(bytes, at, tag);
    put16(bytes, at + 2, kind);
    put32(bytes, at + 4, count);
    put32(bytes, at + 8, value);
}

fn fixture(): [240]u8 {
    var bytes: [240]u8 = [0] ** 240;
    bytes[0] = 73;
    bytes[1] = 73;
    put16(bytes[0..], 2, 42);
    put32(bytes[0..], 4, 8);
    put16(bytes[0..], 8, 3);
    entry(bytes[0..], 10, 272, 2, 10, 64);
    entry(bytes[0..], 22, 274, 3, 1, 6);
    entry(bytes[0..], 34, 330, 4, 1, 80);
    const model: [10]u8 = [78, 73, 75, 79, 78, 32, 90, 32, 56, 0];
    var i: usize = 0;
    while i < 10 {
        bytes[64 + i] = model[i];
        i = i + 1;
    }
    put16(bytes[0..], 80, 11);
    entry(bytes[0..], 82, 256, 4, 1, 4);
    entry(bytes[0..], 94, 257, 4, 1, 2);
    entry(bytes[0..], 106, 258, 3, 1, 14);
    entry(bytes[0..], 118, 259, 3, 1, 34713);
    entry(bytes[0..], 130, 262, 3, 1, 32803);
    entry(bytes[0..], 142, 273, 4, 1, 224);
    entry(bytes[0..], 154, 278, 4, 1, 2);
    entry(bytes[0..], 166, 279, 4, 1, 6);
    entry(bytes[0..], 178, 277, 3, 1, 1);
    entry(bytes[0..], 190, 33421, 3, 2, 131074);
    entry(bytes[0..], 202, 33422, 1, 4, 0x02010100);
    return bytes;
}

fn complete_fixture(): [512]u8 {
    const storage = fixture();
    var bytes: [512]u8 = [0] ** 512;
    var i: usize = 0;
    while i < 240 {
        bytes[i] = storage[i];
        i = i + 1;
    }
    put16(bytes[0..], 8, 4);
    entry(bytes[0..], 46, 34665, 4, 1, 240);
    put16(bytes[0..], 240, 1);
    entry(bytes[0..], 242, 37500, 7, 170, 280);
    const base = 280;
    bytes[base] = 78;
    bytes[base + 1] = 105;
    bytes[base + 2] = 107;
    bytes[base + 3] = 111;
    bytes[base + 4] = 110;
    bytes[base + 6] = 2;
    bytes[base + 10] = 73;
    bytes[base + 11] = 73;
    put16(bytes[0..], base + 12, 42);
    put32(bytes[0..], base + 14, 8);
    put16(bytes[0..], base + 18, 4);
    entry(bytes[0..], base + 20, 0x0096, 7, 10, 80);
    entry(bytes[0..], base + 32, 0x0045, 3, 4, 100);
    entry(bytes[0..], base + 44, 0x003d, 3, 4, 108);
    entry(bytes[0..], base + 56, 0x000c, 5, 4, 120);
    bytes[base + 90] = 0x46;
    put16(bytes[0..], base + 92, 100);
    put16(bytes[0..], base + 94, 200);
    put16(bytes[0..], base + 96, 300);
    put16(bytes[0..], base + 98, 400);
    put16(bytes[0..], base + 110, 1);
    put16(bytes[0..], base + 112, 0);
    put16(bytes[0..], base + 114, 2);
    put16(bytes[0..], base + 116, 2);
    i = 0;
    while i < 4 {
        put16(bytes[0..], base + 118 + i * 2, 64);
        i = i + 1;
    }
    put32(bytes[0..], base + 130, 200);
    put32(bytes[0..], base + 134, 100);
    put32(bytes[0..], base + 138, 150);
    put32(bytes[0..], base + 142, 100);
    put32(bytes[0..], base + 146, 100);
    put32(bytes[0..], base + 150, 100);
    put32(bytes[0..], base + 154, 100);
    put32(bytes[0..], base + 158, 100);
    bytes[224] = 0xfb;
    bytes[225] = 0xef;
    bytes[226] = 0xbe;
    bytes[227] = 0xfb;
    bytes[228] = 0xef;
    bytes[229] = 0xbe;
    return bytes;
}

test "Z8 NEF storage probe identifies bounded single-strip Bayer data" {
    const source = fixture();
    const storage = nef_source.inspect(source[0..].ptr as! *const c_uchar, 240);
    assert(storage.status == 0);
    assert(storage.width == 4 and storage.height == 2 and storage.orientation == 6);
    assert(storage.strip_offset == 224 and storage.strip_bytes == 6 and storage.cfa == 0x02010100);
}

test "Z8 NEF storage probe rejects changed variant and out-of-range strip" {
    var source = fixture();
    put16(source[0..], 118 + 8, 1);
    assert(nef_source.inspect(source[0..].ptr as! *const c_uchar, 240).status == 2);
    source = fixture();
    put32(source[0..], 166 + 8, 40);
    assert(nef_source.inspect(source[0..].ptr as! *const c_uchar, 240).status == 1);
    source = fixture();
    source[64] = 88;
    assert(nef_source.inspect(source[0..].ptr as! *const c_uchar, 240).status == 6);
    assert(nef_source.inspect(0 as! *const c_uchar, 240).status == 1);
}

test "Z8 NEF source inspection binds storage and maker note bounds" {
    var source = complete_fixture();
    const result = nef_source.inspect_source(source[0..]);
    assert(result.status == 0);
    assert(result.storage.width == 4 and result.storage.strip_bytes == 6);
    assert(result.maker.seeds[0] == 100 and result.maker.crop[2] == 2);
    assert(result.maker.red_gain == 2.0 and result.maker.blue_gain == 1.5);
    put32(source[0..], 242 + 8, 500);
    assert(nef_source.inspect_source(source[0..]).status == 1);
}

test "Z8 NEF source decodes and normalizes a bounded synthetic mosaic" {
    const source = complete_fixture();
    var samples: [8]u16 = [0] ** 8;
    var normalized: [4]f32 = [9.0] ** 4;
    const result = nef_mosaic.decode_normalized(source[0..], samples[0..], normalized[0..],
        8, no_cancel, 0 as! *const c_uchar
    );
    assert(result.status == 0 and result.width == 2 and result.height == 2);
    assert(result.orientation == 6 and result.cfa[0] == 1 and result.cfa[1] == 0 and result.cfa[2] == 2 and result.cfa[3] == 1);
    assert(result.camera_to_xyz_d50[0] != 0.0);
    assert(samples[0] == 100 and samples[1] == 200 and samples[4] == 300 and samples[5] == 400);
    assert(normalized[0] == ((200 as f32) - (64 as f32)) / ((15311 as f32) - (64 as f32)));
    assert(normalized[1] == ((100 as f32) - (64 as f32)) / ((15311 as f32) - (64 as f32)));
    assert(normalized[2] == ((400 as f32) - (64 as f32)) / ((15311 as f32) - (64 as f32)));
    assert(normalized[3] == ((300 as f32) - (64 as f32)) / ((15311 as f32) - (64 as f32)));
    var untouched: [4]f32 = [9.0] ** 4;
    assert(nef_mosaic.decode_normalized(source[0..], samples[0..], untouched[0..],
        7, no_cancel, 0 as! *const c_uchar
    ).status == 3);
    assert(nef_mosaic.decode_normalized(source[0..], samples[0..], untouched[0..],
        8, cancel, 0 as! *const c_uchar
    ).status == 7);
    assert(untouched[0] == 9.0 and untouched[3] == 9.0);
}

test "Z8 NEF headless preview uses the checked source and color route" {
    const source = complete_fixture();
    var samples: [8]u16 = [0] ** 8;
    var normalized: [4]f32 = [0.0] ** 4;
    var output: [16]u8 = [0] ** 16;
    assert(nef_pipeline.render(source[0..], samples[0..], normalized[0..],
        output[0..], 2, 2, 0.0, no_cancel, 0 as! *const c_uchar
    ) == 0);
    assert(output[3] == 255 and output[7] == 255 and output[15] == 255);
    assert(nef_pipeline.render(source[0..], samples[0..], normalized[0..],
        output[0..], 2, 2, 0.0, cancel, 0 as! *const c_uchar
    ) == 7);
    assert(nef_pipeline.render(source[0..], samples[0..], normalized[0..],
        output[0..], 3, 2, 0.0, no_cancel, 0 as! *const c_uchar
    ) == 4);
}

test "Z8 NEF RGB16 uses the same scene rendering and bounds" {
    const source = complete_fixture();
    var samples: [8]u16 = [0] ** 8;
    var normalized: [4]f32 = [0.0] ** 4;
    var rgba8: [16]u8 = [0] ** 16;
    var rgb16: [12]u16 = [0] ** 12;
    assert(nef_pipeline.render(source[0..], samples[0..], normalized[0..],
        rgba8[0..], 2, 2, 0.0, no_cancel, 0 as! *const c_uchar
    ) == 0);
    assert(nef_pipeline.render_rgb16(source[0..], samples[0..], normalized[0..],
        rgb16[0..], 0.0, no_cancel, 0 as! *const c_uchar
    ) == 0);
    var pixel: usize = 0;
    while pixel < 4 {
        var channel: usize = 0;
        while channel < 3 {
            const coarse = rgba8[pixel * 4 + channel] as i32;
            const fine = (rgb16[pixel * 3 + channel] / 257) as i32;
            assert(fine >= coarse - 1 and fine <= coarse + 1);
            channel = channel + 1;
        }
        pixel = pixel + 1;
    }
    var untouched: [12]u16 = [9] ** 12;
    assert(nef_pipeline.render_rgb16(source[0..], samples[0..], normalized[0..],
        untouched[0..11], 0.0, no_cancel, 0 as! *const c_uchar
    ) == 4);
    assert(nef_pipeline.render_rgb16(source[0..], samples[0..], normalized[0..],
        untouched[0..], 0.0, cancel, 0 as! *const c_uchar
    ) == 7);
    assert(untouched[0] == 9 and untouched[11] == 9);
}

test "Z8 NEF headless export produces profiled RGB16 TIFF bytes" {
    const source = complete_fixture();
    const icc = fs.read_bytes("src/engine/assets/sRGB2014.icc") catch (error) {
        assert(false);
        return;
    };
    var samples: [8]u16 = [0] ** 8;
    var normalized: [4]f32 = [0.0] ** 4;
    var rgb16: [12]u16 = [0] ** 12;
    var output: [3212]u8 = [9] ** 3212;
    assert(nef_tiff16.render(source[0..], samples[0..], normalized[0..],
        rgb16[0..], icc[..], output[0..], 0.0,
        no_cancel, 0 as! *const c_uchar
    ) == 0);
    const bytes = output[0..].ptr as! *const c_uchar;
    assert(tiff.u16le(bytes, 2) == 42 and tiff.u32le(bytes, 4) == 8);
    assert(tiff.u32le(bytes, 10 + 0 * 12 + 8) == 2);
    assert(tiff.u32le(bytes, 10 + 1 * 12 + 8) == 2);
    assert(tiff.u32le(bytes, 10 + 5 * 12 + 8) == 3188);
    assert(tiff.u32le(bytes, 10 + 9 * 12 + 8) == 24);
    assert(tiff.u16le(bytes, 3188) == rgb16[0]);
    assert(tiff.u16le(bytes, 3210) == rgb16[11]);
    var untouched: [3212]u8 = [9] ** 3212;
    assert(nef_tiff16.render(source[0..], samples[0..], normalized[0..],
        rgb16[0..], icc[..], untouched[0..], 0.0,
        cancel, 0 as! *const c_uchar
    ) == 7);
    assert(untouched[0] == 9 and untouched[3211] == 9);
}
