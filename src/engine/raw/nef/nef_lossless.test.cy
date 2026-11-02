import .engine.raw.nef.nef_lossless;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "NEF lossless decoder keeps four predictor streams separate" {
    // Category zero is canonical Huffman code 111110. Eight zero differences
    // pack as six bytes and leave each even/odd row and column predictor alone.
    const stream: [6]u8 = [0xfb, 0xef, 0xbe, 0xfb, 0xef, 0xbe];
    var output: [8]u16 = [0] ** 8;
    assert(nef_lossless.decode(stream[0..].ptr as! *const u8, 6, 4, 2,
        100, 200, 300, 400, output[0..].ptr as! *u16, 8,
        no_cancel, 0
    ) == 0);
    assert(output[0] == 100 and output[1] == 200 and output[2] == 100 and output[3] == 200);
    assert(output[4] == 300 and output[5] == 400 and output[6] == 300 and output[7] == 400);
}

test "NEF lossless decoder applies signed residuals to predictor seeds" {
    // Category one is 1111110 followed by the sign bit. FD encodes +1;
    // FC encodes -1. Each of the four first positions has its own seed.
    const stream: [4]u8 = [0xfd, 0xfc, 0xfd, 0xfc];
    var output: [4]u16 = [0] ** 4;
    assert(nef_lossless.decode(stream[0..].ptr as! *const u8, 4, 2, 2,
        100, 200, 300, 400, output[0..].ptr as! *u16, 4,
        no_cancel, 0
    ) == 0);
    assert(output[0] == 101 and output[1] == 199);
    assert(output[2] == 301 and output[3] == 399);
}

test "NEF lossless decoder rejects invalid buffers and cancellation" {
    const stream: [6]u8 = [0xfb, 0xef, 0xbe, 0xfb, 0xef, 0xbe];
    var output: [8]u16 = [9] ** 8;
    const input = stream[0..].ptr as! *const u8;
    const pixels = output[0..].ptr as! *u16;
    assert(nef_lossless.decode(input, 6, 4, 2, 100, 200, 300, 400, pixels, 8,
        cancel, 0
    ) == 7);
    assert(output[0] == 9 and output[7] == 9);
    assert(nef_lossless.decode(0 as! *const u8, 6, 4, 2, 100, 200, 300, 400, pixels, 8,
        no_cancel, 0
    ) == 4);
    assert(nef_lossless.decode(input, 6, 4, 2, 100, 200, 300, 400, 0 as! *u16, 8,
        no_cancel, 0
    ) == 4);
    assert(nef_lossless.decode(input, 6, 4, 2, 100, 200, 300, 400, pixels, 7,
        no_cancel, 0
    ) == 4);
    assert(output[0] == 9 and output[7] == 9);
}
