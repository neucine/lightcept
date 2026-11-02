import .engine.raw.dng.dng_source;

const max_source_bytes: usize = 512 * 1024 * 1024;
const max_source_pixels: usize = 64 * 1024 * 1024;
const max_preview_side: usize = 2048;

pub fn source_byte_limit(): usize {
    return max_source_bytes;
}
pub fn source_pixel_limit(): usize {
    return max_source_pixels;
}
pub fn preview_side_limit(): usize {
    return max_preview_side;
}

pub struct DngPreviewInfo {
    pub status: i32;
    pub width: usize;
    pub height: usize;
    pub photometric: u32;
}

pub fn probe_raw(source: *const u8, source_len: usize): DngPreviewInfo {
    if (source as! usize) == 0 or source_len < 8 or source_len > max_source_bytes {
        return {
            status: 1,
            width: 0,
            height: 0,
            photometric: 0
        };
    }
    const info = dng_source.inspect(source, source_len, max_source_pixels);
    return {
        status: info.status,
        width: info.width,
        height: info.height,
        photometric: info.photometric
    };
}

pub fn probe(source: []const u8): DngPreviewInfo {
    if source.len() == 0 {
        return {
            status: 1,
            width: 0,
            height: 0,
            photometric: 0
        };
    }
    return probe_raw(source.ptr as! *const u8, source.len());
}
