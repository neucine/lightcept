import { never_poll } from .engine.core.cancellation;
import .engine.tiff.tiff;
import .engine.raw.lossless_jpeg;

// Bounded DNG source layout for uncompressed 16-bit LinearRaw RGB or Bayer CFA.
// Pixel interpretation remains in the corresponding raw stage.
// This product includes DNG technology under license by Adobe.
// Status: 0 success, 1 malformed, 2 unsupported variant, 3 resource limit,
// 4 output shape mismatch, 6 not a DNG container.

pub struct DngInfo {
    pub width: usize;
    pub height: usize;
    pub strip_offsets_value: u32;
    pub strip_byte_counts_value: u32;
    pub strip_count: usize;
    pub rows_per_strip: usize;
    pub photometric: u32;
    pub samples_per_pixel: usize;
    pub cfa_pattern: u32;
    pub black_pattern_offset: usize;
    pub black_pattern_kind: u16;
    pub mosaic_white: u32;
    pub black_level_count: u32;
    pub white_level_count: u32;
    pub black_red: u32;
    pub black_green: u32;
    pub black_blue: u32;
    pub white_red: u32;
    pub white_green: u32;
    pub white_blue: u32;
    pub forward_matrix_offset: usize;
    pub neutral_offset: usize;
    pub color_supported: bool;
    pub status: i32;
}

pub struct LevelTriplet {
    pub red: u32;
    pub green: u32;
    pub blue: u32;
    pub valid: bool;
}

// Container-only view of the primary RAW IFD. It deliberately makes no claim
// about decodability or color quality.
pub struct DngStorage {
    pub ifd_offset: usize;
    pub width: u32;
    pub height: u32;
    pub bits: u32;
    pub compression: u32;
    pub photometric: u32;
    pub strip_offset: u32;
    pub strip_bytes: u32;
    pub strip_count: u32;
    pub rows_per_strip: u32;
    pub status: i32;
}

fn storage_ifd(input: *const u8, length: usize, offset: usize): DngStorage {
    var result: DngStorage = {
        ifd_offset: offset,
        width: 0,
        height: 0,
        bits: 0,
        compression: 0,
        photometric: 0,
        strip_offset: 0,
        strip_bytes: 0,
        strip_count: 0,
        rows_per_strip: 0,
        status: 1
    };
    if not tiff.has_range(length, offset, 2) {
        return result;
    }
    const count = tiff.u16le(input, offset) as usize;
    if count > 128 or not tiff.has_range(length, offset + 2, count * 12 + 4) {
        return result;
    }
    var subfile: u32 = 0;
    var entry: usize = 0;
    while entry < count {
        const base = offset + 2 + entry * 12;
        const tag = tiff.u16le(input, base);
        const kind = tiff.u16le(input, base + 2);
        const items = tiff.u32le(input, base + 4);
        const value = tiff.u32le(input, base + 8);
        if tag == 254 and kind == 4 and items == 1 {
            subfile = value;
        }
        if tag == 256 and kind == 4 and items == 1 {
            result.width = value;
        }
        if tag == 257 and kind == 4 and items == 1 {
            result.height = value;
        }
        if tag == 258 and kind == 3 and items == 1 {
            result.bits = value % 65536;
        }
        if tag == 259 and kind == 3 and items == 1 {
            result.compression = value % 65536;
        }
        if tag == 262 and kind == 3 and items == 1 {
            result.photometric = value % 65536;
        }
        if tag == 273 and kind == 4 {
            result.strip_offset = value;
            result.strip_count = items;
        }
        if tag == 278 and kind == 4 and items == 1 {
            result.rows_per_strip = value;
        }
        if tag == 279 and kind == 4 and items == 1 {
            result.strip_bytes = value;
        }
        entry = entry + 1;
    }
    if subfile == 0 and result.width > 0 and result.height > 0 and result.bits > 0 and result.compression > 0 and (result.photometric == 32803 or result.photometric == 34892) {
        result.status = 0;
    } else {
        result.status = 2;
    }
    return result;
}

