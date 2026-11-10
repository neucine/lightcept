import .document_state;
import .develop_history;

pub struct WindowDocument {
    pub window: i64;
    pub document_id: u32;
    pub state: document_state.DocumentState;
    pub preview: i64;
    pub navigator_preview: i64;
    pub filmstrip_preview: i64;
    pub histogram_preview: i64;
    pub exposure_tenths: i32;
    pub pending_exposure_tenths: i32;
    pub contrast_percent: i32;
    pub pending_contrast_percent: i32;
    pub shadows_percent: i32;
    pub pending_shadows_percent: i32;
    pub highlights_percent: i32;
    pub pending_highlights_percent: i32;
    pub blacks_percent: i32;
    pub pending_blacks_percent: i32;
    pub whites_percent: i32;
    pub pending_whites_percent: i32;
    pub warmth_percent: i32;
    pub pending_warmth_percent: i32;
    pub tint_percent: i32;
    pub pending_tint_percent: i32;
    pub vibrance_percent: i32;
    pub saturation_percent: i32;
    pub pending_vibrance_percent: i32;
    pub pending_saturation_percent: i32;
    pub clarity_percent: i32;
    pub texture_percent: i32;
    pub pending_clarity_percent: i32;
    pub pending_texture_percent: i32;
    pub pending_edit: bool;
    pub exposure_available: bool;
    pub edit_revision: u32;
    pub history: develop_history.History;
    pub pending_history_cursor: i32;
    pub pending_geometry: bool;
    pub pending_geometry_values: develop_history.Values;
    pub pending_project_history: develop_history.History;
    pub restoring_project: bool;
    pub project_ready: bool;
    pub pending_project_revision: u32;
    pub pending_project_count: u32;
    pub project_status: u32;
}

// A bounded process registry. Callers serialize mutation; source bytes and
// rendered frames are held outside this small workflow table.
pub struct Registry {
    pub slots: [16]WindowDocument;
}

pub fn empty(): Registry {
    const slot: WindowDocument = {
        window: 0,
        document_id: 0,
        state: document_state.empty(),
        preview: 0,
        navigator_preview: 0,
        filmstrip_preview: 0,
        histogram_preview: 0,
        exposure_tenths: 0,
        pending_exposure_tenths: 0,
        contrast_percent: 0,
        pending_contrast_percent: 0,
        shadows_percent: 0,
        pending_shadows_percent: 0,
        highlights_percent: 0,
        pending_highlights_percent: 0,
        blacks_percent: 0,
        pending_blacks_percent: 0,
        whites_percent: 0,
        pending_whites_percent: 0,
        warmth_percent: 0,
        pending_warmth_percent: 0,
        tint_percent: 0,
        pending_tint_percent: 0,
        vibrance_percent: 0,
        saturation_percent: 0,
        pending_vibrance_percent: 0,
        pending_saturation_percent: 0,
        clarity_percent: 0,
        texture_percent: 0,
        pending_clarity_percent: 0,
        pending_texture_percent: 0,
        pending_edit: false,
        exposure_available: false,
        edit_revision: 0,
        history: develop_history.empty(),
        pending_history_cursor: -1,
        pending_geometry: false,
        pending_geometry_values: develop_history.neutral(),
        pending_project_history: develop_history.empty(),
        restoring_project: false,
        project_ready: false,
        pending_project_revision: 0,
        pending_project_count: 0,
        project_status: 0
    };
    return {
        slots: [slot] ** 16
    };
}

pub fn find(registry: &const Registry, window: i64): ?usize {
    if window <= 0 {
        return none;
    }
    var index: usize = 0;
    while index < 16 {
        if registry.slots[index].window == window {
            return index;
        }
        index = index + 1;
    }
    return none;
}

pub fn ensure(registry: &Registry, window: i64): ?usize {
    if find(registry, window) is index {
        return index;
    }
    if window <= 0 {
        return none;
    }
    var index: usize = 0;
    while index < 16 {
        if registry.slots[index].window == 0 {
            registry.slots[index] = {
                window: window,
                document_id: 0,
                state: document_state.empty(),
                preview: 0,
                navigator_preview: 0,
                filmstrip_preview: 0,
                histogram_preview: 0,
                exposure_tenths: 0,
                pending_exposure_tenths: 0,
                contrast_percent: 0,
                pending_contrast_percent: 0,
                shadows_percent: 0,
                pending_shadows_percent: 0,
                highlights_percent: 0,
                pending_highlights_percent: 0,
                blacks_percent: 0,
                pending_blacks_percent: 0,
                whites_percent: 0,
                pending_whites_percent: 0,
                warmth_percent: 0,
                pending_warmth_percent: 0,
                tint_percent: 0,
                pending_tint_percent: 0,
                vibrance_percent: 0,
                saturation_percent: 0,
                pending_vibrance_percent: 0,
                pending_saturation_percent: 0,
                clarity_percent: 0,
                texture_percent: 0,
                pending_clarity_percent: 0,
                pending_texture_percent: 0,
                pending_edit: false,
                exposure_available: false,
                edit_revision: 0,
                history: develop_history.empty(),
                pending_history_cursor: -1,
                pending_geometry: false,
                pending_geometry_values: develop_history.neutral(),
                pending_project_history: develop_history.empty(),
                restoring_project: false,
                project_ready: false,
                pending_project_revision: 0,
                pending_project_count: 0,
                project_status: 0
            };
            return index;
        }
        index = index + 1;
    }
    return none;
}

pub fn release(registry: &Registry, window: i64): void {
    if find(registry, window) is index {
        registry.slots[index] = {
            window: 0,
            document_id: 0,
            state: document_state.empty(),
            preview: 0,
            navigator_preview: 0,
            filmstrip_preview: 0,
            histogram_preview: 0,
            exposure_tenths: 0,
            pending_exposure_tenths: 0,
            contrast_percent: 0,
            pending_contrast_percent: 0,
            shadows_percent: 0,
            pending_shadows_percent: 0,
            highlights_percent: 0,
            pending_highlights_percent: 0,
            blacks_percent: 0,
            pending_blacks_percent: 0,
            whites_percent: 0,
            pending_whites_percent: 0,
            warmth_percent: 0,
            pending_warmth_percent: 0,
            tint_percent: 0,
            pending_tint_percent: 0,
            vibrance_percent: 0,
            saturation_percent: 0,
            pending_vibrance_percent: 0,
            pending_saturation_percent: 0,
            clarity_percent: 0,
            texture_percent: 0,
            pending_clarity_percent: 0,
            pending_texture_percent: 0,
            pending_edit: false,
            exposure_available: false,
            edit_revision: 0,
            history: develop_history.empty(),
            pending_history_cursor: -1,
            pending_geometry: false,
            pending_geometry_values: develop_history.neutral(),
            pending_project_history: develop_history.empty(),
            restoring_project: false,
            project_ready: false,
            pending_project_revision: 0,
            pending_project_count: 0,
            project_status: 0
        };
    }
}
