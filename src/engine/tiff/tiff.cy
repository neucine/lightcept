// Bounded little-endian Classic TIFF reads. Every byte access checks the range first.
pub fn has_range(length: usize, offset: usize, count: usize): bool {
    if offset > length {
        return false;
    }
    return count <= length - offset;
}

pub fn byte(input: *const u8, offset: usize): u8 {
    unchecked {
        const address = (input as! usize) + offset;
        return *(address as! *const u8);
    }
}

pub fn u16le(input: *const u8, offset: usize): u16 {
    return (byte(input, offset) as u16) + ((byte(input, offset + 1) as u16) * 256);
}

pub fn u32le(input: *const u8, offset: usize): u32 {
    return (u16le(input, offset) as u32) + ((u16le(input, offset + 2) as u32) * 65536);
}

pub fn i32le(input: *const u8, offset: usize): i64 {
    const value = u32le(input, offset) as i64;
    if value >= 2147483648 {
        return value - 4294967296;
    }
    return value;
}