pub fn inspect_storage(input: *const u8, length: usize): DngStorage {
    var result: DngStorage = {
        ifd_offset: 0,
        width: 0,
        height: 0,
        bits: 0,
        compression: 0,
        photometric: 0,
        strip_offset: 0,
        strip_bytes: 0,
        strip_count: 0,
        rows_per_strip: 0,
        status: 1
    };
    if not tiff.has_range(length, 0, 8) {
        return result;
    }
    if tiff.byte(input, 0) != 73 or tiff.byte(input, 1) != 73 or tiff.u16le(input, 2) != 42 {
        result.status = 6;
        return result;
    }
    const root = tiff.u32le(input, 4) as usize;
    if not tiff.has_range(length, root, 2) {
        return result;
    }
    const count = tiff.u16le(input, root) as usize;
    if count > 128 or not tiff.has_range(length, root + 2, count * 12 + 4) {
        return result;
    }
    var marker = false;
    var subifds: u32 = 0;
    var subifd_count: usize = 0;
    var entry: usize = 0;
    while entry < count {
        const base = root + 2 + entry * 12;
        const tag = tiff.u16le(input, base);
        const kind = tiff.u16le(input, base + 2);
        const items = tiff.u32le(input, base + 4);
        const value = tiff.u32le(input, base + 8);
        if tag == 50706 and kind == 1 and items == 4 and value % 256 == 1 {
            marker = true;
        }
        if tag == 330 and kind == 4 and items > 0 and items <= 8 {
            subifds = value;
            subifd_count = items as usize;
        }
        entry = entry + 1;
    }
    if not marker {
        result.status = 6;
        return result;
    }
    result = storage_ifd(input, length, root);
    if result.status == 0 or result.status == 1 {
        return result;
    }
    if subifd_count == 0 {
        return result;
    }
    if subifd_count > 1 and not tiff.has_range(length, subifds as usize, subifd_count * 4) {
        result.status = 1;
        return result;
    }
    var index: usize = 0;
    while index < subifd_count {
        var child = subifds;
        if subifd_count > 1 {
            child = tiff.u32le(input, subifds as usize + index * 4);
        }
        const candidate = storage_ifd(input, length, child as usize);
        if candidate.status == 0 or candidate.status == 1 {
            return candidate;
        }
        index = index + 1;
    }
    result.status = 2;
    return result;
}

fn probe_dng_storage(input: *const u8, length: usize, width: *u32, height: *u32, bits: *u32, compression: *u32, photometric: *u32): i32 {
    const result = inspect_storage(input, length as usize);
    if result.status == 0 {
        unchecked {
            *width = result.width as u32;
            *height = result.height as u32;
            *bits = result.bits as u32;
            *compression = result.compression as u32;
            *photometric = result.photometric as u32;
        }
    }
    return result.status;
}

// Decode-only path. Sensor geometry, levels, demosaic, and color are separate
// stages and do not become supported merely because this function succeeds.
fn decode_dng_lossless_bayer(input: *const u8, length: usize, output: *u16, output_len: usize, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    const layout = inspect_storage(input, length as usize);
    if layout.status != 0 {
        return layout.status;
    }
    if layout.photometric != 32803 or layout.compression != 7 or layout.bits < 8 or layout.bits > 16 or layout.strip_count != 1 or layout.strip_bytes == 0 or layout.rows_per_strip != layout.height {
        return 2;
    }
    if max_pixels == 0 or layout.height as usize > max_pixels as usize or layout.width as usize > max_pixels as usize / layout.height as usize {
        return 3;
    }
    if output_len as usize != layout.width as usize * layout.height as usize {
        return 4;
    }
    if not tiff.has_range(length as usize, layout.strip_offset as usize, layout.strip_bytes as usize) {
        return 1;
    }
    const strip = ((input as! usize) + layout.strip_offset as usize) as! *const u8;
    return lossless_jpeg.decode(strip, layout.strip_bytes as usize, output, output_len as usize, layout.width as usize, layout.height as usize, layout.bits, cancelled, context);
}

