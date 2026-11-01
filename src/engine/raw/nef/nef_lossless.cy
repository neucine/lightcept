import .engine.tiff.tiff;

// Nikon 14-bit lossless NEF sensor-code decoder, algorithm version 1.
// Input is one bounded Huffman strip and four maker-note predictor seeds.
// Output is uncropped, unsigned sensor codes in row-major order. No color,
// black-level, or camera-specific geometry is applied here.
struct Bits {
    input: *const c_uchar;
    length: usize;
    byte_position: usize;
    current: u32;
    remaining: u32;
}

fn next_bit(bits: &Bits): i32 {
    if bits.remaining == 0 {
        if bits.byte_position >= bits.length {
            return -1;
        }
        bits.current = tiff.byte(bits.input, bits.byte_position) as u32;
        bits.byte_position = bits.byte_position + 1;
        bits.remaining = 8;
    }
    bits.remaining = bits.remaining - 1;
    return ((bits.current / ((1 as u32) << bits.remaining)) % 2) as i32;
}

// Canonical lossless-14 table. Categories are the published LightCraft
// clean-room table, also checked against our independently decoded Z8 source.
fn category(bits: &Bits): i32 {
    var code: u32 = 0;
    var length: u32 = 1;
    while length <= 8 {
        const bit = next_bit(bits);
        if bit < 0 {
            return -1;
        }
        code = code * 2 + bit as u32;
        if length == 2 and code == 0 {
            return 7;
        }
        if length == 3 {
            if code == 2 {
                return 6;
            }
            if code == 3 {
                return 8;
            }
            if code == 4 {
                return 5;
            }
            if code == 5 {
                return 9;
            }
        }
        if length == 4 {
            if code == 12 {
                return 4;
            }
            if code == 13 {
                return 10;
            }
        }
        if length == 5 {
            if code == 28 {
                return 3;
            }
            if code == 29 {
                return 11;
            }
        }
        if length == 6 {
            if code == 60 {
                return 12;
            }
            if code == 61 {
                return 2;
            }
            if code == 62 {
                return 0;
            }
        }
        if length == 7 and code == 126 {
            return 1;
        }
        if length == 8 {
            if code == 254 {
                return 13;
            }
            if code == 255 {
                return 14;
            }
        }
        length = length + 1;
    }
    return -1;
}

fn difference(bits: &Bits, size: i32): i32 {
    if size < 0 or size > 14 {
        return -65536;
    }
    if size == 0 {
        return 0;
    }
    var value: i32 = 0;
    var index: i32 = 0;
    while index < size {
        const bit = next_bit(bits);
        if bit < 0 {
            return -65536;
        }
        value = value * 2 + bit;
        index = index + 1;
    }
    if value < ((1 as i32) << ((size - 1) as u32)) {
        return value - (((1 as i32) << (size as u32)) - 1);
    }
    return value;
}

fn put(output: *c_ushort, index: usize, value: u16): void {
    unchecked {
        const address = (output as! usize) + index * 2;
        *(address as! *c_ushort) = value as c_ushort;
    }
}

pub export c("lc_cyna_img_v1_decode_nef_lossless14") fn decode(
    input: *const c_uchar, length: c_size_t,
    width: c_size_t, height: c_size_t,
    seed00: c_uint, seed01: c_uint, seed10: c_uint, seed11: c_uint,
    output: *c_ushort, output_len: c_size_t,
    cancelled: c fn (*const c_uchar): c_int, cancel_context: *const c_uchar
): c_int {
    const w = width as usize;
    const h = height as usize;
    const n = output_len as usize;
    if w == 0 or h == 0 or w > 10000 or h > 10000 or w > 100000000 / h {
        return 3;
    }
    if n != w * h {
        return 4;
    }
    if (input as! usize) == 0 or (output as! usize) == 0 {
        return 4;
    }
    if (length as usize) < n / 4 {
        return 1;
    }
    if seed00 > 16383 or seed01 > 16383 or seed10 > 16383 or seed11 > 16383 {
        return 1;
    }
    var bits: Bits = {
        input: input,
        length: length as usize,
        byte_position: 0,
        current: 0,
        remaining: 0
    };
    var p00 = seed00 as i32;
    var p01 = seed01 as i32;
    var p10 = seed10 as i32;
    var p11 = seed11 as i32;
    var clipped: usize = 0;
    var y: usize = 0;
    while y < h {
        if cancelled(cancel_context) != 0 {
            return 7;
        }
        var left0: i32 = 0;
        var left1: i32 = 0;
        var x: usize = 0;
        while x < w {
            const delta = difference(&bits, category(&bits));
            if delta == -65536 {
                return 1;
            }
            var predicted: i32 = 0;
            if x == 0 {
                if y % 2 == 0 {
                    p00 = p00 + delta;
                    predicted = p00;
                } else {
                    p10 = p10 + delta;
                    predicted = p10;
                }
                left0 = predicted;
            } else if x == 1 {
                if y % 2 == 0 {
                    p01 = p01 + delta;
                    predicted = p01;
                } else {
                    p11 = p11 + delta;
                    predicted = p11;
                }
                left1 = predicted;
            } else if x % 2 == 0 {
                left0 = left0 + delta;
                predicted = left0;
            } else {
                left1 = left1 + delta;
                predicted = left1;
            }
            if predicted < 0 {
                predicted = 0;
                clipped = clipped + 1;
            }
            if predicted > 16383 {
                predicted = 16383;
                clipped = clipped + 1;
            }
            put(output, y * w + x, predicted as u16);
            x = x + 1;
        }
        y = y + 1;
    }
    if clipped > n / 1000 + 16 {
        return 1;
    }
    return 0;
}
