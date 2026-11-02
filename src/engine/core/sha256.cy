// Bounded SHA-256 v1, following NIST FIPS 180-4 sections 5 and 6.2.
// Immutable bytes in; caller-owned 32-byte digest out. At most 1 MiB input.
// Status 0 success, 1 input limit, 2 output shape, 7 cancellation. Digest
// output is written only after all blocks complete; failure leaves it intact.
pub const algorithm_version: u32 = 1;
pub const maximum_bytes: usize = 1048576;

fn rotate_right(value: u32, bits: u32): u32 {
    return (value >> bits) | (value << (32 - bits));
}

fn padded_byte(input: []const u8, index: usize,
    padded: usize, bit_length: u64
): u8 {
    if index < input.len() {
        return input[index];
    }
    if index == input.len() {
        return 128;
    }
    if index >= padded - 8 {
        const shift = ((padded - 1 - index) * 8) as u32;
        return ((bit_length >> shift) & 255) as u8;
    }
    return 0;
}

pub fn digest(input: []const u8, output: []u8,
    cancelled: fn (usize): bool, context: usize
): u32 {
    if input.len() > maximum_bytes {
        return 1;
    }
    if output.len() != 32 {
        return 2;
    }
    const k: [64]u32 = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];
    var state: [8]u32 = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];
    const padded = ((input.len() + 72) / 64) * 64;
    const bit_length = (input.len() as u64) * 8;
    var block: usize = 0;
    while block < padded / 64 {
        if cancelled(context) {
            return 7;
        }
        var words: [64]u32 = [0] ** 64;
        var index: usize = 0;
        while index < 16 {
            const offset = block * 64 + index * 4;
            words[index] = ((padded_byte(input, offset, padded, bit_length) as u32) << 24)
            | ((padded_byte(input, offset + 1, padded, bit_length) as u32) << 16)
            | ((padded_byte(input, offset + 2, padded, bit_length) as u32) << 8)
            | (padded_byte(input, offset + 3, padded, bit_length) as u32);
            index = index + 1;
        }
        while index < 64 {
            const x = words[index - 15];
            const y = words[index - 2];
            const small0 = rotate_right(x, 7) ^ rotate_right(x, 18) ^ (x >> 3);
            const small1 = rotate_right(y, 17) ^ rotate_right(y, 19) ^ (y >> 10);
            words[index] = words[index - 16] +% small0 +% words[index - 7] +% small1;
            index = index + 1;
        }
        var a = state[0];
        var b = state[1];
        var c = state[2];
        var d = state[3];
        var e = state[4];
        var f = state[5];
        var g = state[6];
        var h = state[7];
        index = 0;
        while index < 64 {
            const large1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25);
            const choose = (e & f) ^ (~e & g);
            const temp1 = h +% large1 +% choose +% k[index] +% words[index];
            const large0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22);
            const majority = (a & b) ^ (a & c) ^ (b & c);
            const temp2 = large0 +% majority;
            h = g;
            g = f;
            f = e;
            e = d +% temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 +% temp2;
            index = index + 1;
        }
        state[0] = state[0] +% a;
        state[1] = state[1] +% b;
        state[2] = state[2] +% c;
        state[3] = state[3] +% d;
        state[4] = state[4] +% e;
        state[5] = state[5] +% f;
        state[6] = state[6] +% g;
        state[7] = state[7] +% h;
        block = block + 1;
    }
    var index: usize = 0;
    while index < 8 {
        const word = state[index];
        output[index * 4] = ((word >> 24) & 255) as u8;
        output[index * 4 + 1] = ((word >> 16) & 255) as u8;
        output[index * 4 + 2] = ((word >> 8) & 255) as u8;
        output[index * 4 + 3] = (word & 255) as u8;
        index = index + 1;
    }
    return 0;
}
