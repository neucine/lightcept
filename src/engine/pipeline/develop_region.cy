import .engine.pipeline.preview_develop_plan;

// Upright source pixel coordinates. Pixel centers and rectangle edges use
// integer visual pixels after the camera orientation has been applied.
pub struct Rect {
    pub left: usize;
    pub top: usize;
    pub width: usize;
    pub height: usize;
}

pub struct Region {
    pub source: Rect;
    pub requested: Rect;
    pub halo: usize;
    pub status: i32;
}

// Clarity samples a three-pixel radius. Texture then samples one pixel of
// that result. Expand by four to match the full-frame develop order.
pub const detail_halo: usize = 4;
pub const maximum_region_pixels: usize = 4194304;

fn required_halo(controls: preview_develop_plan.Controls): usize {
    var halo: usize = 0;
    if controls.clarity_percent != 0 {
        halo = 3;
    }
    if controls.texture_percent != 0 {
        halo = halo + 1;
    }
    return halo;
}

// Status 4 means invalid source/request geometry or resource limit; status 5
// means invalid develop controls.
// The returned source rectangle can be passed to a format's source-region
// reconstruction API. No geometry is usable when status is nonzero.
pub fn bounds(source_width: usize, source_height: usize,
    requested: Rect, controls: preview_develop_plan.Controls
): Region {
    var result: Region = {
        source: {
            left: 0,
            top: 0,
            width: 0,
            height: 0
        },
        requested: requested,
        halo: 0,
        status: 4
    };
    if source_width == 0 or source_height == 0 or
    source_width > 50000000 / source_height or
    requested.left >= source_width or requested.top >= source_height or
    requested.width == 0 or requested.height == 0 or
    requested.width > source_width - requested.left or
    requested.height > source_height - requested.top or
    requested.width > maximum_region_pixels / requested.height {
        return result;
    }
    if not preview_develop_plan.valid(controls) {
        result.status = 5;
        return result;
    }
    const halo = required_halo(controls);
    var left = requested.left;
    var top = requested.top;
    if left > halo {
        left = left - halo;
    } else {
        left = 0;
    }
    if top > halo {
        top = top - halo;
    } else {
        top = 0;
    }
    var right = requested.left + requested.width;
    var bottom = requested.top + requested.height;
    if source_width - right > halo {
        right = right + halo;
    } else {
        right = source_width;
    }
    if source_height - bottom > halo {
        bottom = bottom + halo;
    } else {
        bottom = source_height;
    }
    const width = right - left;
    const height = bottom - top;
    if width > maximum_region_pixels / height {
        return result;
    }
    result.source = {
        left: left,
        top: top,
        width: width,
        height: height
    };
    result.halo = halo;
    result.status = 0;
    return result;
}

// Develop one halo-expanded scene-linear Rec.2020/D65 working region with the
// same twelve-control preview plan, then return just requested opaque sRGB
// RGBA8 pixels. The caller owns the immutable working region and the output.
// The source extent and controls must match the earlier bounds call. A
// nonzero status invalidates output, including partial copies on cancellation.
pub fn render(region: Region, working: []const f64, output: []u8,
    baseline_exposure_ev: f64, controls: preview_develop_plan.Controls,
    cancelled: fn (usize): bool, context: usize
): i32 {
    const source = region.source;
    const requested = region.requested;
    if region.status != 0 or source.width == 0 or source.height == 0 or
    source.width > maximum_region_pixels / source.height or
    requested.width == 0 or requested.height == 0 or
    requested.width > maximum_region_pixels / requested.height or
    requested.left < source.left or requested.top < source.top or
    requested.width > source.width - (requested.left - source.left) or
    requested.height > source.height - (requested.top - source.top) or
    working.len() != source.width * source.height * 3 or
    output.len() != requested.width * requested.height * 4 {
        return 4;
    }
    if not preview_develop_plan.valid(controls) or
    required_halo(controls) != region.halo {
        return 5;
    }
    var expanded: [:]u8 = [: source.width * source.height * 4]u8;
    while expanded.len() < source.width * source.height * 4 {
        expanded.push(0);
    }
    const status = preview_develop_plan.render(working.ptr,
        working.len(), expanded[..].ptr, expanded.len(), source.width,
        source.height, baseline_exposure_ev, controls, cancelled, context
    );
    if status != 0 {
        return status;
    }
    const offset_x = requested.left - source.left;
    const offset_y = requested.top - source.top;
    var row: usize = 0;
    while row < requested.height {
        if cancelled(context) {
            return 7;
        }
        var column: usize = 0;
        while column < requested.width {
            const source_index = ((row + offset_y) * source.width + column + offset_x) * 4;
            const target_index = (row * requested.width + column) * 4;
            output[target_index] = expanded[source_index];
            output[target_index + 1] = expanded[source_index + 1];
            output[target_index + 2] = expanded[source_index + 2];
            output[target_index + 3] = expanded[source_index + 3];
            column = column + 1;
        }
        row = row + 1;
    }
    return 0;
}
