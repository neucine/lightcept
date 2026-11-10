import .engine.develop.rgb_gradation;

// Worker request v5 appends nine little-endian encoded-sRGB output positions;
// v6 adds three luma positions. Each curve has fixed inputs 0.25, 0.5, 0.75
// and fixed endpoints. This transport module does not own curve mathematics.
pub struct Decoded {
    pub valid: bool;
    pub edit: rgb_gradation.FivePointEdit;
}

fn integer(bytes: []const u8, offset: usize): i32 {
    const raw = (bytes[offset] as u64) | ((bytes[offset + 1] as u64) << 8)
    | ((bytes[offset + 2] as u64) << 16) | ((bytes[offset + 3] as u64) << 24);
    if raw >= 2147483648 {
        return (raw as i64 - 4294967296) as i32;
    }
    return raw as i32;
}

pub fn decode(request: []const u8, offset: usize): Decoded {
    var edit = rgb_gradation.neutral_five_point_edit();
    if offset > request.len() or (request.len() - offset != 36 and
        request.len() - offset != 48 and request.len() - offset != 100 and
        request.len() - offset != 128
    ) {
        return {
            valid: false,
            edit: edit
        };
    }
    var channel: usize = 0;
    while channel < 3 {
        var node: usize = 0;
        while node < 3 {
            const value = integer(request, offset + (channel * 3 + node) * 4);
            if channel == 0 {
                edit.red[node] = value;
            } else if channel == 1 {
                edit.green[node] = value;
            } else {
                edit.blue[node] = value;
            }
            node = node + 1;
        }
        channel = channel + 1;
    }
    if request.len() - offset >= 48 {
        var node: usize = 0;
        while node < 3 {
            edit.luma[node] = integer(request, offset + 36 + node * 4);
            node = node + 1;
        }
    } else {
        edit.version = 1;
    }
    return {
        valid: rgb_gradation.valid_five_point_edit(edit),
        edit: edit
    };
}
