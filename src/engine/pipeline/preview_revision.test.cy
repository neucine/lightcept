import .engine.pipeline.preview_revision;
import .engine.pipeline.preview_develop_plan;
import .engine.pipeline.develop_replay;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

test "fixed preview revision replays prior bytes and rejects changed identity" {
    var source_hash: [32]u8 = [0] ** 32;
    var working_hash: [32]u8 = [0] ** 32;
    source_hash[0] = 11;
    working_hash[0] = 22;
    const source: develop_replay.WorkingSourceIdentity = {
        version: 1,
        source_sha256: source_hash,
        working_contract_sha256: working_hash,
        width: 3,
        height: 1,
        domain: 4
    };
    const controls: preview_develop_plan.Controls = {
        exposure_tenths: 0,
        contrast_percent: 0,
        shadows_percent: 0,
        highlights_percent: 0,
        blacks_percent: 0,
        whites_percent: 0,
        warmth_percent: 0,
        tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0
    };
    const opened: preview_revision.Revision = {
        sequence: 0,
        route: preview_revision.DNG_SPATIAL,
        source: source,
        baseline_exposure_ev: 0.0,
        controls: controls
    };
    assert(preview_revision.valid(opened));
    const exposure = preview_revision.set_exposure(opened, 1, 10);
    const automatic = preview_revision.set_exposure(exposure, 2, 5);
    assert(preview_revision.valid_child(opened, exposure));
    assert(preview_revision.valid_child(exposure, automatic));
    const working: [9]f64 = [0.02, 0.02, 0.02, 0.35, 0.35, 0.35, 0.75, 0.75, 0.75];
    var first: [12]u8 = [0] ** 12;
    var replay: [12]u8 = [0] ** 12;
    var later: [12]u8 = [0] ** 12;
    assert(preview_revision.render_pinned(exposure, exposure, working[0..].ptr, 9,
        first[0..].ptr, 12, no_cancel, 0
    ) == 0);
    assert(preview_revision.render_pinned(automatic, automatic, working[0..].ptr, 9,
        later[0..].ptr, 12, no_cancel, 0
    ) == 0);
    assert(preview_revision.render_pinned(exposure, exposure, working[0..].ptr, 9,
        replay[0..].ptr, 12, no_cancel, 0
    ) == 0);
    assert(first == replay and first != later);
    replay[0] = 19;
    assert(preview_revision.render_pinned(exposure, automatic, working[0..].ptr, 9,
        replay[0..].ptr, 12, no_cancel, 0
    ) == 8 and replay[0] == 19);
    var changed = exposure;
    changed.source.source_sha256[0] = 33;
    assert(not preview_revision.valid_child(opened, changed));
    assert(preview_revision.render_pinned(exposure, changed, working[0..].ptr, 9,
        replay[0..].ptr, 12, no_cancel, 0
    ) == 8);
}
