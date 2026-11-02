import std.fs;
import .engine.color.output_profile;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

test "output profile validates the pinned asset and exact candidate bytes" {
    const pinned = fs.read_bytes("src/engine/assets/sRGB2014.icc") catch (error) {
        assert(false);
        return;
    };
    assert(pinned.len() == output_profile.srgb2014_bytes);
    const accepted = output_profile.select(pinned[..], no_cancel, 0);
    assert(accepted.status == 0 and accepted.version == 1);
    assert(accepted.byte_count == pinned.len());
    var changed = pinned.clone();
    changed[200] = changed[200] ^ 1;
    assert(output_profile.select(changed[..], no_cancel, 0).status == 2);
    changed[36] = 0;
    assert(output_profile.select(changed[..], no_cancel, 0).status == 1);
    assert(output_profile.select(pinned[0..127], no_cancel, 0).status == 1);
    assert(output_profile.select(pinned[..], cancel, 0).status == 7);
}