// Decodes one lossless JPEG Bayer strip into caller-owned, row-major unsigned
// sensor codes. No black subtraction, crop, or color transform is applied.
// Status 7 means cancellation; discard output after any nonzero status.
pub fn decode_lossless_bayer(source: []const u8, samples: []u16, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    if source.len() == 0 or samples.len() == 0 {
        return 4;
    }
    return decode_dng_lossless_bayer(source.ptr as! *const u8, source.len() as usize,
        samples.ptr as! *u16, samples.len() as usize, max_pixels as usize,
        cancelled, context
    );
}

fn decode_dng_lossless_bayer_v1(input: *const u8, length: usize, output: *u16, output_len: usize, max_pixels: usize): i32 {
    return decode_dng_lossless_bayer(input, length, output, output_len, max_pixels, never_poll, 0);
}

fn decode_dng_lossless_bayer_v2(input: *const u8, length: usize, output: *u16, output_len: usize, max_pixels: usize, cancelled: fn (usize): bool, context: usize): i32 {
    return decode_dng_lossless_bayer(input, length, output, output_len, max_pixels, cancelled, context);
}

fn level_triplet(input: *const u8, length: usize, kind: u16, count: u32, offset: u32): LevelTriplet {
    var levels: LevelTriplet = {
        red: 0,
        green: 0,
        blue: 0,
        valid: false
    };
    if count != 3 {
        return levels;
    }
    const at = offset as usize;
    if kind == 3 and tiff.has_range(length, at, 6) {
        levels.red = tiff.u16le(input, at) as u32;
        levels.green = tiff.u16le(input, at + 2) as u32;
        levels.blue = tiff.u16le(input, at + 4) as u32;
        levels.valid = true;
    }
    if kind == 4 and tiff.has_range(length, at, 12) {
        levels.red = tiff.u32le(input, at);
        levels.green = tiff.u32le(input, at + 4);
        levels.blue = tiff.u32le(input, at + 8);
        levels.valid = true;
    }
    return levels;
}

fn needs_unimplemented_render_operation(tag: u16): bool {
    // Geometry and image storage outside this renderer's pixel contract.
    if tag == 274 or tag == 330 or tag == 322 or tag == 323 or tag == 324 or tag == 325 or tag == 50718 or tag == 50719 or tag == 50720 {
        return true;
    }
    // Camera calibration, alternate white balance, baseline exposure, and
    // additional illuminants require distinct color stages.
    if tag == 50723 or tag == 50724 or tag == 50727 or tag == 50729 or tag == 50730 or tag == 50778 or tag == 50779 or tag == 50965 {
        return true;
    }
    // Profile appearance operations and DNG opcode lists.
    return tag == 50937 or tag == 50938 or tag == 50939 or tag == 50940 or tag == 50941 or tag == 51008 or tag == 51009 or tag == 51022 or tag == 51041 or tag == 51089;
}

