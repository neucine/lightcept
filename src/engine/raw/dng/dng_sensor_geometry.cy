import { never_poll } from .engine.core.cancellation;
import .engine.tiff.tiff;
import .engine.raw.dng.dng_source;

// DNG sensor geometry and level normalization v1. Coordinates are stored-raster
// pixels; the CFA and BlackLevel patterns start at ActiveArea's top-left.

pub struct SensorGeometry {
    pub stored_width: usize;
    pub stored_height: usize;
    pub active_top: usize;
    pub active_left: usize;
    pub active_bottom: usize;
    pub active_right: usize;
    pub crop_top: usize;
    pub crop_left: usize;
    pub crop_width: usize;
    pub crop_height: usize;
    pub pattern: u32;
    pub black: [4]u32;
    pub white: u32;
    pub bits: u32;
    pub status: i32;
}

struct Pair {
    first: usize;
    second: usize;
    valid: bool;
}

fn pair(input: *const u8, length: usize, kind: u16, count: u32, value: u32): Pair {
    var result: Pair = {
        first: 0,
        second: 0,
        valid: false
    };
    if count != 2 {
        return result;
    }
    if kind == 3 {
        result.first = value as usize % 65536;
        result.second = value as usize / 65536;
        result.valid = true;
    } else if kind == 4 and tiff.has_range(length, value as usize, 8) {
        result.first = tiff.u32le(input, value as usize) as usize;
        result.second = tiff.u32le(input, value as usize + 4) as usize;
        result.valid = true;
    }
    return result;
}

fn color(pattern: u32, row: usize, column: usize): u32 {
    const position = (row % 2) * 2 + column % 2;
    if position == 0 {
        return pattern % 256;
    }
    if position == 1 {
        return (pattern / 256) % 256;
    }
    if position == 2 {
        return (pattern / 65536) % 256;
    }
    return pattern / 16777216;
}

fn valid_bayer(pattern: u32): bool {
    const a = color(pattern, 0, 0);
    const b = color(pattern, 0, 1);
    const c = color(pattern, 1, 0);
    const d = color(pattern, 1, 1);
    return (a == 0 and b == 1 and c == 1 and d == 2) or (a == 2 and b == 1 and c == 1 and d == 0) or (a == 1 and b == 0 and c == 2 and d == 1) or (a == 1 and b == 2 and c == 0 and d == 1);
}

