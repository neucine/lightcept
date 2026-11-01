import .engine.tiff.tiff;

// Bounded JPEG lossless-Huffman (SOF3) decoder for the currently observed DNG
// strip layout. The accepted stream has 1 or 2 full-resolution components,
// one DC Huffman table, predictor 1, point transform 0, and no restarts.
// Output samples remain raw unsigned sensor values in raster order.

struct Huffman {
    counts: usize;
    symbols: usize;
    valid: bool;
}

struct Bits {
    input: *const c_uchar;
    position: usize;
    end: usize;
    current: u32;
    remaining: u32;
    valid: bool;
}

fn be16(input: *const c_uchar, offset: usize): usize {
    return (tiff.byte(input, offset) as usize) * 256 + (tiff.byte(input, offset + 1) as usize);
}

fn next_bit(bits: &Bits): i32 {
    if not bits.valid {
        return -1;
    }
    if bits.remaining == 0 {
        if bits.position >= bits.end {
            bits.valid = false;
            return -1;
        }
        const value = tiff.byte(bits.input, bits.position) as u32;
        bits.position = bits.position + 1;
        if value == 255 {
            if bits.position >= bits.end or tiff.byte(bits.input, bits.position) != 0 {
                bits.valid = false;
                return -1;
            }
            bits.position = bits.position + 1;
        }
        bits.current = value;
        bits.remaining = 8;
    }
    bits.remaining = bits.remaining - 1;
    return ((bits.current / ((1 as u32) << bits.remaining)) % 2) as i32;
}

fn huffman_symbol(bits: &Bits, table: Huffman): i32 {
    var code: u32 = 0;
    var first: u32 = 0;
    var symbol: usize = 0;
    var size: usize = 1;
    while size <= 16 {
        const bit = next_bit(bits);
        if bit < 0 {
            return -1;
        }
        code = code * 2 + bit as u32;
        const count = tiff.byte(bits.input, table.counts + size - 1) as u32;
        if code >= first and code - first < count {
            return tiff.byte(bits.input, table.symbols + symbol + (code - first) as usize) as i32;
        }
        symbol = symbol + count as usize;
        first = (first + count) * 2;
        size = size + 1;
    }
    return -1;
}

fn difference(bits: &Bits, category: i32): i32 {
    if category < 0 or category > 16 {
        return -65536;
    }
    if category == 0 {
        return 0;
    }
    var value: i32 = 0;
    var bit: i32 = 0;
    while bit < category {
        const next = next_bit(bits);
        if next < 0 {
            return -65536;
        }
        value = value * 2 + next;
        bit = bit + 1;
    }
    const threshold = (1 as i32) << ((category - 1) as u32);
    if value < threshold {
        return value - (((1 as i32) << (category as u32)) - 1);
    }
    return value;
}

fn sample(output: *const c_ushort, index: usize): i32 {
    unchecked {
        const address = (output as! usize) + index * 2;
        return *(address as! *const c_ushort) as i32;
    }
}

fn put_sample(output: *c_ushort, index: usize, value: i32): void {
    unchecked {
        const address = (output as! usize) + index * 2;
        *(address as! *c_ushort) = value as c_ushort;
    }
}

