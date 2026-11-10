import .engine.raw.nef.nef_packed;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

fn put_sample(bytes: []u8, row_base: usize, column: usize, value: u16): void {
    const bit = column * 14;
    const at = row_base + bit / 8;
    const shift = bit % 8;
    var word = (bytes[at] as u32) +
    ((bytes[at + 1] as u32) << 8) +
    ((bytes[at + 2] as u32) << 16);
    word = word & (4294967295 - (((1 as u32) << 14) - 1) * ((1 as u32) << shift));
    word = word | ((value as u32) << shift);
    bytes[at] = (word % 256) as u8;
    bytes[at + 1] = ((word / 256) % 256) as u8;
    bytes[at + 2] = ((word / 65536) % 256) as u8;
}

fn fixture(): [32]u8 {
    var bytes: [32]u8 = [0] ** 32;
    const first: [4]u16 = [1, 2, 3, 4];
    const second: [4]u16 = [16383, 8192, 5461, 2730];
    var column: usize = 0;
    while column < 4 {
        put_sample(bytes[0..], 0, column, first[column]);
        put_sample(bytes[0..], 16, column, second[column]);
        column = column + 1;
    }
    bytes[7] = 255;
    bytes[23] = 255;
    return bytes;
}

test "Nikon packed 14-bit decoder keeps LSB-first samples and row padding" {
    const bytes = fixture();
    var output: [8]u16 = [0] ** 8;
    assert(nef_packed.decode(bytes[0..].ptr as! *const u8, 32, 4, 2,
        output[0..].ptr as! *u16, 8, no_cancel, 0
    ) == 0);
    assert(output[0] == 1 and output[1] == 2 and output[2] == 3 and output[3] == 4);
    assert(output[4] == 16383 and output[5] == 8192 and output[6] == 5461 and output[7] == 2730);
}

test "Nikon packed 14-bit decoder rejects malformed lengths and cancellation" {
    const bytes = fixture();
    var output: [8]u16 = [9] ** 8;
    assert(nef_packed.decode(bytes[0..].ptr as! *const u8, 31, 4, 2,
        output[0..].ptr as! *u16, 8, no_cancel, 0
    ) == 1);
    assert(nef_packed.decode(bytes[0..].ptr as! *const u8, 32, 4, 2,
        output[0..].ptr as! *u16, 7, no_cancel, 0
    ) == 4);
    assert(nef_packed.decode(bytes[0..].ptr as! *const u8, 32, 4, 2,
        output[0..].ptr as! *u16, 8, cancel, 0
    ) == 7);
    assert(output[0] == 9 and output[7] == 9);
}