pub fn inspect(input: *const u8, length: usize): SensorGeometry {
    var geometry: SensorGeometry = {
        stored_width: 0,
        stored_height: 0,
        active_top: 0,
        active_left: 0,
        active_bottom: 0,
        active_right: 0,
        crop_top: 0,
        crop_left: 0,
        crop_width: 0,
        crop_height: 0,
        pattern: 0,
        black: [0, 0, 0, 0],
        white: 0,
        bits: 0,
        status: 2
    };
    const storage = dng_source.inspect_storage(input, length);
    if storage.status != 0 {
        geometry.status = storage.status;
        return geometry;
    }
    if storage.photometric != 32803 or storage.bits < 8 or storage.bits > 16 {
        return geometry;
    }
    geometry.stored_width = storage.width as usize;
    geometry.stored_height = storage.height as usize;
    geometry.active_bottom = geometry.stored_height;
    geometry.active_right = geometry.stored_width;
    geometry.bits = storage.bits;
    geometry.white = ((1 as u32) << storage.bits) - 1;
    const ifd = storage.ifd_offset;
    const entries = tiff.u16le(input, ifd) as usize;
    var cfa_repeat = false;
    var cfa_seen = false;
    var black_repeat = false;
    var black_count: u32 = 0;
    var crop_origin: Pair = {
        first: 0,
        second: 0,
        valid: false
    };
    var crop_size: Pair = {
        first: 0,
        second: 0,
        valid: false
    };
    var entry: usize = 0;
    while entry < entries {
        const base = ifd + 2 + entry * 12;
        const tag = tiff.u16le(input, base);
        const kind = tiff.u16le(input, base + 2);
        const count = tiff.u32le(input, base + 4);
        const value = tiff.u32le(input, base + 8);
        if tag == 33421 {
            if cfa_repeat or kind != 3 or count != 2 or value != 131074 {
                return geometry;
            }
            cfa_repeat = true;
        }
        if tag == 33422 {
            if cfa_seen or kind != 1 or count != 4 {
                return geometry;
            }
            geometry.pattern = value;
            cfa_seen = true;
        }
        if tag == 50710 and (kind != 1 or count != 3 or value % 16777216 != 131328) {
            return geometry;
        }
        if tag == 50711 and (kind != 3 or count != 1 or value % 65536 != 1) {
            return geometry;
        }
        if tag == 50712 or tag == 50715 or tag == 50716 {
            return geometry;
        }
        if tag == 50713 {
            if black_repeat or kind != 3 or count != 2 or value != 131074 {
                return geometry;
            }
            black_repeat = true;
        }
        if tag == 50714 {
            if black_count != 0 {
                return geometry;
            }
            black_count = count;
            if count == 4 and (kind == 3 or kind == 4) {
                var bytes: usize = 16;
                if kind == 3 {
                    bytes = 8;
                }
                if not tiff.has_range(length, value as usize, bytes) {
                    geometry.status = 1;
                    return geometry;
                }
                var position: usize = 0;
                while position < 4 {
                    if kind == 3 {
                        geometry.black[position] = tiff.u16le(input, value as usize + position * 2) as u32;
                    } else {
                        geometry.black[position] = tiff.u32le(input, value as usize + position * 4);
                    }
                    position = position + 1;
                }
            } else if count == 1 and kind == 3 {
                geometry.black = [value % 65536, value % 65536, value % 65536, value % 65536];
            } else if count == 1 and kind == 4 {
                geometry.black = [value, value, value, value];
            } else {
                return geometry;
            }
        }
        if tag == 50717 {
            if count != 1 {
                return geometry;
            }
            if kind == 3 {
                geometry.white = value % 65536;
            } else if kind == 4 {
                geometry.white = value;
            } else {
                return geometry;
            }
        }
        if tag == 50719 {
            if crop_origin.valid {
                return geometry;
            }
            crop_origin = pair(input, length, kind, count, value);
            if not crop_origin.valid {
                return geometry;
            }
        }
        if tag == 50720 {
            if crop_size.valid {
                return geometry;
            }
            crop_size = pair(input, length, kind, count, value);
            if not crop_size.valid {
                return geometry;
            }
        }
        if tag == 50829 {
            if count != 4 {
                return geometry;
            }
            if kind == 3 and tiff.has_range(length, value as usize, 8) {
                geometry.active_top = tiff.u16le(input, value as usize) as usize;
                geometry.active_left = tiff.u16le(input, value as usize + 2) as usize;
                geometry.active_bottom = tiff.u16le(input, value as usize + 4) as usize;
                geometry.active_right = tiff.u16le(input, value as usize + 6) as usize;
            } else if kind == 4 and tiff.has_range(length, value as usize, 16) {
                geometry.active_top = tiff.u32le(input, value as usize) as usize;
                geometry.active_left = tiff.u32le(input, value as usize + 4) as usize;
                geometry.active_bottom = tiff.u32le(input, value as usize + 8) as usize;
                geometry.active_right = tiff.u32le(input, value as usize + 12) as usize;
            } else {
                return geometry;
            }
        }
        entry = entry + 1;
    }
    if not cfa_repeat or not cfa_seen or not valid_bayer(geometry.pattern) or geometry.active_top >= geometry.active_bottom or geometry.active_left >= geometry.active_right or geometry.active_bottom > geometry.stored_height or geometry.active_right > geometry.stored_width {
        return geometry;
    }
    if black_count == 4 and not black_repeat {
        return geometry;
    }
    if black_count == 1 and black_repeat {
        return geometry;
    }
    if geometry.white == 0 or geometry.white > ((1 as u32) << geometry.bits) - 1 {
        return geometry;
    }
    var index: usize = 0;
    while index < 4 {
        if geometry.black[index] >= geometry.white {
            return geometry;
        }
        index = index + 1;
    }
    const active_width = geometry.active_right - geometry.active_left;
    const active_height = geometry.active_bottom - geometry.active_top;
    if not crop_origin.valid {
        crop_origin = {
            first: 0,
            second: 0,
            valid: true
        };
    }
    if not crop_size.valid {
        crop_size = {
            first: active_width,
            second: active_height,
            valid: true
        };
    }
    if crop_size.first == 0 or crop_size.second == 0 or crop_origin.first >= active_width or crop_origin.second >= active_height or crop_size.first > active_width - crop_origin.first or crop_size.second > active_height - crop_origin.second {
        return geometry;
    }
    geometry.crop_left = geometry.active_left + crop_origin.first;
    geometry.crop_top = geometry.active_top + crop_origin.second;
    geometry.crop_width = crop_size.first;
    geometry.crop_height = crop_size.second;
    geometry.status = 0;
    return geometry;
}

