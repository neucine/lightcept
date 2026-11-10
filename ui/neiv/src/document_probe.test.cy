import lightcept_core.engine.render.dng.dng_preview_buffer;
import std.fs;

test "Neiv inspects DNG bytes through its Cyna engine" {
    const source = fs.read_bytes("src/engine/tests/fixtures/synthetic-linearraw-1x1.dng") catch (error) {
        assert(false);
        return;
    };
    const probe = dng_preview_buffer.probe(source[..]);
    assert(probe.status == 0);
    assert(probe.width == 1);
    assert(probe.height == 1);
    assert(probe.photometric == 34892);
}

test "short data is rejected before pointer access" {
    const short: [:]u8 = [73, 73, 42];
    const probe = dng_preview_buffer.probe(short[..]);
    assert(probe.status != 0);
}
