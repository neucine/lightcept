// App workflow identity. The imaging engine does not depend on this state.
pub enum DocumentPhase: u32 {
    empty = 0,
    opening = 1,
    ready = 2,
    failed = 3,
}

pub enum OpenStatus: u32 {
    ok = 0,
    unreadable_source = 1,
    unsupported_dng = 2,
    resource_limit = 3,
    invalid_buffer = 4,
    processing_failure = 5,
    non_raw_source = 6,
    cancelled = 7,
    changed_source = 8,
    invalid_project = 9,
    project_io = 10,
    incompatible_route = 11,
}

pub fn open_status(code: u32): OpenStatus {
    if code == 0 {
        return OpenStatus.ok;
    }
    if code == 1 {
        return OpenStatus.unreadable_source;
    }
    if code == 2 {
        return OpenStatus.unsupported_dng;
    }
    if code == 3 {
        return OpenStatus.resource_limit;
    }
    if code == 4 {
        return OpenStatus.invalid_buffer;
    }
    if code == 5 {
        return OpenStatus.processing_failure;
    }
    if code == 6 {
        return OpenStatus.non_raw_source;
    }
    if code == 7 {
        return OpenStatus.cancelled;
    }
    if code == 8 {
        return OpenStatus.changed_source;
    }
    if code == 9 {
        return OpenStatus.invalid_project;
    }
    if code == 10 {
        return OpenStatus.project_io;
    }
    if code == 11 {
        return OpenStatus.incompatible_route;
    }
    return OpenStatus.processing_failure;
}

pub enum ProjectSaveStatus: u32 {
    idle = 0,
    saving = 1,
    saved = 2,
    cancelled = 3,
    io_failure = 4,
    changed_source = 5,
}

// Native save completion is a numeric callback. An unexpected value is an I/O
// failure so the document can leave the saving state with a valid snapshot.
pub fn completed_save_status(status: u32): ProjectSaveStatus {
    if status == ProjectSaveStatus.saved as u32 {
        return ProjectSaveStatus.saved;
    }
    if status == ProjectSaveStatus.cancelled as u32 {
        return ProjectSaveStatus.cancelled;
    }
    if status == ProjectSaveStatus.changed_source as u32 {
        return ProjectSaveStatus.changed_source;
    }
    return ProjectSaveStatus.io_failure;
}

pub fn project_save_status(status: u32): ProjectSaveStatus {
    if status == ProjectSaveStatus.idle as u32 {
        return ProjectSaveStatus.idle;
    }
    if status == ProjectSaveStatus.saving as u32 {
        return ProjectSaveStatus.saving;
    }
    return completed_save_status(status);
}

pub struct DocumentState {
    pub generation: u32;
    pub committed_generation: u32;
    pub has_photo: bool;
    pub opening: bool;
    pub failure_code: u32;
}

// A product snapshot can be copied without exposing a source path or pixels.
// Failure code 0 means none. Other codes preserve the bounded engine/open
// statuses: 1 unreadable/invalid source, 2 unsupported DNG variant,
// 3 resource limit, 4 invalid geometry/buffer, 5 processing failure,
// 6 non-RAW source, 8 changed source, 9 invalid project, 10 project I/O,
// 11 incompatible route. Status 7 is cancellation and clears the failure code.
pub struct DocumentSnapshot {
    pub generation: u32;
    pub committed_generation: u32;
    pub phase: u32;
    pub has_photo: bool;
    pub failure_code: u32;
}

// Phase codes are stable at the Neiv command boundary: empty=0, opening=1,
// ready=2, failed=3. A failed replacement retains the committed photograph.
pub fn phase_kind(current: DocumentState): DocumentPhase {
    if current.opening {
        return DocumentPhase.opening;
    }
    if current.failure_code != 0 {
        return DocumentPhase.failed;
    }
    if current.has_photo {
        return DocumentPhase.ready;
    }
    return DocumentPhase.empty;
}

pub fn phase(current: DocumentState): u32 {
    return phase_kind(current) as u32;
}

pub fn snapshot(current: DocumentState): DocumentSnapshot {
    return {
        generation: current.generation,
        committed_generation: current.committed_generation,
        phase: phase(current),
        has_photo: current.has_photo,
        failure_code: current.failure_code
    };
}

pub fn empty(): DocumentState {
    return {
        generation: 0,
        committed_generation: 0,
        has_photo: false,
        opening: false,
        failure_code: 0
    };
}

// A generation is never reused, including after a failed or cancelled open.
pub fn begin_open(current: DocumentState): ?DocumentState {
    if current.generation == 4294967295 {
        return none;
    }
    return DocumentState {
        generation: current.generation + 1,
        committed_generation: current.committed_generation,
        has_photo: current.has_photo,
        opening: true,
        failure_code: 0
    };
}

// The state transition rejects a late completion. Frame publication needs the
// same generation check before concurrent opens can be enabled.
pub fn finish_open(current: DocumentState, generation: u32, status: u32): DocumentState {
    if not current.opening or current.generation != generation {
        return current;
    }
    var committed_generation = current.committed_generation;
    var has_photo = current.has_photo;
    var failure_code = status;
    if status == 0 {
        committed_generation = generation;
        has_photo = true;
        failure_code = 0;
    } else if status == OpenStatus.cancelled as u32 {
        failure_code = 0;
    } else if status > OpenStatus.incompatible_route as u32 {
        failure_code = OpenStatus.processing_failure as u32;
    }
    return {
        generation: current.generation,
        committed_generation: committed_generation,
        has_photo: has_photo,
        opening: false,
        failure_code: failure_code
    };
}

// Cancelling invalidates publication for this generation. A later open still
// increments from the same generation, so an old worker cannot become current.
pub fn cancel_open(current: DocumentState): DocumentState {
    if not current.opening {
        return current;
    }
    return {
        generation: current.generation,
        committed_generation: current.committed_generation,
        has_photo: current.has_photo,
        opening: false,
        failure_code: 0
    };
}
