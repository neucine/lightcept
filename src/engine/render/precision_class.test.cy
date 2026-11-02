import .engine.render.precision_class;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn settings(bits: u32, channels: u32): precision_class.PrecisionPolicy {
    return {
        version: 1,
        channel_bits: bits,
        channels: channels,
        dither: precision_class.dither_none,
        rounding: precision_class.round_nearest_ties_up
    };
}

test "precision class selects bounded 8 and 16 bit layouts" {
    const preview = precision_class.select(3, 2, settings(8, 4),
        no_cancel, 0
    );
    assert(preview.status == 0 and preview.version == 1);
    assert(preview.pixels == 6 and preview.samples == 24);
    assert(preview.bytes == 24 and preview.maximum_code == 255);
    const export_rgb = precision_class.select(3, 2, settings(16, 3),
        no_cancel, 0
    );
    assert(export_rgb.status == 0 and export_rgb.samples == 18);
    assert(export_rgb.bytes == 36 and export_rgb.maximum_code == 65535);
    const maximum = precision_class.select(16777216, 1, settings(16, 3),
        no_cancel, 0
    );
    assert(maximum.status == 0 and maximum.samples == 50331648);
    assert(maximum.bytes == 100663296);
}

test "precision class rejects unsupported policy dimensions and cancellation" {
    var unsupported = settings(16, 4);
    assert(precision_class.select(2, 2, unsupported,
        no_cancel, 0
    ).status == 1);
    unsupported = settings(8, 4);
    unsupported.dither = 1;
    assert(precision_class.select(2, 2, unsupported,
        no_cancel, 0
    ).status == 1);
    assert(precision_class.select(0, 2, settings(8, 3),
        no_cancel, 0
    ).status == 2);
    assert(precision_class.select(2, 2, settings(8, 3),
        cancel, 0
    ).status == 7);
}
