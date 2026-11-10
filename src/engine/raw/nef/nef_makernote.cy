import .engine.tiff.tiff;

// Nikon 14-bit maker-note metadata v1. Supports the qualified Z8 lossless
// Huffman layout and Z6 II packed layout. Input is the bounded tag 37500
// payload, with offsets inside its embedded little-endian TIFF based at byte
// 10. Crop coordinates and dimensions are stored photosites; black and white
// levels are 14-bit sensor codes. White multipliers are dimensionless.
// Status: 0 success, 1 malformed, 2 unsupported variant, 3 resource limit.
pub const encoding_lossless_huffman: u32 = 1;
pub const encoding_packed_14: u32 = 2;

pub struct NefMakerMetadata {
    pub encoding: u32;
    pub seeds: [4]u32;
    pub crop: [4]u32;
    pub black: [4]u32;
    pub white: u32;
    pub red_gain: f64;
    pub blue_gain: f64;
    pub status: i32;
}

struct Entry {
    kind: u16;
    count: u32;
    value: u32;
}

fn empty(status: i32): NefMakerMetadata {
    return {
        encoding: 0,
        seeds: [0] ** 4,
        crop: [0] ** 4,
        black: [0] ** 4,
        white: 15311,
        red_gain: 1.0,
        blue_gain: 1.0,
        status: status
    };
}

fn find(input: *const u8, offset: usize, tag: u16): ?Entry {
    const count = tiff.u16le(input, offset) as usize;
    var result: ?Entry = none;
    var index: usize = 0;
    while index < count {
        const at = offset + 2 + index * 12;
        if tiff.u16le(input, at) == tag {
            if result is previous {
                const ignored = previous;
                return none;
            }
            result = Entry {
                kind: tiff.u16le(input, at + 2),
                count: tiff.u32le(input, at + 4),
                value: tiff.u32le(input, at + 8)
            };
        }
        index = index + 1;
    }
    return result;
}

fn four_shorts(input: *const u8, length: usize, offset: usize, tag: u16): ?[4]u32 {
    if find(input, offset, tag) is entry {
        if entry.kind != 3 or entry.count != 4 or not tiff.has_range(length, entry.value as usize, 8) {
            return none;
        }
        const at = entry.value as usize;
        const values: [4]u32 = [tiff.u16le(input, at) as u32, tiff.u16le(input, at + 2) as u32,
            tiff.u16le(input, at + 4) as u32, tiff.u16le(input, at + 6) as u32
        ];
        return values;
    }
    return none;
}

pub fn parse(note: []const u8, stored_width: u32, stored_height: u32): NefMakerMetadata {
    if note.len() > 1048576 {
        return empty(3);
    }
    if note.len() < 18 or stored_width == 0 or stored_height == 0 {
        return empty(1);
    }
    if note[0] != 78 or note[1] != 105 or note[2] != 107 or note[3] != 111 or
    note[4] != 110 or note[5] != 0 or note[6] != 2 or note[10] != 73 or
    note[11] != 73 or note[12] != 42 or note[13] != 0 {
        return empty(2);
    }
    const base = 10;
    const length = note.len() - base;
    const input = note[base..].ptr as! *const u8;
    const directory = tiff.u32le(input, 4) as usize;
    if not tiff.has_range(length, directory, 2) {
        return empty(1);
    }
    const count = tiff.u16le(input, directory) as usize;
    if count > 256 or not tiff.has_range(length, directory + 2, count * 12 + 4) {
        return empty(1);
    }
    var result = empty(2);
    if find(input, directory, 0x0096) is table {
        if table.kind != 7 or table.count < 10 or table.count > 65536 or
        not tiff.has_range(length, table.value as usize, table.count as usize) {
            return result;
        }
        const at = table.value as usize;
        if tiff.byte(input, at) != 0x46 {
            return result;
        }
        result.seeds = [tiff.u16le(input, at + 2) as u32, tiff.u16le(input, at + 4) as u32,
            tiff.u16le(input, at + 6) as u32, tiff.u16le(input, at + 8) as u32
        ];
        result.encoding = encoding_lossless_huffman;
    } else {
        if find(input, directory, 0x0093) is compression {
            if compression.kind != 3 or compression.count != 1 or compression.value != 10 {
                return result;
            }
            result.encoding = encoding_packed_14;
        } else {
            return result;
        }
    }
    if four_shorts(input, length, directory, 0x0045) is values {
        result.crop = values;
    } else {
        return empty(2);
    }
    if four_shorts(input, length, directory, 0x003d) is values {
        result.black = values;
    } else {
        return empty(2);
    }
    const crop = result.crop;
    if crop[2] == 0 or crop[3] == 0 or crop[0] > stored_width or crop[1] > stored_height or
    crop[2] > stored_width - crop[0] or crop[3] > stored_height - crop[1] {
        return empty(2);
    }
    var i: usize = 0;
    while i < 4 {
        if result.black[i] >= result.white or result.black[i] != result.black[0] {
            return empty(2);
        }
        if result.encoding == encoding_lossless_huffman and result.seeds[i] > 16383 {
            return empty(2);
        }
        i = i + 1;
    }
    if find(input, directory, 0x000c) is balance {
        if balance.kind != 5 or balance.count != 4 or not tiff.has_range(length, balance.value as usize, 32) {
            return empty(2);
        }
        var gains: [4]f64 = [0.0] ** 4;
        i = 0;
        while i < 4 {
            const at = balance.value as usize + i * 8;
            const numerator = tiff.u32le(input, at);
            const denominator = tiff.u32le(input, at + 4);
            if numerator == 0 or denominator == 0 {
                return empty(1);
            }
            gains[i] = (numerator as f64) / (denominator as f64);
            if gains[i] < 0.125 or gains[i] > 16.0 {
                return empty(2);
            }
            i = i + 1;
        }
        const difference = gains[2] - gains[3];
        if difference < -0.001 or difference > 0.001 {
            return empty(2);
        }
        result.red_gain = gains[0] / gains[2];
        result.blue_gain = gains[1] / gains[2];
    } else {
        return empty(2);
    }
    result.status = 0;
    return result;
}
