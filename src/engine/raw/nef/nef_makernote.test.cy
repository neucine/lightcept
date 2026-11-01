import .engine.raw.nef.nef_makernote;

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

fn fixture(): [170]u8 {
    var note: [170]u8 = [0] ** 170;
    note[0] = 78;
    note[1] = 105;
    note[2] = 107;
    note[3] = 111;
    note[4] = 110;
    note[6] = 2;
    note[10] = 73;
    note[11] = 73;
    put16(note[0..], 12, 42);
    put32(note[0..], 14, 8);
    put16(note[0..], 18, 4);
    entry(note[0..], 20, 0x0096, 7, 10, 80);
    entry(note[0..], 32, 0x0045, 3, 4, 100);
    entry(note[0..], 44, 0x003d, 3, 4, 108);
    entry(note[0..], 56, 0x000c, 5, 4, 120);
    note[90] = 0x46;
    put16(note[0..], 92, 100);
    put16(note[0..], 94, 200);
    put16(note[0..], 96, 300);
    put16(note[0..], 98, 400);
    put16(note[0..], 110, 1);
    put16(note[0..], 112, 1);
    put16(note[0..], 114, 2);
    put16(note[0..], 116, 2);
    var i: usize = 0;
    while i < 4 {
        put16(note[0..], 118 + i * 2, 64);
        i = i + 1;
    }
    put32(note[0..], 130, 200);
    put32(note[0..], 134, 100);
    put32(note[0..], 138, 150);
    put32(note[0..], 142, 100);
    put32(note[0..], 146, 100);
    put32(note[0..], 150, 100);
    put32(note[0..], 154, 100);
    put32(note[0..], 158, 100);
    return note;
}

test "Z8 maker note supplies decoder and sensor metadata in declared units" {
    const note = fixture();
    const data = nef_makernote.parse(note[0..], 4, 4);
    assert(data.status == 0 and data.white == 15311);
    assert(data.seeds[0] == 100 and data.seeds[3] == 400);
    assert(data.crop[0] == 1 and data.crop[1] == 1 and data.crop[2] == 2 and data.crop[3] == 2);
    assert(data.black[0] == 64 and data.black[3] == 64);
    assert(data.red_gain == 2.0 and data.blue_gain == 1.5);
}

test "Z8 maker note rejects invalid version geometry and rational data" {
    var note = fixture();
    note[90] = 0x45;
    assert(nef_makernote.parse(note[0..], 4, 4).status == 2);
    note = fixture();
    put16(note[0..], 114, 4);
    assert(nef_makernote.parse(note[0..], 4, 4).status == 2);
    note = fixture();
    put32(note[0..], 134, 0);
    assert(nef_makernote.parse(note[0..], 4, 4).status == 1);
    note = fixture();
    put32(note[0..], 56 + 8, 160);
    assert(nef_makernote.parse(note[0..], 4, 4).status == 2);
}
