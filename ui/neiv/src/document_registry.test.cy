import .document_registry;
import .document_state;

test "two Neiv windows keep independent document generations" {
    var registry = document_registry.empty();
    const first = document_registry.ensure(&registry, 11);
    const second = document_registry.ensure(&registry, 22);
    if first is a {
        if second is b {
            assert(a != b);
            const started = document_state.begin_open(registry.slots[a].state);
            if started is opening {
                var slot = registry.slots[a];
                slot.state = document_state.finish_open(opening, opening.generation, 0);
                slot.exposure_tenths = 5;
                slot.contrast_percent = 40;
                slot.exposure_available = true;
                slot.navigator_preview = 71;
                slot.filmstrip_preview = 72;
                slot.edit_revision = 1;
                registry.slots[a] = slot;
                assert(registry.slots[a].state.has_photo);
                assert(not registry.slots[b].state.has_photo);
                assert(registry.slots[b].state.generation == 0);
                assert(registry.slots[b].exposure_tenths == 0);
                assert(registry.slots[b].contrast_percent == 0);
                assert(not registry.slots[b].exposure_available);
                document_registry.release(&registry, 11);
                assert(registry.slots[b].window == 22);
                const third = document_registry.ensure(&registry, 33);
                if third is reused {
                    assert(reused == a);
                    assert(registry.slots[reused].exposure_tenths == 0);
                    assert(registry.slots[reused].contrast_percent == 0);
                    assert(registry.slots[reused].edit_revision == 0);
                    assert(registry.slots[reused].navigator_preview == 0);
                    assert(registry.slots[reused].filmstrip_preview == 0);
                    return;
                }
            }
        }
    }
    assert(false);
}

test "document registry caps live windows and reuses a released slot" {
    var registry = document_registry.empty();
    var window: i64 = 1;
    while window <= 16 {
        const allocated = document_registry.ensure(&registry, window);
        if allocated is index {
            assert(index == (window - 1) as usize);
        } else {
            assert(false);
        }
        window = window + 1;
    }
    const full = document_registry.ensure(&registry, 17);
    if full is unexpected {
        assert(false);
    }
    document_registry.release(&registry, 8);
    const reused = document_registry.ensure(&registry, 17);
    if reused is index {
        assert(index == 7);
        return;
    }
    assert(false);
}
