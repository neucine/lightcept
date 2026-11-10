import .document_state;
import { ProjectSaveStatus } from .document_state;

test "save completion accepts terminal statuses and bounds unknown callbacks" {
    assert(document_state.completed_save_status(2) == ProjectSaveStatus.saved);
    assert(document_state.completed_save_status(3) == ProjectSaveStatus.cancelled);
    assert(document_state.completed_save_status(5) == ProjectSaveStatus.changed_source);
    assert(document_state.completed_save_status(99) == ProjectSaveStatus.io_failure);
    assert(document_state.project_save_status(0) == ProjectSaveStatus.idle);
    assert(document_state.project_save_status(1) == ProjectSaveStatus.saving);
    assert(document_state.project_save_status(99) == ProjectSaveStatus.io_failure);
}

test "failed open retains a committed photograph" {
    const first = document_state.begin_open(document_state.empty());
    if first is opening {
        const ready = document_state.finish_open(opening, opening.generation, 0);
        assert(ready.has_photo);
        const second = document_state.begin_open(ready);
        if second is replacing {
            const failed = document_state.finish_open(replacing, replacing.generation, 2);
            assert(failed.has_photo);
            assert(failed.committed_generation == ready.committed_generation);
            assert(document_state.phase(failed) == 3);
            const report = document_state.snapshot(failed);
            assert(report.failure_code == 2);
            assert(report.has_photo);
            assert(report.committed_generation == ready.committed_generation);
            return;
        }
    }
    assert(false);
}

test "document phase follows open lifecycle" {
    assert(document_state.phase(document_state.empty()) == 0);
    const first = document_state.begin_open(document_state.empty());
    if first is opening {
        assert(document_state.phase(opening) == 1);
        const ready = document_state.finish_open(opening, opening.generation, 0);
        assert(document_state.phase(ready) == 2);
        return;
    }
    assert(false);
}

test "late completion cannot commit an older request" {
    const first = document_state.begin_open(document_state.empty());
    if first is opening {
        const second = document_state.begin_open(opening);
        if second is replacing {
            const stale = document_state.finish_open(replacing, opening.generation, 0);
            assert(not stale.has_photo);
            assert(stale.opening);
            assert(document_state.snapshot(stale).failure_code == 0);
            const ready = document_state.finish_open(stale, replacing.generation, 0);
            assert(ready.has_photo);
            assert(ready.committed_generation == replacing.generation);
            return;
        }
    }
    assert(false);
}

test "cancelled open rejects late completion and keeps the prior photo" {
    const first = document_state.begin_open(document_state.empty());
    if first is opening {
        const ready = document_state.finish_open(opening, opening.generation, 0);
        const second = document_state.begin_open(ready);
        if second is replacing {
            const cancelled = document_state.cancel_open(replacing);
            const late = document_state.finish_open(cancelled, replacing.generation, 0);
            assert(late.has_photo);
            assert(late.committed_generation == ready.committed_generation);
            assert(late.generation == replacing.generation);
            assert(document_state.phase(late) == 2);
            return;
        }
    }
    assert(false);
}

test "open failure statuses retain their bounded meaning" {
    const first = document_state.begin_open(document_state.empty());
    if first is opening {
        const limited = document_state.finish_open(opening, opening.generation, 3);
        assert(document_state.snapshot(limited).failure_code == 3);
        const retry = document_state.begin_open(limited);
        if retry is replacing {
            const cancelled = document_state.finish_open(replacing, replacing.generation, 7);
            assert(document_state.snapshot(cancelled).failure_code == 0);
            assert(document_state.phase(cancelled) == 0);
            return;
        }
    }
    assert(false);
}