fn pattern_color(pattern: u32, position: usize): u32 {
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

fn valid_bayer_pattern(pattern: u32): bool {
    const a = pattern_color(pattern, 0);
    const b = pattern_color(pattern, 1);
    const c = pattern_color(pattern, 2);
    const d = pattern_color(pattern, 3);
    return (a == 0 and b == 1 and c == 1 and d == 2) or (a == 2 and b == 1 and c == 1 and d == 0) or (a == 1 and b == 0 and c == 2 and d == 1) or (a == 1 and b == 2 and c == 0 and d == 1);
}

pub fn inspect(input: *const u8, length: usize, max_pixels: usize): DngInfo {
    var info: DngInfo = {
        width: 0,
        height: 0,
        strip_offsets_value: 0,
        strip_byte_counts_value: 0,
        strip_count: 0,
        rows_per_strip: 0,
        photometric: 0,
        samples_per_pixel: 0,
        cfa_pattern: 0,
        black_pattern_offset: 0,
        black_pattern_kind: 0,
        mosaic_white: 65535,
        black_level_count: 0,
        white_level_count: 0,
        black_red: 0,
        black_green: 0,
        black_blue: 0,
        white_red: 65535,
        white_green: 65535,
        white_blue: 65535,
        forward_matrix_offset: 0,
        neutral_offset: 0,
        color_supported: true,
        status: 1
    };
    if not tiff.has_range(length, 0, 8) {
        return info;
    }
    if tiff.byte(input, 0) != 73 or tiff.byte(input, 1) != 73 or tiff.u16le(input, 2) != 42 {
        info.status = 6;
        return info;
    }
    const ifd = tiff.u32le(input, 4) as usize;
    if not tiff.has_range(length, ifd, 2) {
        return info;
    }
    const entries = tiff.u16le(input, ifd) as usize;
    if entries > 128 or not tiff.has_range(length, ifd + 2, entries * 12 + 4) {
        return info;
    }
    var bits_ok = false;
    var compression: u32 = 0;
    var channels: u32 = 0;
    var rows: u32 = 4294967295;
    var planar: u32 = 1;
    var dng = false;
    var dng_marker_seen = false;
    var offsets_count: u32 = 0;
    var byte_counts_count: u32 = 0;
    var offsets_seen = false;
    var byte_counts_seen = false;
    var levels_supported = true;
    var black_repeat: u32 = 65537;
    var cfa_repeat: u32 = 0;
    var cfa_repeat_seen = false;
    var cfa_pattern_seen = false;
    var cfa_plane_supported = true;
    var cfa_layout_supported = true;
    var active_area_supported = true;
    var active_area_seen = false;
    var active_area_offset: usize = 0;
    var sample_format_supported = true;
    var extra_samples_present = false;
    var sample_format_count: u32 = 0;
    var previous_tag: u16 = 0;
    var matrix_seen = false;
    var neutral_seen = false;
    var entry: usize = 0;
    while entry < entries {
        const base = ifd + 2 + entry * 12;
        const tag = tiff.u16le(input, base);
        if tag <= previous_tag {
            info.status = 2;
            return info;
        }
        previous_tag = tag;
        const kind = tiff.u16le(input, base + 2);
        const count = tiff.u32le(input, base + 4);
        const raw = tiff.u32le(input, base + 8);
        if tag == 256 and kind == 4 and count == 1 {
            info.width = raw as usize;
        }
        if tag == 257 and kind == 4 and count == 1 {
            info.height = raw as usize;
        }
        if tag == 258 and kind == 3 and count == 3 {
            const at = raw as usize;
            if tiff.has_range(length, at, 6) {
                bits_ok = tiff.u16le(input, at) == 16 and tiff.u16le(input, at + 2) == 16 and tiff.u16le(input, at + 4) == 16;
            }
        }
        if tag == 258 and kind == 3 and count == 1 {
            bits_ok = raw % 65536 == 16;
        }
        if tag == 259 and kind == 3 and count == 1 {
            compression = (raw % 65536);
        }
        if tag == 262 and kind == 3 and count == 1 {
            info.photometric = (raw % 65536);
        }
        if tag == 273 {
            if offsets_seen {
                info.status = 2;
                return info;
            }
            offsets_seen = true;
            if kind == 4 {
                info.strip_offsets_value = raw;
                offsets_count = count;
            }
        }
        if tag == 277 and kind == 3 and count == 1 {
            channels = (raw % 65536);
        }
        if tag == 278 and kind == 4 and count == 1 {
            rows = raw;
        }
        if tag == 279 {
            if byte_counts_seen {
                info.status = 2;
                return info;
            }
            byte_counts_seen = true;
            if kind == 4 {
                info.strip_byte_counts_value = raw;
                byte_counts_count = count;
            }
        }
        if tag == 284 and kind == 3 and count == 1 {
            planar = (raw % 65536);
        }
        if tag == 338 {
            extra_samples_present = true;
        }
        if tag == 339 {
            sample_format_count = count;
            if kind == 3 and count == 1 {
                sample_format_supported = raw % 65536 == 1;
            } else if kind == 3 and count == 3 and tiff.has_range(length, raw as usize, 6) {
                sample_format_supported = tiff.u16le(input, raw as usize) == 1 and tiff.u16le(input, raw as usize + 2) == 1 and tiff.u16le(input, raw as usize + 4) == 1;
            } else {
                sample_format_supported = false;
            }
        }
        if tag == 50706 {
            dng_marker_seen = true;
            if kind == 1 and count == 4 {
                dng = raw % 256 == 1;
            }
        }
        if tag == 50712 or tag == 50715 or tag == 50716 {
            levels_supported = false;
        }
        if tag == 50713 {
            if kind != 3 or count != 2 {
                levels_supported = false;
            } else {
                black_repeat = raw;
            }
        }
        if tag == 50714 {
            info.black_level_count = count;
            if count == 3 {
                const levels = level_triplet(input, length, kind, count, raw);
                if not levels.valid {
                    levels_supported = false;
                }
                info.black_red = levels.red;
                info.black_green = levels.green;
                info.black_blue = levels.blue;
            } else if count == 4 and (kind == 3 or kind == 4) {
                var bytes: usize = 16;
                if kind == 3 {
                    bytes = 8;
                }
                if not tiff.has_range(length, raw as usize, bytes) {
                    levels_supported = false;
                } else {
                    info.black_pattern_offset = raw as usize;
                    info.black_pattern_kind = kind;
                }
            } else if count == 1 and kind == 3 {
                info.black_red = raw % 65536;
            } else if count == 1 and kind == 4 {
                info.black_red = raw;
            } else {
                levels_supported = false;
            }
        }
        if tag == 50717 {
            info.white_level_count = count;
            if count == 3 {
                const levels = level_triplet(input, length, kind, count, raw);
                if not levels.valid {
                    levels_supported = false;
                }
                info.white_red = levels.red;
                info.white_green = levels.green;
                info.white_blue = levels.blue;
            } else if count == 1 and kind == 3 {
                info.mosaic_white = raw % 65536;
            } else if count == 1 and kind == 4 {
                info.mosaic_white = raw;
            } else {
                levels_supported = false;
            }
        }
        if tag == 33421 {
            if cfa_repeat_seen {
                cfa_plane_supported = false;
            }
            cfa_repeat_seen = true;
            if kind == 3 and count == 2 {
                cfa_repeat = raw;
            } else {
                cfa_plane_supported = false;
            }
        }
        if tag == 33422 {
            if kind == 1 and count == 4 and not cfa_pattern_seen {
                info.cfa_pattern = raw;
                cfa_pattern_seen = true;
            } else {
                cfa_plane_supported = false;
            }
        }
        if tag == 50710 {
            if kind != 1 or count != 3 or raw % 16777216 != 131328 {
                cfa_plane_supported = false;
            }
        }
        if tag == 50711 and (kind != 3 or count != 1 or raw % 65536 != 1) {
            cfa_layout_supported = false;
        }
        if tag == 50829 {
            if active_area_seen {
                active_area_supported = false;
            }
            active_area_seen = true;
            if kind != 4 or count != 4 or not tiff.has_range(length, raw as usize, 16) {
                active_area_supported = false;
            } else {
                active_area_offset = raw as usize;
            }
        }
        // The first render variant uses only a single embedded forward matrix
        // and AsShotNeutral. Other calibration/profile operations need their
        // own explicit implementation before this variant may accept them.
        if needs_unimplemented_render_operation(tag) {
            info.color_supported = false;
        }
        if tag == 50728 {
            if neutral_seen {
                info.color_supported = false;
            }
            neutral_seen = true;
            if kind == 5 and count == 3 and tiff.has_range(length, raw as usize, 24) {
                info.neutral_offset = raw as usize;
            } else {
                info.color_supported = false;
            }
        }
        if tag == 50964 {
            if matrix_seen {
                info.color_supported = false;
            }
            matrix_seen = true;
            if kind == 10 and count == 9 and tiff.has_range(length, raw as usize, 72) {
                info.forward_matrix_offset = raw as usize;
            } else {
                info.color_supported = false;
            }
        }
        entry = entry + 1;
    }
    if not dng_marker_seen {
        info.status = 6;
        return info;
    }
    if not dng {
        info.status = 2;
        return info;
    }
    if info.width == 0 or info.height == 0 {
        return info;
    }
    if active_area_seen and active_area_supported {
        active_area_supported = tiff.u32le(input, active_area_offset) == 0 and tiff.u32le(input, active_area_offset + 4) == 0 and tiff.u32le(input, active_area_offset + 8) as usize == info.height and tiff.u32le(input, active_area_offset + 12) as usize == info.width;
    }
    if max_pixels == 0 or info.height > max_pixels or info.width > max_pixels / info.height or info.width > 16777216 / info.height {
        info.status = 3;
        return info;
    }
    if not dng or not bits_ok or compression != 1 or rows == 0 or planar != 1 or not levels_supported or not cfa_plane_supported or not cfa_layout_supported or not active_area_supported or not sample_format_supported or extra_samples_present {
        info.status = 2;
        return info;
    }
    if info.photometric == 34892 and channels == 3 {
        if black_repeat != 65537 or info.black_pattern_kind != 0 or (sample_format_count != 0 and sample_format_count != 3) or (info.black_level_count != 0 and info.black_level_count != 3) or (info.white_level_count != 0 and info.white_level_count != 3) or info.white_red > 65535 or info.white_green > 65535 or info.white_blue > 65535 or info.black_red >= info.white_red or info.black_green >= info.white_green or info.black_blue >= info.white_blue {
            info.status = 2;
            return info;
        }
        info.samples_per_pixel = 3;
    } else if info.photometric == 32803 and channels == 1 {
        if cfa_repeat != 131074 or not cfa_pattern_seen or not valid_bayer_pattern(info.cfa_pattern) or info.width < 2 or info.height < 2 or (sample_format_count != 0 and sample_format_count != 1) or (info.black_level_count != 0 and info.black_level_count != 1 and info.black_level_count != 4) or (info.white_level_count != 0 and info.white_level_count != 1) or info.mosaic_white > 65535 or info.mosaic_white == 0 {
            info.status = 2;
            return info;
        }
        if black_repeat == 65537 and info.black_pattern_kind == 0 {
            if info.black_red >= info.mosaic_white {
                info.status = 2;
                return info;
            }
        } else if black_repeat != 131074 or info.black_pattern_kind == 0 {
            info.status = 2;
            return info;
        }
        if info.black_pattern_kind != 0 {
            var position: usize = 0;
            while position < 4 {
                var black: u32 = 0;
                if info.black_pattern_kind == 3 {
                    black = tiff.u16le(input, info.black_pattern_offset + position * 2) as u32;
                } else {
                    black = tiff.u32le(input, info.black_pattern_offset + position * 4);
                }
                if black >= info.mosaic_white {
                    info.status = 2;
                    return info;
                }
                position = position + 1;
            }
        }
        info.samples_per_pixel = 1;
    } else {
        info.status = 2;
        return info;
    }
    const rows_per_strip = rows as usize;
    const count = 1 + (info.height - 1) / rows_per_strip;
    if count > 4096 {
        info.status = 3;
        return info;
    }
    if offsets_count as usize != count or byte_counts_count as usize != count {
        info.status = 2;
        return info;
    }
    if count > 1 and (not tiff.has_range(length, info.strip_offsets_value as usize, count * 4) or not tiff.has_range(length, info.strip_byte_counts_value as usize, count * 4)) {
        return info;
    }
    info.strip_count = count;
    info.rows_per_strip = rows_per_strip;
    var strip: usize = 0;
    while strip < count {
        const offset = strip_value(input, info.strip_offsets_value, count, strip) as usize;
        const bytes = strip_value(input, info.strip_byte_counts_value, count, strip) as usize;
        var strip_rows = rows_per_strip;
        const remaining = info.height - strip * rows_per_strip;
        if remaining < strip_rows {
            strip_rows = remaining;
        }
        const required = info.width * strip_rows * info.samples_per_pixel * 2;
        if bytes != required or not tiff.has_range(length, offset, required) {
            return info;
        }
        strip = strip + 1;
    }
    info.status = 0;
    return info;
}

fn strip_value(input: *const u8, value: u32, count: usize, index: usize): u32 {
    if count == 1 {
        return value;
    }
    return tiff.u32le(input, (value as usize) + index * 4);
}

pub fn sample_offset(input: *const u8, info: DngInfo, index: usize): usize {
    const pixel = index / info.samples_per_pixel;
    const row = pixel / info.width;
    const column = pixel % info.width;
    const strip = row / info.rows_per_strip;
    const local_row = row % info.rows_per_strip;
    const offset = strip_value(input, info.strip_offsets_value, info.strip_count, strip) as usize;
    return offset + (local_row * info.width + column) * info.samples_per_pixel * 2 + (index % info.samples_per_pixel) * 2;
}

pub fn mosaic_color(info: DngInfo, row: usize, column: usize): u32 {
    return pattern_color(info.cfa_pattern, (row % 2) * 2 + column % 2);
}

pub fn mosaic_sample(input: *const u8, info: DngInfo, row: usize, column: usize): f64 {
    const index = row * info.width + column;
    const raw = tiff.u16le(input, sample_offset(input, info, index)) as f64;
    var black = info.black_red;
    if info.black_pattern_kind == 3 {
        black = tiff.u16le(input, info.black_pattern_offset + ((row % 2) * 2 + column % 2) * 2) as u32;
    }
    if info.black_pattern_kind == 4 {
        black = tiff.u32le(input, info.black_pattern_offset + ((row % 2) * 2 + column % 2) * 4);
    }
    var normalized = (raw - (black as f64)) / ((info.mosaic_white - black) as f64);
    if normalized > 1.0 {
        normalized = 1.0;
    }
    return normalized;
}

pub fn has_render_profile(info: DngInfo): bool {
    return info.color_supported and info.forward_matrix_offset != 0 and info.neutral_offset != 0;
}

fn write_sample(output: *f32, index: usize, value: f32): void {
    unchecked {
        const address = (output as! usize) + index * 4;
        *(address as! *f32) = value;
    }
}

pub fn normalized_sample(input: *const u8, info: DngInfo, index: usize): f64 {
    const raw = tiff.u16le(input, sample_offset(input, info, index)) as f64;
    var black: u32 = info.black_red;
    var white: u32 = info.white_red;
    if index % 3 == 1 {
        black = info.black_green;
        white = info.white_green;
    }
    if index % 3 == 2 {
        black = info.black_blue;
        white = info.white_blue;
    }
    var normalized = (raw - (black as f64)) / ((white - black) as f64);
    if normalized > 1.0 {
        normalized = 1.0;
    }
    return normalized;
}

fn probe(input: *const u8, length: usize, max_pixels: usize, width: *u32, height: *u32): i32 {
    const info = inspect(input, length as usize, max_pixels as usize);
    if info.status == 0 and info.photometric != 34892 {
        return 2;
    }
    if info.status == 0 {
        unchecked {
            *width = info.width as u32;
            *height = info.height as u32;
        }
    }
    return info.status;
}

fn probe_bayer(input: *const u8, length: usize, max_pixels: usize, width: *u32, height: *u32): i32 {
    const info = inspect(input, length as usize, max_pixels as usize);
    if info.status == 0 and info.photometric != 32803 {
        return 2;
    }
    if info.status == 0 {
        unchecked {
            *width = info.width as u32;
            *height = info.height as u32;
        }
    }
    return info.status;
}

fn decode(input: *const u8, length: usize, output: *f32, output_len: usize, max_pixels: usize): i32 {
    const info = inspect(input, length as usize, max_pixels as usize);
    if info.status != 0 {
        return info.status;
    }
    if info.photometric != 34892 {
        return 2;
    }
    const samples = info.width * info.height * 3;
    if output_len as usize != samples {
        return 4;
    }
    var index: usize = 0;
    while index < samples {
        const raw = tiff.u16le(input, sample_offset(input, info, index));
        var black: u32 = info.black_red;
        var white: u32 = info.white_red;
        if index % 3 == 1 {
            black = info.black_green;
            white = info.white_green;
        }
        if index % 3 == 2 {
            black = info.black_blue;
            white = info.white_blue;
        }
        var normalized: f32 = ((raw as f32) - (black as f32)) / ((white - black) as f32);
        if normalized > 1.0 {
            normalized = 1.0;
        }
        write_sample(output, index, normalized as f32);
        index = index + 1;
    }
    return 0;
}
