import .engine.analysis.auto_tone;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn tonal_histogram(): [258]u64 {
    var counts: [258]u64 = [0] ** 258;
    counts[9] = 10;
    counts[32] = 20;
    counts[65] = 20;
    counts[129] = 30;
    counts[225] = 20;
    return counts;
}

test "auto tone proposes bounded controls from a spread histogram" {
    const counts = tonal_histogram();
    const clip: [100]u8 = [0] ** 100;
    const result = auto_tone.propose(counts[0..], clip[0..],
        10, 10, 42, 1.0, no_cancel, 0
    );
    assert(result.status == 0 and result.version == 1);
    assert(result.source_hash == 42 and result.pixels == 100);
    assert(result.percentiles[0] < result.percentiles[1]);
    assert(result.percentiles[1] < result.percentiles[3]);
    assert(result.blacks_offset > 0.0);
    assert(result.shadows_strength < 0.0);
    assert(result.contrast_slope > 0.5 and result.contrast_slope <= 2.0);
    assert(result.highlights_strength > 0.0);
    assert(result.whites_strength > 0.0);
}

test "clipped pixels prevent brightening highlight and white proposals" {
    const counts = tonal_histogram();
    var clip: [100]u8 = [0] ** 100;
    clip[0] = 1;
    const result = auto_tone.propose(counts[0..], clip[0..],
        10, 10, 43, 1.0, no_cancel, 0
    );
    assert(result.status == 0 and result.clipped_pixels == 1);
    assert(result.highlights_strength <= 0.0);
    assert(result.whites_strength <= 0.0);
}

test "auto tone rejects mismatched and censored evidence" {
    var counts = tonal_histogram();
    const clip: [100]u8 = [0] ** 100;
    assert(auto_tone.propose(counts[0..], clip[0..],
        10, 10, 0, 1.0, no_cancel, 0
    ).status == 1);
    assert(auto_tone.propose(counts[0..], clip[0..],
        5, 10, 1, 1.0, no_cancel, 0
    ).status == 2);
    counts[9] = 0;
    counts[0] = 10;
    assert(auto_tone.propose(counts[0..], clip[0..],
        10, 10, 1, 1.0, no_cancel, 0
    ).status == 3);
    counts[0] = 0;
    counts[1] = 10;
    assert(auto_tone.propose(counts[0..], clip[0..],
        10, 10, 1, 1.0, no_cancel, 0
    ).status == 3);
    const original = tonal_histogram();
    var bad_clip: [100]u8 = [0] ** 100;
    bad_clip[0] = 8;
    assert(auto_tone.propose(original[0..], bad_clip[0..],
        10, 10, 1, 1.0, no_cancel, 0
    ).status == 5);
    assert(auto_tone.propose(original[0..], clip[0..],
        10, 10, 1, 1.0, cancel, 0
    ).status == 7);
    var narrow: [258]u64 = [0] ** 258;
    narrow[65] = 100;
    assert(auto_tone.propose(narrow[0..], clip[0..],
        10, 10, 1, 1.0, no_cancel, 0
    ).status == 4);
}