fn write_u32(output: *u32, index: usize, value: u32): void {
    unchecked {
        *((((output as! usize) + index * 4) as! *u32)) = value as u32;
    }
}

pub fn probe(input: *const u8, length: usize, output: *u32, output_len: usize): i32 {
    const geometry = inspect(input, length as usize);
    if geometry.status != 0 {
        return geometry.status;
    }
    if output_len as usize != 16 {
        return 4;
    }
    write_u32(output, 0, geometry.stored_width as u32);
    write_u32(output, 1, geometry.stored_height as u32);
    write_u32(output, 2, geometry.crop_left as u32);
    write_u32(output, 3, geometry.crop_top as u32);
    write_u32(output, 4, geometry.crop_width as u32);
    write_u32(output, 5, geometry.crop_height as u32);
    var position: usize = 0;
    while position < 4 {
        const row = (geometry.crop_top - geometry.active_top + position / 2) % 2;
        const column = (geometry.crop_left - geometry.active_left + position % 2) % 2;
        write_u32(output, 6 + position, color(geometry.pattern, row, column));
        position = position + 1;
    }
    write_u32(output, 10, geometry.white);
    write_u32(output, 11, geometry.bits);
    position = 0;
    while position < 4 {
        write_u32(output, 12 + position, geometry.black[position]);
        position = position + 1;
    }
    return 0;
}

fn raw_sample(samples: *const u16, index: usize): u32 {
    unchecked {
        return *(((samples as! usize) + index * 2) as! *const u16) as u32;
    }
}

fn write_normalized(output: *f32, index: usize, value: f32): void {
    unchecked {
        *(((output as! usize) + index * 4) as! *f32) = value as f32;
    }
}

fn normalize(input: *const u8, length: usize, samples: *const u16, sample_len: usize, output: *f32, output_len: usize, cancelled: fn (usize): bool, context: usize, retain_above_white: bool): i32 {
    const geometry = inspect(input, length as usize);
    if geometry.status != 0 {
        return geometry.status;
    }
    if geometry.stored_height > 33554432 / geometry.stored_width or sample_len as usize != geometry.stored_width * geometry.stored_height {
        return 4;
    }
    if geometry.crop_height > 33554432 / geometry.crop_width or output_len as usize != geometry.crop_width * geometry.crop_height {
        return 4;
    }
    var row: usize = 0;
    while row < geometry.crop_height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < geometry.crop_width {
            const stored_row = geometry.crop_top + row;
            const stored_column = geometry.crop_left + column;
            const black_index = ((stored_row - geometry.active_top) % 2) * 2 + (stored_column - geometry.active_left) % 2;
            const raw = raw_sample(samples, stored_row * geometry.stored_width + stored_column);
            if raw > ((1 as u32) << geometry.bits) - 1 {
                return 1;
            }
            const black = geometry.black[black_index];
            var value = (raw as f32 - black as f32) / (geometry.white - black) as f32;
            if not retain_above_white and value > 1.0 {
                value = 1.0;
            }
            write_normalized(output, row * geometry.crop_width + column, value);
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}

fn normalize_v1(input: *const u8, length: usize, samples: *const u16, sample_len: usize, output: *f32, output_len: usize): i32 {
    return normalize(input, length, samples, sample_len, output, output_len, never_poll, 0, false);
}

pub fn normalize_v2(input: *const u8, length: usize, samples: *const u16, sample_len: usize, output: *f32, output_len: usize, cancelled: fn (usize): bool, context: usize): i32 {
    return normalize(input, length, samples, sample_len, output, output_len, cancelled, context, false);
}

// Diagnostic normalization: preserve finite sensor headroom above declared white.
pub fn normalize_v3(input: *const u8, length: usize, samples: *const u16, sample_len: usize, output: *f32, output_len: usize, cancelled: fn (usize): bool, context: usize): i32 {
    return normalize(input, length, samples, sample_len, output, output_len, cancelled, context, true);
}
