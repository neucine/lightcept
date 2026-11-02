import .engine.tiff.rgb16_writer;
import .engine.tiff.tiff;
import std.fs;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "RGB16 TIFF writes top-left pixels and the pinned output ICC" {
    const icc = fs.read_bytes("src/engine/assets/sRGB2014.icc") catch (error) {
        assert(false);
        return;
    };
    assert(icc.len() == 3024);
    const plan = rgb16_writer.layout(2, 1, icc.len());
    assert(plan.status == 0 and plan.pixel_offset == 3188 and plan.total_bytes == 3200);
    const rgb: [6]u16 = [0, 65535, 32768, 65535, 0, 12345];
    var output: [3200]u8 = [9] ** 3200;
    assert(rgb16_writer.encode(rgb[0..], 2, 1, icc[..], output[0..], no_cancel, 0
    ) == 0);
    const bytes = output[0..].ptr as! *const u8;
    assert(tiff.u16le(bytes, 2) == 42 and tiff.u32le(bytes, 4) == 8);
    assert(tiff.u16le(bytes, 8) == 12 and tiff.u32le(bytes, 154) == 0);
    assert(tiff.u16le(bytes, 10 + 5 * 12) == 273 and tiff.u32le(bytes, 10 + 5 * 12 + 8) == 3188);
    assert(tiff.u16le(bytes, 10 + 6 * 12) == 274 and tiff.u32le(bytes, 10 + 6 * 12 + 8) == 1);
    assert(tiff.u16le(bytes, 10 + 11 * 12) == 34675 and tiff.u32le(bytes, 10 + 11 * 12 + 4) == 3024);
    assert(tiff.u16le(bytes, 10 + 11 * 12 + 2) == 1);
    assert(tiff.u32le(bytes, 10 + 11 * 12 + 8) == 164);
    assert(output[164] == icc[0] and output[164 + 3023] == icc[3023]);
    assert(tiff.u16le(bytes, 3188) == 0 and tiff.u16le(bytes, 3190) == 65535);
    assert(tiff.u16le(bytes, 3192) == 32768 and tiff.u16le(bytes, 3198) == 12345);
}

test "RGB16 TIFF checks limits shape profile and cancellation before writing" {
    var icc: [128]u8 = [0] ** 128;
    icc[36] = 97;
    icc[37] = 99;
    icc[38] = 115;
    icc[39] = 112;
    const rgb: [3]u16 = [10, 20, 30];
    var output: [298]u8 = [9] ** 298;
    assert(rgb16_writer.layout(10000, 10000, 128).status == 3);
    assert(rgb16_writer.encode(rgb[0..], 1, 1, icc[0..], output[0..297], no_cancel, 0
    ) == 4);
    icc[36] = 0;
    assert(rgb16_writer.encode(rgb[0..], 1, 1, icc[0..], output[0..], no_cancel, 0
    ) == 2);
    icc[36] = 97;
    assert(rgb16_writer.encode(rgb[0..], 1, 1, icc[0..], output[0..], cancel, 0
    ) == 7);
    assert(output[0] == 9 and output[297] == 9);
}

test "RGB16 TIFF header and rows assemble the same bytes for padded and aligned ICC" {
    var icc: [129]u8 = [0] ** 129;
    icc[36] = 97;
    icc[37] = 99;
    icc[38] = 115;
    icc[39] = 112;
    const rgb: [12]u16 = [0, 1, 255, 256, 32768, 65535,
        65535, 32768, 256, 255, 1, 0
    ];
    var length: usize = 128;
    while length <= 129 {
        const plan = rgb16_writer.layout(2, 2, length);
        assert(plan.status == 0);
        var complete: [318]u8 = [9] ** 318;
        var streamed: [318]u8 = [9] ** 318;
        assert(rgb16_writer.encode(rgb[0..], 2, 2, icc[0..length],
            complete[0..plan.total_bytes], no_cancel, 0
        ) == 0);
        assert(rgb16_writer.encode_header(2, 2, icc[0..length],
            streamed[0..plan.pixel_offset], no_cancel, 0
        ) == 0);
        var row: usize = 0;
        while row < 2 {
            assert(rgb16_writer.encode_row(rgb[row * 6..(row + 1) * 6], 2,
                streamed[plan.pixel_offset + row * 12..plan.pixel_offset + (row + 1) * 12],
                no_cancel, 0
            ) == 0);
            row = row + 1;
        }
        var index: usize = 0;
        while index < plan.total_bytes {
            assert(complete[index] == streamed[index]);
            index = index + 1;
        }
        length = length + 1;
    }
    var row_output: [12]u8 = [9] ** 12;
    assert(rgb16_writer.encode_row(rgb[0..6], 2, row_output[0..], cancel, 0
    ) == 7);
    assert(row_output[0] == 9 and row_output[11] == 9);
    assert(rgb16_writer.encode_row(rgb[0..6], 2, row_output[0..11], no_cancel, 0
    ) == 4);
}