pub fn decode(input: *const c_uchar, length: usize, output: *c_ushort, output_len: usize, expected_width: usize, expected_height: usize, expected_bits: u32, cancelled: c fn (*const c_uchar): c_int, cancel_context: *const c_uchar): c_int {
    if not tiff.has_range(length, 0, 4) or tiff.byte(input, 0) != 255 or tiff.byte(input, 1) != 216 {
        return 1;
    }
    var position: usize = 2;
    var jpeg_width: usize = 0;
    var jpeg_height: usize = 0;
    var precision: u32 = 0;
    var components: usize = 0;
    var first_id: u8 = 0;
    var second_id: u8 = 0;
    var frame_seen = false;
    var table: Huffman = {
        counts: 0,
        symbols: 0,
        valid: false
    };
    var scan = false;
    while not scan {
        if not tiff.has_range(length, position, 4) or tiff.byte(input, position) != 255 {
            return 1;
        }
        const marker = tiff.byte(input, position + 1);
        if marker == 255 or marker == 0 or marker == 216 or marker == 217 {
            return 2;
        }
        const segment = be16(input, position + 2);
        if segment < 2 or not tiff.has_range(length, position + 2, segment) {
            return 1;
        }
        const data = position + 4;
        const data_size = segment - 2;
        if marker == 195 {
            if frame_seen or data_size < 9 {
                return 2;
            }
            precision = tiff.byte(input, data) as u32;
            jpeg_height = be16(input, data + 1);
            jpeg_width = be16(input, data + 3);
            components = tiff.byte(input, data + 5) as usize;
            if (components != 1 and components != 2) or data_size != 6 + components * 3 or precision < 2 or precision > 16 {
                return 2;
            }
            first_id = tiff.byte(input, data + 6);
            if tiff.byte(input, data + 7) != 17 or tiff.byte(input, data + 8) != 0 {
                return 2;
            }
            if components == 2 {
                second_id = tiff.byte(input, data + 9);
                if first_id == second_id or tiff.byte(input, data + 10) != 17 or tiff.byte(input, data + 11) != 0 {
                    return 2;
                }
            }
            frame_seen = true;
        } else if marker == 196 {
            if table.valid or data_size < 17 or tiff.byte(input, data) != 0 {
                return 2;
            }
            var count: usize = 0;
            var available: i32 = 1;
            var index: usize = 0;
            while index < 16 {
                const level_count = tiff.byte(input, data + 1 + index) as usize;
                count = count + level_count;
                available = available * 2 - level_count as i32;
                if available < 0 {
                    return 1;
                }
                index = index + 1;
            }
            if count == 0 or count > 256 or data_size != 17 + count {
                return 2;
            }
            table = {
                counts: data + 1,
                symbols: data + 17,
                valid: true
            };
        } else if marker == 218 {
            if not frame_seen or not table.valid or data_size != 4 + components * 2 or tiff.byte(input, data) as usize != components {
                return 2;
            }
            if tiff.byte(input, data + 1) != first_id or tiff.byte(input, data + 2) != 0 {
                return 2;
            }
            if components == 2 and (tiff.byte(input, data + 3) != second_id or tiff.byte(input, data + 4) != 0) {
                return 2;
            }
            const controls = data + 1 + components * 2;
            if tiff.byte(input, controls) != 1 or tiff.byte(input, controls + 1) != 0 or tiff.byte(input, controls + 2) != 0 {
                return 2;
            }
            scan = true;
        } else if (marker < 224 or marker > 239) and marker != 254 {
            return 2;
        }
        position = position + 2 + segment;
    }
    if precision != expected_bits or jpeg_height != expected_height or jpeg_width == 0 or jpeg_width > expected_width or components > expected_width / jpeg_width or jpeg_width * components != expected_width {
        return 2;
    }
    if expected_height == 0 or expected_width > 33554432 / expected_height or output_len != expected_width * expected_height {
        return 3;
    }
    var bits: Bits = {
        input: input,
        position: position,
        end: length,
        current: 0,
        remaining: 0,
        valid: true
    };
    const maximum = ((1 as i32) << precision) - 1;
    var row: usize = 0;
    while row < jpeg_height {
        if cancelled(cancel_context) != 0 {
            return 7;
        }
        var column: usize = 0;
        while column < jpeg_width {
            var component: usize = 0;
            while component < components {
                const category = huffman_symbol(&bits, table);
                if category == 16 or category > precision as i32 {
                    return 2;
                }
                const delta = difference(&bits, category);
                if delta == -65536 {
                    return 1;
                }
                const index = row * expected_width + column * components + component;
                var predictor = (1 as i32) << (precision - 1);
                if column > 0 {
                    predictor = sample(output, index - components);
                } else if row > 0 {
                    predictor = sample(output, index - expected_width);
                }
                const value = predictor + delta;
                if value < 0 or value > maximum {
                    return 1;
                }
                put_sample(output, index, value);
                component = component + 1;
            }
            column = column + 1;
        }
        row = row + 1;
    }
    if not tiff.has_range(length, bits.position, 2) or bits.position + 2 != length or tiff.byte(input, bits.position) != 255 or tiff.byte(input, bits.position + 1) != 217 {
        return 1;
    }
    return 0;
}
