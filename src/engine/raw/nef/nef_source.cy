import .engine.tiff.tiff;
import .engine.raw.nef.nef_makernote;
import { NefMakerMetadata } from .engine.raw.nef.nef_makernote;

// Nikon Z8 Classic TIFF storage probe v1. This is a container boundary only:
// maker-note seeds, crop, black levels, and camera characterization are separate
// requirements before a source can enter the product render route.
// Status: 0 supported storage, 1 malformed, 2 unsupported layout, 3 limit,
// 6 not a Z8 NEF. Offsets and lengths are bytes; dimensions are photosites.
pub struct NefStorage {
    pub width: u32;
    pub height: u32;
    pub strip_offset: u32;
    pub strip_bytes: u32;
    pub orientation: u32;
    pub cfa: u32;
    pub status: c_int;
}

pub struct NefSource {
    pub storage: NefStorage;
    pub maker: NefMakerMetadata;
    pub status: c_int;
}

struct Entry {
    kind: u16;
    count: u32;
    value: u32;
}

fn empty(status: c_int): NefStorage {
    return {
        width: 0,
        height: 0,
        strip_offset: 0,
        strip_bytes: 0,
        orientation: 1,
        cfa: 0,
        status: status
    };
}

fn directory_valid(input: *const c_uchar, length: usize, offset: usize): bool {
    if not tiff.has_range(length, offset, 2) {
        return false;
    }
    const count = tiff.u16le(input, offset) as usize;
    return count <= 256 and tiff.has_range(length, offset + 2, count * 12 + 4);
}

