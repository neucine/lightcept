import lightcept_core.engine.pipeline.dng.dng_legacy_preview_pipeline;
import lightcept_core.engine.render.dng.dng_preview_buffer;
import std.fs;

fn never_poll(context: usize): bool {
    const ignored = context;
    return false;
}

fn always_cancel(context: usize): bool {
    const ignored = context;
    return true;
}

test "Neiv renders a fitted DNG through the Cyna engine package" {
    const source = fs.read_bytes("src/engine/tests/fixtures/synthetic-profiled-linearraw-1x1.dng") catch (error) {
        assert(false);
        return;
    };
    var output: [:]u8 = [0, 0, 0, 0];
    const status = dng_legacy_preview_pipeline.render_fitted(source[..], output[..], 1, 1, never_poll, 0);
    assert(status == 0);
    assert(output[3] == 255);
}

test "invalid preview geometry cannot write output" {
    const source: [:]u8 = [73, 73, 42, 0, 8, 0, 0, 0];
    var output: [:]u8 = [17, 18, 19, 20];
    const status = dng_legacy_preview_pipeline.render_fitted(source[..], output[..], 0, 1, never_poll, 0);
    assert(status == 4);
    assert(output[0] == 17);
}

test "cancelled Cyna render discards its candidate" {
    const source = fs.read_bytes("src/engine/tests/fixtures/synthetic-profiled-linearraw-1x1.dng") catch (error) {
        assert(false);
        return;
    };
    var output: [:]u8 = [0, 0, 0, 0];
    const status = dng_legacy_preview_pipeline.render_fitted(source[..], output[..], 1, 1, always_cancel, 0);
    assert(status == 7);
}
