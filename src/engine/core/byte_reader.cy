// Bounds helpers for byte-oriented source decoders.
pub fn has_range(length: usize, offset: usize, count: usize): bool {
    return offset <= length and count <= length - offset;
}

// Caller checks the source range before reading.
pub fn byte(input: *const u8, offset: usize): u8 {
    unchecked {
        return *(((input as! usize) + offset) as! *const u8);
    }
}