fn find(input: *const c_uchar, offset: usize, tag: u16): ?Entry {
    const count = tiff.u16le(input, offset) as usize;
    var result: ?Entry = none;
    var index: usize = 0;
    while index < count {
        const at = offset + 2 + index * 12;
        if tiff.u16le(input, at) == tag {
            if result is present {
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

fn scalar(entry: Entry): ?u32 {
    if entry.count != 1 {
        return none;
    }
    if entry.kind == 3 {
        return entry.value % 65536;
    }
    if entry.kind == 4 {
        return entry.value;
    }
    return none;
}

fn value(input: *const c_uchar, offset: usize, tag: u16): ?u32 {
    if find(input, offset, tag) is entry {
        return scalar(entry);
    }
    return none;
}

pub fn inspect(input: *const c_uchar, length: usize): NefStorage {
    if (input as! usize) == 0 or not tiff.has_range(length, 0, 8) {
        return empty(1);
    }
    if tiff.byte(input, 0) != 73 or tiff.byte(input, 1) != 73 or tiff.u16le(input, 2) != 42 {
        return empty(6);
    }
    const root = tiff.u32le(input, 4) as usize;
    if not directory_valid(input, length, root) {
        return empty(1);
    }
    if find(input, root, 50706) is marker {
        const ignored = marker;
        return empty(6);
    }
    if find(input, root, 272) is model {
        if model.kind != 2 or model.count != 10 or not tiff.has_range(length, model.value as usize, 10) {
            return empty(6);
        }
        const label: [10]u8 = [78, 73, 75, 79, 78, 32, 90, 32, 56, 0];
        var i: usize = 0;
        while i < 10 {
            if tiff.byte(input, model.value as usize + i) != label[i] {
                return empty(6);
            }
            i = i + 1;
        }
    } else {
        return empty(6);
    }
    var orientation: u32 = 1;
    if find(input, root, 274) is direction {
        if scalar(direction) is number {
            if number < 1 or number > 8 {
                return empty(2);
            }
            orientation = number;
        } else {
            return empty(2);
        }
    }
    var subifds: Entry = {
        kind: 0,
        count: 0,
        value: 0
    };
    if find(input, root, 330) is entry {
        subifds = entry;
    } else {
        return empty(2);
    }
    if subifds.kind != 4 or subifds.count == 0 or subifds.count > 8 {
        return empty(2);
    }
    const count = subifds.count as usize;
    if count > 1 and not tiff.has_range(length, subifds.value as usize, count * 4) {
        return empty(1);
    }
    var found = false;
    var storage = empty(2);
    var index: usize = 0;
    while index < count {
        var child = subifds.value as usize;
        if count > 1 {
            child = tiff.u32le(input, child + index * 4) as usize;
        }
        if not directory_valid(input, length, child) {
            return empty(1);
        }
        if value(input, child, 262) is photometric {
            if photometric == 32803 {
                if found {
                    return empty(2);
                }
                found = true;
                var width: u32 = 0;
                var height: u32 = 0;
                if value(input, child, 256) is dimension {
                    width = dimension;
                } else {
                    return empty(2);
                }
                if value(input, child, 257) is dimension {
                    height = dimension;
                } else {
                    return empty(2);
                }
                if width == 0 or height == 0 or width > 10000 or height > 10000 or width > 50000000 / height {
                    return empty(3);
                }
                var bits: u32 = 0;
                var compression: u32 = 0;
                var samples: u32 = 0;
                var rows: u32 = 0;
                if value(input, child, 258) is number {
                    bits = number;
                }
                if value(input, child, 259) is number {
                    compression = number;
                }
                if value(input, child, 277) is number {
                    samples = number;
                }
                if value(input, child, 278) is number {
                    rows = number;
                }
                if bits != 14 or compression != 34713 or samples != 1 or rows != height {
                    return empty(2);
                }
                var strip: u32 = 0;
                var bytes: u32 = 0;
                if value(input, child, 273) is number {
                    strip = number;
                } else {
                    return empty(2);
                }
                if value(input, child, 279) is number {
                    bytes = number;
                } else {
                    return empty(2);
                }
                if bytes == 0 or not tiff.has_range(length, strip as usize, bytes as usize) {
                    return empty(1);
                }
                var repeat: Entry = {
                    kind: 0,
                    count: 0,
                    value: 0
                };
                var pattern: Entry = {
                    kind: 0,
                    count: 0,
                    value: 0
                };
                if find(input, child, 33421) is entry {
                    repeat = entry;
                } else {
                    return empty(2);
                }
                if find(input, child, 33422) is entry {
                    pattern = entry;
                } else {
                    return empty(2);
                }
                if repeat.kind != 3 or repeat.count != 2 or repeat.value != 131074 or pattern.kind != 1 or pattern.count != 4 {
                    return empty(2);
                }
                const cfa_bytes = pattern.value;
                var red: u32 = 0;
                var green: u32 = 0;
                var blue: u32 = 0;
                var shift: u32 = 0;
                while shift < 32 {
                    const channel = (cfa_bytes >> shift) % 256;
                    if channel == 0 {
                        red = red + 1;
                    } else if channel == 1 {
                        green = green + 1;
                    } else if channel == 2 {
                        blue = blue + 1;
                    } else {
                        return empty(2);
                    }
                    shift = shift + 8;
                }
                if red != 1 or green != 2 or blue != 1 {
                    return empty(2);
                }
                storage = {
                    width: width,
                    height: height,
                    strip_offset: strip,
                    strip_bytes: bytes,
                    orientation: orientation,
                    cfa: cfa_bytes,
                    status: 0
                };
            }
        }
        index = index + 1;
    }
    return storage;
}

// Resolve the exact Z8 storage layout and its Nikon maker-note metadata in
// one checked source view. No sensor codes or pixels are decoded here.
pub fn inspect_source(source: []const u8): NefSource {
    const storage = inspect(source.ptr as! *const c_uchar, source.len());
    var result: NefSource = {
        storage: storage,
        maker: nef_makernote.parse(source[0..0], 0, 0),
        status: storage.status
    };
    if storage.status != 0 {
        return result;
    }
    const input = source.ptr as! *const c_uchar;
    const root = tiff.u32le(input, 4) as usize;
    if value(input, root, 34665) is exif_offset {
        const exif = exif_offset as usize;
        if not directory_valid(input, source.len(), exif) {
            result.status = 1;
            return result;
        }
        if find(input, exif, 37500) is note {
            if note.kind != 7 or note.count < 18 or note.count > 1048576 {
                result.status = 2;
                return result;
            }
            const at = note.value as usize;
            if not tiff.has_range(source.len(), at, note.count as usize) {
                result.status = 1;
                return result;
            }
            result.maker = nef_makernote.parse(source[at..at + note.count as usize], storage.width, storage.height);
            result.status = result.maker.status;
            return result;
        }
    }
    result.status = 2;
    return result;
}
