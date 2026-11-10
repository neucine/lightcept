import { configure_window } from neiv.lib;
import { current, open, raw_handle } from neiv.window;
import .document_state;
import { ProjectSaveStatus } from .document_state;
import .document_registry;
import .develop_history;
import lightcept_core.engine.develop.orthogonal_transform;
import { select_photo, select_project, save_project_native, export_tiff_native, export_status_native, cancel_export_native, cancel_picker, snapshot_text, SnapshotValues, lock_documents, unlock_documents, rerender_develop, rerender_history, source_canvas_size, commit_frame, discard_candidate, create_preview, create_navigator_preview, create_filmstrip_preview, create_histogram, surface_alive, destroy_surface, set_comparison, set_zoom, set_crop_mode, set_crop_aspect, set_color_pick_mode, show_color_selection } from .native_preview;
import lightcept_core.engine.develop.picked_color;
import neiv.native_buffer;

// @neiv-callback
pub fn sample_picked_hue(input: native_buffer.ReadBuffer): i32 {
    if input.length != 24 {
        return -1;
    }
    const pixels = input.pointer as! *const f64;
    var red: f64 = 0.0;
    var green: f64 = 0.0;
    var blue: f64 = 0.0;
    unchecked {
        red = *pixels;
        green = *(((pixels as! usize) + 8) as! *const f64);
        blue = *(((pixels as! usize) + 16) as! *const f64);
    }
    return picked_color.sample_hue(red, green, blue);
}

// @neiv-callback
pub fn render_picked_mask(input: native_buffer.ReadBuffer, output: native_buffer.WriteBuffer, source_width: usize, source_height: usize, mask_width: usize, mask_height: usize, hue: i32, width: i32, softness: i32): i32 {
    const edit: picked_color.SelectionEdit = {
        version: picked_color.algorithm_version,
        enabled: true,
        center_degrees: hue,
        half_width_degrees: width,
        softness_percent: softness,
        hue_shift_percent: 0,
        saturation_percent: 0,
        brightness_percent: 0
    };
    if not picked_color.valid(edit) {
        return 1;
    }
    return picked_color.mask_rgba(input.pointer as! *const f64, input.length / 8, source_width, source_height, edit, output.pointer, output.length, mask_width, mask_height);
}

// Numeric values are fixed by the generated Neiv command boundary.
enum DevelopControl: i32 {
    warmth = 0,
    tint = 1,
    vibrance = 2,
    saturation = 3,
    clarity = 4,
    texture = 5,
}

enum ToneControl: i32 {
    shadows = 1,
    highlights = 2,
    blacks = 3,
    whites = 4,
}

enum PreviewComparison: i32 {
    after = 0,
    before = 1,
    split = 2,
}

enum ProofProfile: i32 {
    off = 0,
    srgb = 1,
    adobe_rgb = 2,
    monitor = 3,
}

// @neiv-event {"topic":"lightcept.zoom","payload":{"type":"record","fields":{"percent":{"type":"number","min":25,"max":400}}}}
// @neiv-event {"topic":"lightcept.detail","payload":{"type":"record","fields":{"ready":"boolean"}}}
// @neiv-event {"topic":"lightcept.crop","payload":{"type":"record","fields":{"left":{"type":"number","min":0,"max":10000},"top":{"type":"number","min":0,"max":10000},"width":{"type":"number","min":2,"max":10000},"height":{"type":"number","min":2,"max":10000},"angleMillidegrees":{"type":"number","min":-17000,"max":17000}}}}
// @neiv-event {"topic":"lightcept.color_pick","payload":{"type":"record","fields":{"hue":{"type":"number","min":-1,"max":359}}}}

// Schema 12 extends schema 11 with four grading wheels and tonal balance.
enum ProjectField: usize {
    exposure = 0,
    contrast = 1,
    shadows = 2,
    highlights = 3,
    blacks = 4,
    whites = 5,
    warmth = 6,
    tint = 7,
    vibrance = 8,
    saturation = 9,
    clarity = 10,
    texture = 11,
    crop_left = 12,
    crop_top = 13,
    crop_width = 14,
    crop_height = 15,
    straighten_millidegrees = 16,
    transform_code = 17,
    count = 74,
}

var documents: document_registry.Registry = {
    slots: [{
        window: 0,
        document_id: 0,
        state: {
            generation: 0,
            committed_generation: 0,
            has_photo: false,
            opening: false,
            failure_code: 0
        },
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
        history: {
            entries: [{
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
                texture_percent: 0,
                crop_left: 0,
                crop_top: 0,
                crop_width: 0,
                crop_height: 0,
                straighten_millidegrees: 0,
                transform_code: 1,
                hsl: {
                    version: 1,
                    words: [0x6464646464646464] ** 3
                },
                curve: [250, 500, 750, 250, 500, 750, 250, 500, 750, 250, 500, 750],
                grade: [0] ** 20
            }] ** 32,
            length: 0,
            cursor: 0
        },
        pending_history_cursor: -1,
        pending_geometry: false,
        pending_geometry_values: {
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
            texture_percent: 0,
            crop_left: 0,
            crop_top: 0,
            crop_width: 0,
            crop_height: 0,
            straighten_millidegrees: 0,
            transform_code: 1,
            hsl: {
                version: 1,
                words: [0x6464646464646464] ** 3
            },
            curve: [250, 500, 750, 250, 500, 750, 250, 500, 750, 250, 500, 750],
            grade: [0] ** 20
        },
        pending_project_history: {
            entries: [{
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
                texture_percent: 0,
                crop_left: 0,
                crop_top: 0,
                crop_width: 0,
                crop_height: 0,
                straighten_millidegrees: 0,
                transform_code: 1,
                hsl: {
                    version: 1,
                    words: [0x6464646464646464] ** 3
                },
                curve: [250, 500, 750, 250, 500, 750, 250, 500, 750, 250, 500, 750],
                grade: [0] ** 20
            }] ** 32,
            length: 0,
            cursor: 0
        },
        restoring_project: false,
        project_ready: false,
        pending_project_revision: 0,
        pending_project_count: 0,
        project_status: 0 // ProjectSaveStatus.idle; top-level initializer requires literals.
    }] ** 16
};
var next_document_id: u32 = 0;

fn current_window(): i64 {
    const window = current() catch (error) {
        return 0;
    };
    return raw_handle(window) as i64;
}

fn state_for(window: i64): document_state.DocumentState {
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        return documents.slots[index].state;
    }
    return document_state.empty();
}

// @neiv-callback
pub fn is_open_generation(window: i64, generation: u32): i32 {
    const state = state_for(window);
    if state.opening and state.generation == generation as u32 {
        return 1;
    }
    return 0;
}

// @neiv-callback
pub fn close_document(window: i64): void {
    lock_documents();
    document_registry.release(&documents, window);
    unlock_documents();
}

// @neiv-callback
pub fn stage_project_entry(window: i64, generation: u32, index: u32, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32, crop_left: i32, crop_top: i32, crop_width: i32, crop_height: i32, straighten_millidegrees: i32, transform_code: i32): i32 {
    if index >= 32 {
        return 0;
    }
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is slot_index {
        var slot = documents.slots[slot_index];
        if slot.state.opening and slot.state.generation == generation and slot.restoring_project and not slot.project_ready and index == slot.pending_project_count {
            slot.pending_project_history.entries[index as usize] = {
                exposure_tenths: exposure_tenths,
                contrast_percent: contrast_percent,
                shadows_percent: shadows_percent,
                highlights_percent: highlights_percent,
                blacks_percent: blacks_percent,
                whites_percent: whites_percent,
                warmth_percent: warmth_percent,
                tint_percent: tint_percent,
                vibrance_percent: vibrance_percent,
                saturation_percent: saturation_percent,
                clarity_percent: clarity_percent,
                texture_percent: texture_percent,
                crop_left: crop_left,
                crop_top: crop_top,
                crop_width: crop_width,
                crop_height: crop_height,
                straighten_millidegrees: straighten_millidegrees,
                transform_code: transform_code,
                hsl: develop_history.neutral().hsl,
                curve: develop_history.neutral_curve(),
                grade: [0] ** 20
            };
            slot.pending_project_count = slot.pending_project_count + 1;
            documents.slots[slot_index] = slot;
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn stage_project_hsl(window: i64, generation: u32, index: u32, band: u32, hue: i32, saturation: i32, luminance: i32): i32 {
    if index >= 32 or band >= 8 {
        return 0;
    }
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is slot_index {
        var slot = documents.slots[slot_index];
        if slot.state.opening and slot.state.generation == generation and
        slot.restoring_project and not slot.project_ready and
        index < slot.pending_project_count {
            var values = slot.pending_project_history.entries[index as usize];
            const first = develop_history.with_hsl_percent(values.hsl, 0, band as usize, hue);
            if first is none {
                return 0;
            }
            const second = develop_history.with_hsl_percent(first, 1, band as usize, saturation);
            if second is none {
                return 0;
            }
            const third = develop_history.with_hsl_percent(second, 2, band as usize, luminance);
            if third is none {
                return 0;
            }
            values.hsl = third;
            slot.pending_project_history.entries[index as usize] = values;
            documents.slots[slot_index] = slot;
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn stage_project_curve(window: i64, generation: u32, index: u32, channel: u32, shadow: i32, middle: i32, highlight: i32): i32 {
    if index >= 32 or channel >= 4 {
        return 0;
    }
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is slot_index {
        var slot = documents.slots[slot_index];
        if slot.state.opening and slot.state.generation == generation and
        slot.restoring_project and not slot.project_ready and
        index < slot.pending_project_count {
            var values = slot.pending_project_history.entries[index as usize];
            values.curve[channel as usize * 3] = shadow;
            values.curve[channel as usize * 3 + 1] = middle;
            values.curve[channel as usize * 3 + 2] = highlight;
            if not develop_history.valid_curve(values.curve) {
                return 0;
            }
            slot.pending_project_history.entries[index as usize] = values;
            documents.slots[slot_index] = slot;
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn stage_grade(w: i64, g: u32, i: u32, f: u32, v: i32): i32 {
    if i >= 32 or f >= 20 {
        return 0;
    }
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, w) is slot_index {
        var slot = documents.slots[slot_index];
        if slot.state.opening and slot.state.generation == g and
        slot.restoring_project and not slot.project_ready and
        i < slot.pending_project_count {
            var values = slot.pending_project_history.entries[i as usize];
            values.grade[f as usize] = v;
            if not develop_history.valid_grade(values.grade) {
                return 0;
            }
            slot.pending_project_history.entries[i as usize] = values;
            documents.slots[slot_index] = slot;
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn finish_project_entries(window: i64, generation: u32, length: u32, cursor: u32, revision: u32): i32 {
    if length == 0 or length > 32 or cursor >= length or revision < cursor {
        return 0;
    }
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        var slot = documents.slots[index];
        if slot.state.opening and slot.state.generation == generation and slot.restoring_project and not slot.project_ready and length == slot.pending_project_count {
            slot.pending_project_history.length = length as usize;
            slot.pending_project_history.cursor = cursor as usize;
            if not develop_history.valid(&slot.pending_project_history) {
                return 0;
            }
            const values = slot.pending_project_history.entries[cursor as usize];
            slot.pending_exposure_tenths = values.exposure_tenths;
            slot.pending_contrast_percent = values.contrast_percent;
            slot.pending_shadows_percent = values.shadows_percent;
            slot.pending_highlights_percent = values.highlights_percent;
            slot.pending_blacks_percent = values.blacks_percent;
            slot.pending_whites_percent = values.whites_percent;
            slot.pending_warmth_percent = values.warmth_percent;
            slot.pending_tint_percent = values.tint_percent;
            slot.pending_vibrance_percent = values.vibrance_percent;
            slot.pending_saturation_percent = values.saturation_percent;
            slot.pending_clarity_percent = values.clarity_percent;
            slot.pending_texture_percent = values.texture_percent;
            slot.pending_project_revision = revision;
            slot.project_ready = true;
            documents.slots[index] = slot;
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn complete_project_save(window: i64, generation: u32, status: u32): void {
    lock_documents();
    if document_registry.find(&documents, window) is index {
        var slot = documents.slots[index];
        if slot.state.committed_generation == generation and slot.project_status == ProjectSaveStatus.saving as u32 {
            slot.project_status = document_state.completed_save_status(status) as u32;
            documents.slots[index] = slot;
        }
    }
    unlock_documents();
}

// @neiv-callback
pub fn can_save_project(window: i64, generation: u32): i32 {
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and not slot.state.opening and slot.state.committed_generation == generation and slot.project_status == ProjectSaveStatus.saving as u32 {
            return 1;
        }
    }
    return 0;
}

// @neiv-callback
pub fn complete_open(window: i64, generation: u32, status: i32): void {
    lock_documents();
    if document_registry.find(&documents, window) is index {
        const state = documents.slots[index].state;
        if state.opening and state.generation == generation as u32 {
            var slot = documents.slots[index];
            var completion_status = status;
            var commit_status: i32 = 7;
            if status == 0 {
                if (not slot.restoring_project or slot.project_ready) and (slot.pending_edit or next_document_id < 4294967295) {
                    commit_status = commit_frame(window, generation);
                } else {
                    completion_status = 3;
                    if slot.restoring_project and not slot.project_ready {
                        completion_status = 9;
                    }
                }
            }
            if completion_status == 0 and commit_status != 0 and commit_status != 1 {
                completion_status = 5;
            }
            if completion_status == 0 {
                slot.state = document_state.finish_open(state, generation as u32, 0);
                slot.exposure_tenths = slot.pending_exposure_tenths;
                slot.contrast_percent = slot.pending_contrast_percent;
                slot.shadows_percent = slot.pending_shadows_percent;
                slot.highlights_percent = slot.pending_highlights_percent;
                slot.blacks_percent = slot.pending_blacks_percent;
                slot.whites_percent = slot.pending_whites_percent;
                slot.warmth_percent = slot.pending_warmth_percent;
                slot.tint_percent = slot.pending_tint_percent;
                slot.vibrance_percent = slot.pending_vibrance_percent;
                slot.saturation_percent = slot.pending_saturation_percent;
                slot.clarity_percent = slot.pending_clarity_percent;
                slot.texture_percent = slot.pending_texture_percent;
                slot.exposure_available = commit_status == 0;
                if not slot.pending_edit {
                    next_document_id = next_document_id + 1;
                    slot.document_id = next_document_id;
                }
                if slot.restoring_project {
                    slot.history = slot.pending_project_history;
                    slot.edit_revision = slot.pending_project_revision;
                } else if slot.pending_edit {
                    if slot.pending_history_cursor >= 0 {
                        slot.history.cursor = slot.pending_history_cursor as usize;
                    } else {
                        var prior_geometry = slot.history.entries[slot.history.cursor];
                        if slot.pending_geometry {
                            prior_geometry = slot.pending_geometry_values;
                        }
                        develop_history.append(&slot.history, {
                            exposure_tenths: slot.exposure_tenths,
                            contrast_percent: slot.contrast_percent,
                            shadows_percent: slot.shadows_percent,
                            highlights_percent: slot.highlights_percent,
                            blacks_percent: slot.blacks_percent,
                            whites_percent: slot.whites_percent,
                            warmth_percent: slot.warmth_percent,
                            tint_percent: slot.tint_percent,
                            vibrance_percent: slot.vibrance_percent,
                            saturation_percent: slot.saturation_percent,
                            clarity_percent: slot.clarity_percent,
                            texture_percent: slot.texture_percent,
                            crop_left: prior_geometry.crop_left,
                            crop_top: prior_geometry.crop_top,
                            crop_width: prior_geometry.crop_width,
                            crop_height: prior_geometry.crop_height,
                            straighten_millidegrees: prior_geometry.straighten_millidegrees,
                            transform_code: prior_geometry.transform_code,
                            hsl: prior_geometry.hsl,
                            curve: prior_geometry.curve,
                            grade: prior_geometry.grade
                        });
                    }
                    if slot.edit_revision < 4294967295 {
                        slot.edit_revision = slot.edit_revision + 1;
                    }
                } else {
                    develop_history.reset(&slot.history);
                    slot.edit_revision = 0;
                }
            } else {
                slot.state = document_state.finish_open(state, generation as u32, completion_status as u32);
            }
            slot.pending_edit = false;
            slot.pending_history_cursor = -1;
            slot.pending_geometry = false;
            slot.restoring_project = false;
            slot.project_ready = false;
            documents.slots[index] = slot;
        }
    }
    discard_candidate(window, generation);
    unlock_documents();
}

// @neiv-configure
pub fn configure(): void {
    const configured = configure_window("Lightcept", 1200, 800);
}

// @neiv {"returns":"boolean"}
pub fn new_window(): i32 {
    const opened = open("Lightcept", 1200, 800) catch (error) {
        return 0;
    };
    const ignored = opened;
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn has_photo(): i32 {
    if state_for(current_window()).has_photo {
        return 1;
    }
    return 0;
}

// @neiv {"returns":"boolean"}
pub fn set_preview_display(comparison_mode: i32, proof_profile: i32): i32 {
    const window = current_window();
    if not state_for(window).has_photo or not valid_preview_display(comparison_mode, proof_profile) {
        return 0;
    }
    if set_comparison(window, comparison_mode, proof_profile) {
        return 1;
    }
    return 0;
}

fn valid_preview_display(comparison_mode: i32, proof_profile: i32): bool {
    return comparison_mode >= PreviewComparison.after as i32 and comparison_mode <= PreviewComparison.split as i32
    and proof_profile >= ProofProfile.off as i32 and proof_profile <= ProofProfile.monitor as i32;
}

// @neiv {"returns":"boolean"}
pub fn set_preview_zoom(percent: i32): i32 {
    const window = current_window();
    if not state_for(window).has_photo {
        return 0;
    }
    if set_zoom(window, percent) {
        return 1;
    }
    return 0;
}

// @neiv
pub fn document_phase(): i32 {
    return document_state.snapshot(state_for(current_window())).phase as i32;
}

// @neiv {"returns":{"type":"record","fields":{"documentId":{"type":"number","min":0,"max":4294967295},"generation":{"type":"number","min":0,"max":4294967295},"committedGeneration":{"type":"number","min":0,"max":4294967295},"previewWidth":{"type":"number","min":0,"max":2048},"previewHeight":{"type":"number","min":0,"max":2048},"phase":{"type":"number","min":0,"max":3},"hasPhoto":"boolean","sourceName":{"type":"string","maxBytes":255},"failureCode":{"type":"number","min":0,"max":11},"exposureTenths":{"type":"number","min":-160,"max":160},"contrastPercent":{"type":"number","min":-100,"max":100},"shadowsPercent":{"type":"number","min":-100,"max":100},"highlightsPercent":{"type":"number","min":-100,"max":100},"blacksPercent":{"type":"number","min":-100,"max":100},"whitesPercent":{"type":"number","min":-100,"max":100},"warmthPercent":{"type":"number","min":-100,"max":100},"tintPercent":{"type":"number","min":-100,"max":100},"vibrancePercent":{"type":"number","min":-100,"max":100},"saturationPercent":{"type":"number","min":-100,"max":100},"clarityPercent":{"type":"number","min":-100,"max":100},"texturePercent":{"type":"number","min":-100,"max":100},"exposureAvailable":"boolean","editRevision":{"type":"number","min":0,"max":4294967295},"canUndo":"boolean","canRedo":"boolean","historyLength":{"type":"number","min":0,"max":32},"historyCursor":{"type":"number","min":0,"max":31},"projectStatus":{"type":"number","min":0,"max":5}}}}
pub fn document_snapshot(): string {
    const window = current_window();
    lock_documents();
    var current_state = document_state.empty();
    var document_id: u32 = 0;
    var exposure_tenths: i32 = 0;
    var contrast_percent: i32 = 0;
    var shadows_percent: i32 = 0;
    var highlights_percent: i32 = 0;
    var blacks_percent: i32 = 0;
    var whites_percent: i32 = 0;
    var warmth_percent: i32 = 0;
    var tint_percent: i32 = 0;
    var vibrance_percent: i32 = 0;
    var saturation_percent: i32 = 0;
    var clarity_percent: i32 = 0;
    var texture_percent: i32 = 0;
    var exposure_available = false;
    var edit_revision: u32 = 0;
    var can_undo = false;
    var can_redo = false;
    var project_status: u32 = 0;
    var history_length: u32 = 0;
    var history_cursor: u32 = 0;
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        current_state = slot.state;
        document_id = slot.document_id;
        exposure_tenths = slot.exposure_tenths;
        contrast_percent = slot.contrast_percent;
        shadows_percent = slot.shadows_percent;
        highlights_percent = slot.highlights_percent;
        blacks_percent = slot.blacks_percent;
        whites_percent = slot.whites_percent;
        warmth_percent = slot.warmth_percent;
        tint_percent = slot.tint_percent;
        vibrance_percent = slot.vibrance_percent;
        saturation_percent = slot.saturation_percent;
        clarity_percent = slot.clarity_percent;
        texture_percent = slot.texture_percent;
        exposure_available = slot.exposure_available;
        edit_revision = slot.edit_revision;
        can_undo = develop_history.can_undo(&slot.history);
        can_redo = develop_history.can_redo(&slot.history);
        project_status = slot.project_status;
        history_length = slot.history.length as u32;
        history_cursor = slot.history.cursor as u32;
    }
    unlock_documents();
    const state = document_state.snapshot(current_state);
    const values = SnapshotValues {
        window: window,
        document_id: document_id,
        generation: state.generation,
        committed: state.committed_generation,
        phase: document_state.phase_kind(current_state),
        has_photo: state.has_photo,
        failure: document_state.open_status(state.failure_code),
        exposure_tenths: exposure_tenths,
        contrast_percent: contrast_percent,
        shadows_percent: shadows_percent,
        highlights_percent: highlights_percent,
        blacks_percent: blacks_percent,
        whites_percent: whites_percent,
        warmth_percent: warmth_percent,
        tint_percent: tint_percent,
        vibrance_percent: vibrance_percent,
        saturation_percent: saturation_percent,
        clarity_percent: clarity_percent,
        texture_percent: texture_percent,
        exposure_available: exposure_available,
        edit_revision: edit_revision,
        can_undo: can_undo,
        can_redo: can_redo,
        history_length: history_length,
        history_cursor: history_cursor,
        project_status: document_state.project_save_status(project_status)
    };
    return snapshot_text(values);
}

// @neiv {"returns":"boolean"}
pub fn show_preview(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var old: i64 = 0;
    var committed: u32 = 0;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.has_photo {
            old = documents.slots[index].preview;
            committed = documents.slots[index].state.committed_generation;
        }
    }
    unlock_documents();
    if committed == 0 {
        return 0;
    }
    if old != 0 and surface_alive(old) == 1 {
        return 1;
    }
    const surface = create_preview(window);
    if surface <= 0 {
        return 0;
    }
    lock_documents();
    var accepted = false;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.committed_generation == committed {
            var slot = documents.slots[index];
            slot.preview = surface;
            documents.slots[index] = slot;
            accepted = true;
        }
    }
    unlock_documents();
    if not accepted {
        const discarded = destroy_surface(surface);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn show_navigator_preview(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var old: i64 = 0;
    var committed: u32 = 0;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.has_photo {
            old = documents.slots[index].navigator_preview;
            committed = documents.slots[index].state.committed_generation;
        }
    }
    unlock_documents();
    if committed == 0 {
        return 0;
    }
    if old != 0 and surface_alive(old) == 1 {
        return 1;
    }
    const surface = create_navigator_preview(window);
    if surface <= 0 {
        return 0;
    }
    lock_documents();
    var accepted = false;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.committed_generation == committed {
            var slot = documents.slots[index];
            slot.navigator_preview = surface;
            documents.slots[index] = slot;
            accepted = true;
        }
    }
    unlock_documents();
    if not accepted {
        const discarded = destroy_surface(surface);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn show_filmstrip_preview(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var old: i64 = 0;
    var committed: u32 = 0;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.has_photo {
            old = documents.slots[index].filmstrip_preview;
            committed = documents.slots[index].state.committed_generation;
        }
    }
    unlock_documents();
    if committed == 0 {
        return 0;
    }
    if old != 0 and surface_alive(old) == 1 {
        return 1;
    }
    const surface = create_filmstrip_preview(window);
    if surface <= 0 {
        return 0;
    }
    lock_documents();
    var accepted = false;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.committed_generation == committed {
            var slot = documents.slots[index];
            slot.filmstrip_preview = surface;
            documents.slots[index] = slot;
            accepted = true;
        }
    }
    unlock_documents();
    if not accepted {
        const discarded = destroy_surface(surface);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn show_histogram(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var old: i64 = 0;
    var committed: u32 = 0;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.has_photo {
            old = documents.slots[index].histogram_preview;
            committed = documents.slots[index].state.committed_generation;
        }
    }
    unlock_documents();
    if committed == 0 {
        return 0;
    }
    if old != 0 and surface_alive(old) == 1 {
        return 1;
    }
    const surface = create_histogram(window);
    if surface <= 0 {
        return 0;
    }
    lock_documents();
    var accepted = false;
    if document_registry.find(&documents, window) is index {
        if documents.slots[index].state.committed_generation == committed {
            var slot = documents.slots[index];
            slot.histogram_preview = surface;
            documents.slots[index] = slot;
            accepted = true;
        }
    }
    unlock_documents();
    if not accepted {
        const discarded = destroy_surface(surface);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn open_photo(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    if document_registry.ensure(&documents, window) is index {
        const started = document_state.begin_open(documents.slots[index].state);
        if started is opening {
            var slot = documents.slots[index];
            slot.state = opening;
            slot.pending_exposure_tenths = 0;
            slot.pending_contrast_percent = 0;
            slot.pending_shadows_percent = 0;
            slot.pending_highlights_percent = 0;
            slot.pending_blacks_percent = 0;
            slot.pending_whites_percent = 0;
            slot.pending_warmth_percent = 0;
            slot.pending_tint_percent = 0;
            slot.pending_vibrance_percent = 0;
            slot.pending_saturation_percent = 0;
            slot.pending_clarity_percent = 0;
            slot.pending_texture_percent = 0;
            slot.pending_edit = false;
            slot.pending_history_cursor = -1;
            slot.restoring_project = false;
            slot.project_ready = false;
            slot.project_status = ProjectSaveStatus.idle as u32;
            documents.slots[index] = slot;
            generation = opening.generation;
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    if select_photo(window, generation as u32) != 0 {
        complete_open(window, generation as u32, 5);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn open_project(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    if document_registry.ensure(&documents, window) is index {
        const started = document_state.begin_open(documents.slots[index].state);
        if started is opening {
            var slot = documents.slots[index];
            slot.state = opening;
            slot.pending_project_history = develop_history.empty();
            slot.pending_project_count = 0;
            slot.pending_project_revision = 0;
            slot.restoring_project = true;
            slot.project_ready = false;
            slot.pending_edit = false;
            slot.project_status = ProjectSaveStatus.idle as u32;
            documents.slots[index] = slot;
            generation = opening.generation;
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    if select_project(window, generation) != 0 {
        complete_open(window, generation, 10);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn save_project(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var history = develop_history.empty();
    var generation: u32 = 0;
    var revision: u32 = 0;
    if document_registry.find(&documents, window) is index {
        var slot = documents.slots[index];
        if slot.state.has_photo and not slot.state.opening and slot.exposure_available and slot.project_status != ProjectSaveStatus.saving as u32 and develop_history.valid(&slot.history) {
            history = slot.history;
            generation = slot.state.committed_generation;
            revision = slot.edit_revision;
            slot.project_status = ProjectSaveStatus.saving as u32;
            documents.slots[index] = slot;
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    // Cyna fixed array lengths require a literal: 32 history entries × 74 fields.
    var flattened: [2368]i32 = [0] ** 2368;
    var index: usize = 0;
    while index < history.length {
        const values = history.entries[index];
        flattened[index * ProjectField.count as usize + ProjectField.exposure as usize] = values.exposure_tenths;
        flattened[index * ProjectField.count as usize + ProjectField.contrast as usize] = values.contrast_percent;
        flattened[index * ProjectField.count as usize + ProjectField.shadows as usize] = values.shadows_percent;
        flattened[index * ProjectField.count as usize + ProjectField.highlights as usize] = values.highlights_percent;
        flattened[index * ProjectField.count as usize + ProjectField.blacks as usize] = values.blacks_percent;
        flattened[index * ProjectField.count as usize + ProjectField.whites as usize] = values.whites_percent;
        flattened[index * ProjectField.count as usize + ProjectField.warmth as usize] = values.warmth_percent;
        flattened[index * ProjectField.count as usize + ProjectField.tint as usize] = values.tint_percent;
        flattened[index * ProjectField.count as usize + ProjectField.vibrance as usize] = values.vibrance_percent;
        flattened[index * ProjectField.count as usize + ProjectField.saturation as usize] = values.saturation_percent;
        flattened[index * ProjectField.count as usize + ProjectField.clarity as usize] = values.clarity_percent;
        flattened[index * ProjectField.count as usize + ProjectField.texture as usize] = values.texture_percent;
        flattened[index * ProjectField.count as usize + ProjectField.crop_left as usize] = values.crop_left;
        flattened[index * ProjectField.count as usize + ProjectField.crop_top as usize] = values.crop_top;
        flattened[index * ProjectField.count as usize + ProjectField.crop_width as usize] = values.crop_width;
        flattened[index * ProjectField.count as usize + ProjectField.crop_height as usize] = values.crop_height;
        flattened[index * ProjectField.count as usize + ProjectField.straighten_millidegrees as usize] = values.straighten_millidegrees;
        flattened[index * ProjectField.count as usize + ProjectField.transform_code as usize] = values.transform_code;
        var kind: usize = 0;
        while kind < 3 {
            var band: usize = 0;
            while band < 8 {
                flattened[index * ProjectField.count as usize + 18 + kind * 8 + band] = develop_history.hsl_percent(values.hsl, kind, band);
                band = band + 1;
            }
            kind = kind + 1;
        }
        var curve_index: usize = 0;
        while curve_index < 12 {
            flattened[index * ProjectField.count as usize + 42 + curve_index] =
            values.curve[curve_index];
            curve_index = curve_index + 1;
        }
        var grade_index: usize = 0;
        while grade_index < 20 {
            flattened[index * ProjectField.count as usize + 54 + grade_index] =
            values.grade[grade_index];
            grade_index = grade_index + 1;
        }
        index = index + 1;
    }
    if save_project_native(window, generation, flattened[0..].ptr, history.length as u32, history.cursor as u32, revision) != 0 {
        complete_project_save(window, generation, 4);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn export_tiff(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    var values: [18]i32 = [0] ** 18;
    var generation: u32 = 0;
    lock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and not slot.state.opening and slot.exposure_available and not slot.pending_edit {
            generation = slot.state.committed_generation;
            const selected = slot.history.entries[slot.history.cursor];
            values = [slot.exposure_tenths, slot.contrast_percent,
                slot.shadows_percent, slot.highlights_percent,
                slot.blacks_percent, slot.whites_percent, slot.warmth_percent,
                slot.tint_percent, slot.vibrance_percent,
                slot.saturation_percent, slot.clarity_percent,
                slot.texture_percent, selected.crop_left, selected.crop_top,
                selected.crop_width, selected.crop_height,
                selected.straighten_millidegrees, selected.transform_code
            ];
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    if export_tiff_native(window, generation, values[0..].ptr) != 0 {
        return 0;
    }
    return 1;
}

// @neiv {"returns":"int32"}
pub fn export_status(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    return export_status_native(window);
}

// @neiv {"returns":"boolean"}
pub fn cancel_export(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    cancel_export_native(window);
    return 1;
}

// @neiv {"returns":"boolean","args":{"tenths":{"type":"int32","min":-40,"max":40}}}
pub fn set_exposure(tenths: i32): i32 {
    const window = current_window();
    if window <= 0 or tenths < -40 or tenths > 40 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var contrast_percent: i32 = 0;
    var shadows_percent: i32 = 0;
    var highlights_percent: i32 = 0;
    var blacks_percent: i32 = 0;
    var whites_percent: i32 = 0;
    var warmth_percent: i32 = 0;
    var tint_percent: i32 = 0;
    var vibrance_percent: i32 = 0;
    var saturation_percent: i32 = 0;
    var clarity_percent: i32 = 0;
    var texture_percent: i32 = 0;
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = tenths as i32;
                slot.pending_contrast_percent = current_slot.contrast_percent;
                slot.pending_shadows_percent = current_slot.shadows_percent;
                slot.pending_highlights_percent = current_slot.highlights_percent;
                slot.pending_blacks_percent = current_slot.blacks_percent;
                slot.pending_whites_percent = current_slot.whites_percent;
                slot.pending_warmth_percent = current_slot.warmth_percent;
                slot.pending_tint_percent = current_slot.tint_percent;
                slot.pending_vibrance_percent = current_slot.vibrance_percent;
                slot.pending_saturation_percent = current_slot.saturation_percent;
                slot.pending_clarity_percent = current_slot.clarity_percent;
                slot.pending_texture_percent = current_slot.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                documents.slots[index] = slot;
                generation = opening.generation;
                contrast_percent = current_slot.contrast_percent as i32;
                shadows_percent = current_slot.shadows_percent;
                highlights_percent = current_slot.highlights_percent;
                blacks_percent = current_slot.blacks_percent;
                whites_percent = current_slot.whites_percent;
                warmth_percent = current_slot.warmth_percent;
                tint_percent = current_slot.tint_percent;
                vibrance_percent = current_slot.vibrance_percent;
                saturation_percent = current_slot.saturation_percent;
                clarity_percent = current_slot.clarity_percent;
                texture_percent = current_slot.texture_percent;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation as u32, tenths as i32, contrast_percent, shadows_percent, highlights_percent, blacks_percent, whites_percent, warmth_percent, tint_percent, vibrance_percent, saturation_percent, clarity_percent, texture_percent);
    if scheduled != 0 {
        complete_open(window, generation as u32, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean","args":{"percent":{"type":"int32","min":-100,"max":100}}}
pub fn set_contrast(percent: i32): i32 {
    const window = current_window();
    if window <= 0 or percent < -100 or percent > 100 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var exposure_tenths: i32 = 0;
    var shadows_percent: i32 = 0;
    var highlights_percent: i32 = 0;
    var blacks_percent: i32 = 0;
    var whites_percent: i32 = 0;
    var warmth_percent: i32 = 0;
    var tint_percent: i32 = 0;
    var vibrance_percent: i32 = 0;
    var saturation_percent: i32 = 0;
    var clarity_percent: i32 = 0;
    var texture_percent: i32 = 0;
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = current_slot.exposure_tenths;
                slot.pending_contrast_percent = percent as i32;
                slot.pending_shadows_percent = current_slot.shadows_percent;
                slot.pending_highlights_percent = current_slot.highlights_percent;
                slot.pending_blacks_percent = current_slot.blacks_percent;
                slot.pending_whites_percent = current_slot.whites_percent;
                slot.pending_warmth_percent = current_slot.warmth_percent;
                slot.pending_tint_percent = current_slot.tint_percent;
                slot.pending_vibrance_percent = current_slot.vibrance_percent;
                slot.pending_saturation_percent = current_slot.saturation_percent;
                slot.pending_clarity_percent = current_slot.clarity_percent;
                slot.pending_texture_percent = current_slot.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                documents.slots[index] = slot;
                generation = opening.generation;
                exposure_tenths = current_slot.exposure_tenths as i32;
                shadows_percent = current_slot.shadows_percent;
                highlights_percent = current_slot.highlights_percent;
                blacks_percent = current_slot.blacks_percent;
                whites_percent = current_slot.whites_percent;
                warmth_percent = current_slot.warmth_percent;
                tint_percent = current_slot.tint_percent;
                vibrance_percent = current_slot.vibrance_percent;
                saturation_percent = current_slot.saturation_percent;
                clarity_percent = current_slot.clarity_percent;
                texture_percent = current_slot.texture_percent;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation as u32, exposure_tenths, percent as i32, shadows_percent, highlights_percent, blacks_percent, whites_percent, warmth_percent, tint_percent, vibrance_percent, saturation_percent, clarity_percent, texture_percent);
    if scheduled != 0 {
        complete_open(window, generation as u32, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean","args":{"control":{"type":"int32","min":1,"max":4},"percent":{"type":"int32","min":-100,"max":100}}}
pub fn set_tone(control: i32, percent: i32): i32 {
    const window = current_window();
    if window <= 0 or control < ToneControl.shadows as i32 or control > ToneControl.whites as i32 or percent < -100 or percent > 100 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var exposure_tenths: i32 = 0;
    var contrast_percent: i32 = 0;
    var shadows_percent: i32 = 0;
    var highlights_percent: i32 = 0;
    var blacks_percent: i32 = 0;
    var whites_percent: i32 = 0;
    var warmth_percent: i32 = 0;
    var tint_percent: i32 = 0;
    var vibrance_percent: i32 = 0;
    var saturation_percent: i32 = 0;
    var clarity_percent: i32 = 0;
    var texture_percent: i32 = 0;
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = current_slot.exposure_tenths;
                slot.pending_contrast_percent = current_slot.contrast_percent;
                slot.pending_shadows_percent = current_slot.shadows_percent;
                slot.pending_highlights_percent = current_slot.highlights_percent;
                slot.pending_blacks_percent = current_slot.blacks_percent;
                slot.pending_whites_percent = current_slot.whites_percent;
                slot.pending_warmth_percent = current_slot.warmth_percent;
                slot.pending_tint_percent = current_slot.tint_percent;
                slot.pending_vibrance_percent = current_slot.vibrance_percent;
                slot.pending_saturation_percent = current_slot.saturation_percent;
                slot.pending_clarity_percent = current_slot.clarity_percent;
                slot.pending_texture_percent = current_slot.texture_percent;
                if control == ToneControl.shadows as i32 {
                    slot.pending_shadows_percent = percent;
                } else if control == ToneControl.highlights as i32 {
                    slot.pending_highlights_percent = percent;
                } else if control == ToneControl.blacks as i32 {
                    slot.pending_blacks_percent = percent;
                } else {
                    slot.pending_whites_percent = percent;
                }
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                documents.slots[index] = slot;
                generation = opening.generation;
                exposure_tenths = slot.pending_exposure_tenths;
                contrast_percent = slot.pending_contrast_percent;
                shadows_percent = slot.pending_shadows_percent;
                highlights_percent = slot.pending_highlights_percent;
                blacks_percent = slot.pending_blacks_percent;
                whites_percent = slot.pending_whites_percent;
                warmth_percent = slot.pending_warmth_percent;
                tint_percent = slot.pending_tint_percent;
                vibrance_percent = slot.pending_vibrance_percent;
                saturation_percent = slot.pending_saturation_percent;
                clarity_percent = slot.pending_clarity_percent;
                texture_percent = slot.pending_texture_percent;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, exposure_tenths, contrast_percent, shadows_percent, highlights_percent, blacks_percent, whites_percent, warmth_percent, tint_percent, vibrance_percent, saturation_percent, clarity_percent, texture_percent);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn reset_light(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available and
        (current_slot.exposure_tenths != 0 or current_slot.contrast_percent != 0 or
            current_slot.shadows_percent != 0 or current_slot.highlights_percent != 0 or
            current_slot.blacks_percent != 0 or current_slot.whites_percent != 0
        ) {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = 0;
                slot.pending_contrast_percent = 0;
                slot.pending_shadows_percent = 0;
                slot.pending_highlights_percent = 0;
                slot.pending_blacks_percent = 0;
                slot.pending_whites_percent = 0;
                slot.pending_warmth_percent = slot.warmth_percent;
                slot.pending_tint_percent = slot.tint_percent;
                slot.pending_vibrance_percent = slot.vibrance_percent;
                slot.pending_saturation_percent = slot.saturation_percent;
                slot.pending_clarity_percent = slot.clarity_percent;
                slot.pending_texture_percent = slot.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, 0, 0, 0, 0, 0, 0, current_color_value(window, DevelopControl.warmth as i32), current_color_value(window, DevelopControl.tint as i32), current_color_value(window, DevelopControl.vibrance as i32), current_color_value(window, DevelopControl.saturation as i32), current_color_value(window, DevelopControl.clarity as i32), current_color_value(window, DevelopControl.texture as i32));
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

fn current_color_value(window: i64, control: i32): i32 {
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if control == DevelopControl.warmth as i32 {
            return slot.warmth_percent;
        }
        if control == DevelopControl.tint as i32 {
            return slot.tint_percent;
        }
        if control == DevelopControl.vibrance as i32 {
            return slot.vibrance_percent;
        }
        if control == DevelopControl.saturation as i32 {
            return slot.saturation_percent;
        }
        if control == DevelopControl.clarity as i32 {
            return slot.clarity_percent;
        }
        return slot.texture_percent;
    }
    return 0;
}

// @neiv {"returns":"boolean"}
pub fn set_color(control: i32, percent: i32): i32 {
    if control < DevelopControl.warmth as i32 or control > DevelopControl.saturation as i32 or percent < -100 or percent > 100 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var values = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = slot.exposure_tenths;
                slot.pending_contrast_percent = slot.contrast_percent;
                slot.pending_shadows_percent = slot.shadows_percent;
                slot.pending_highlights_percent = slot.highlights_percent;
                slot.pending_blacks_percent = slot.blacks_percent;
                slot.pending_whites_percent = slot.whites_percent;
                slot.pending_warmth_percent = slot.warmth_percent;
                slot.pending_tint_percent = slot.tint_percent;
                slot.pending_vibrance_percent = slot.vibrance_percent;
                slot.pending_saturation_percent = slot.saturation_percent;
                slot.pending_clarity_percent = slot.clarity_percent;
                slot.pending_texture_percent = slot.texture_percent;
                if control == DevelopControl.warmth as i32 {
                    slot.pending_warmth_percent = percent;
                }
                if control == DevelopControl.tint as i32 {
                    slot.pending_tint_percent = percent;
                }
                if control == DevelopControl.vibrance as i32 {
                    slot.pending_vibrance_percent = percent;
                }
                if control == DevelopControl.saturation as i32 {
                    slot.pending_saturation_percent = percent;
                }
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                values.exposure_tenths = slot.pending_exposure_tenths;
                values.contrast_percent = slot.pending_contrast_percent;
                values.shadows_percent = slot.pending_shadows_percent;
                values.highlights_percent = slot.pending_highlights_percent;
                values.blacks_percent = slot.pending_blacks_percent;
                values.whites_percent = slot.pending_whites_percent;
                values.warmth_percent = slot.pending_warmth_percent;
                values.tint_percent = slot.pending_tint_percent;
                values.vibrance_percent = slot.pending_vibrance_percent;
                values.saturation_percent = slot.pending_saturation_percent;
                values.clarity_percent = slot.pending_clarity_percent;
                values.texture_percent = slot.pending_texture_percent;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, values.warmth_percent, values.tint_percent, values.vibrance_percent, values.saturation_percent, values.clarity_percent, values.texture_percent);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn reset_color(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var values = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available and
        (current_slot.warmth_percent != 0 or current_slot.tint_percent != 0 or current_slot.vibrance_percent != 0 or current_slot.saturation_percent != 0) {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = slot.exposure_tenths;
                slot.pending_contrast_percent = slot.contrast_percent;
                slot.pending_shadows_percent = slot.shadows_percent;
                slot.pending_highlights_percent = slot.highlights_percent;
                slot.pending_blacks_percent = slot.blacks_percent;
                slot.pending_whites_percent = slot.whites_percent;
                slot.pending_warmth_percent = 0;
                slot.pending_tint_percent = 0;
                slot.pending_vibrance_percent = 0;
                slot.pending_saturation_percent = 0;
                slot.pending_clarity_percent = slot.clarity_percent;
                slot.pending_texture_percent = slot.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                values.exposure_tenths = slot.exposure_tenths;
                values.contrast_percent = slot.contrast_percent;
                values.shadows_percent = slot.shadows_percent;
                values.highlights_percent = slot.highlights_percent;
                values.blacks_percent = slot.blacks_percent;
                values.whites_percent = slot.whites_percent;
                values.clarity_percent = slot.clarity_percent;
                values.texture_percent = slot.texture_percent;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, 0, 0, 0, 0, values.clarity_percent, values.texture_percent);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn reset_detail(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var values = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available and
        (current_slot.clarity_percent != 0 or current_slot.texture_percent != 0) {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = slot.exposure_tenths;
                slot.pending_contrast_percent = slot.contrast_percent;
                slot.pending_shadows_percent = slot.shadows_percent;
                slot.pending_highlights_percent = slot.highlights_percent;
                slot.pending_blacks_percent = slot.blacks_percent;
                slot.pending_whites_percent = slot.whites_percent;
                slot.pending_warmth_percent = slot.warmth_percent;
                slot.pending_tint_percent = slot.tint_percent;
                slot.pending_vibrance_percent = slot.vibrance_percent;
                slot.pending_saturation_percent = slot.saturation_percent;
                slot.pending_clarity_percent = 0;
                slot.pending_texture_percent = 0;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                values.exposure_tenths = slot.exposure_tenths;
                values.contrast_percent = slot.contrast_percent;
                values.shadows_percent = slot.shadows_percent;
                values.highlights_percent = slot.highlights_percent;
                values.blacks_percent = slot.blacks_percent;
                values.whites_percent = slot.whites_percent;
                values.warmth_percent = slot.warmth_percent;
                values.tint_percent = slot.tint_percent;
                values.vibrance_percent = slot.vibrance_percent;
                values.saturation_percent = slot.saturation_percent;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, values.warmth_percent, values.tint_percent, values.vibrance_percent, values.saturation_percent, 0, 0);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn set_clarity(percent: i32): i32 {
    if percent < -100 or percent > 100 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var values = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available and current_slot.clarity_percent != percent {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = slot.exposure_tenths;
                slot.pending_contrast_percent = slot.contrast_percent;
                slot.pending_shadows_percent = slot.shadows_percent;
                slot.pending_highlights_percent = slot.highlights_percent;
                slot.pending_blacks_percent = slot.blacks_percent;
                slot.pending_whites_percent = slot.whites_percent;
                slot.pending_warmth_percent = slot.warmth_percent;
                slot.pending_tint_percent = slot.tint_percent;
                slot.pending_vibrance_percent = slot.vibrance_percent;
                slot.pending_saturation_percent = slot.saturation_percent;
                slot.pending_clarity_percent = percent;
                slot.pending_texture_percent = slot.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                values.exposure_tenths = slot.pending_exposure_tenths;
                values.contrast_percent = slot.pending_contrast_percent;
                values.shadows_percent = slot.pending_shadows_percent;
                values.highlights_percent = slot.pending_highlights_percent;
                values.blacks_percent = slot.pending_blacks_percent;
                values.whites_percent = slot.pending_whites_percent;
                values.warmth_percent = slot.pending_warmth_percent;
                values.tint_percent = slot.pending_tint_percent;
                values.vibrance_percent = slot.pending_vibrance_percent;
                values.saturation_percent = slot.pending_saturation_percent;
                values.clarity_percent = slot.pending_clarity_percent;
                values.texture_percent = slot.pending_texture_percent;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, values.warmth_percent, values.tint_percent, values.vibrance_percent, values.saturation_percent, values.clarity_percent, values.texture_percent);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn set_texture(percent: i32): i32 {
    if percent < -100 or percent > 100 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var values = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available and current_slot.texture_percent != percent {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                slot.state = opening;
                slot.pending_exposure_tenths = slot.exposure_tenths;
                slot.pending_contrast_percent = slot.contrast_percent;
                slot.pending_shadows_percent = slot.shadows_percent;
                slot.pending_highlights_percent = slot.highlights_percent;
                slot.pending_blacks_percent = slot.blacks_percent;
                slot.pending_whites_percent = slot.whites_percent;
                slot.pending_warmth_percent = slot.warmth_percent;
                slot.pending_tint_percent = slot.tint_percent;
                slot.pending_vibrance_percent = slot.vibrance_percent;
                slot.pending_saturation_percent = slot.saturation_percent;
                slot.pending_clarity_percent = slot.clarity_percent;
                slot.pending_texture_percent = percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = -1;
                values.exposure_tenths = slot.pending_exposure_tenths;
                values.contrast_percent = slot.pending_contrast_percent;
                values.shadows_percent = slot.pending_shadows_percent;
                values.highlights_percent = slot.pending_highlights_percent;
                values.blacks_percent = slot.pending_blacks_percent;
                values.whites_percent = slot.pending_whites_percent;
                values.warmth_percent = slot.pending_warmth_percent;
                values.tint_percent = slot.pending_tint_percent;
                values.vibrance_percent = slot.pending_vibrance_percent;
                values.saturation_percent = slot.pending_saturation_percent;
                values.clarity_percent = slot.pending_clarity_percent;
                values.texture_percent = slot.pending_texture_percent;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const scheduled = rerender_develop(window, generation, values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, values.warmth_percent, values.tint_percent, values.vibrance_percent, values.saturation_percent, values.clarity_percent, values.texture_percent);
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn reset_clarity(): i32 {
    return set_clarity(0);
}

// @neiv {"args":{"enabled":{"type":"int32","min":0,"max":1}},"returns":"boolean"}
pub fn set_crop_tool(enabled: i32): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    return set_crop_mode(window, enabled != 0);
}

// @neiv {"args":{"enabled":{"type":"int32","min":0,"max":1}},"returns":"boolean"}
pub fn pick_color_from_photo(enabled: i32): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    return set_color_pick_mode(window, enabled != 0);
}

// @neiv {"args":{"on":{"type":"int32","min":0,"max":1},"hue":{"type":"int32","min":0,"max":359},"span":{"type":"int32","min":2,"max":90},"soft":{"type":"int32","min":1,"max":100}},"returns":"boolean"}
pub fn show_pick_mask(on: i32, hue: i32, span: i32, soft: i32): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    return show_color_selection(window, on != 0, hue, span, soft);
}

// @neiv {"args":{"preset":{"type":"int32","min":0,"max":4}},"returns":"boolean"}
pub fn set_crop_ratio(preset: i32): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    return set_crop_aspect(window, preset);
}

fn history_request(target: develop_history.Values): [74]i32 {
    var result: [74]i32 = [0] ** 74;
    result[0] = target.exposure_tenths;
    result[1] = target.contrast_percent;
    result[2] = target.shadows_percent;
    result[3] = target.highlights_percent;
    result[4] = target.blacks_percent;
    result[5] = target.whites_percent;
    result[6] = target.warmth_percent;
    result[7] = target.tint_percent;
    result[8] = target.vibrance_percent;
    result[9] = target.saturation_percent;
    result[10] = target.clarity_percent;
    result[11] = target.texture_percent;
    result[12] = target.crop_left;
    result[13] = target.crop_top;
    result[14] = target.crop_width;
    result[15] = target.crop_height;
    result[16] = target.straighten_millidegrees;
    result[17] = target.transform_code;
    var kind: usize = 0;
    while kind < 3 {
        var band: usize = 0;
        while band < 8 {
            result[18 + kind * 8 + band] = develop_history.hsl_percent(target.hsl, kind, band);
            band = band + 1;
        }
        kind = kind + 1;
    }
    var curve_index: usize = 0;
    while curve_index < 12 {
        result[42 + curve_index] = target.curve[curve_index];
        curve_index = curve_index + 1;
    }
    var grade_index: usize = 0;
    while grade_index < 20 {
        result[54 + grade_index] = target.grade[grade_index];
        grade_index = grade_index + 1;
    }
    return result;
}

fn history_request_length(target: develop_history.Values): usize {
    if develop_history.nonneutral_picked(target.grade) {
        return 74;
    }
    if develop_history.nonneutral_grade(target.grade) {
        return 67;
    }
    if develop_history.nonneutral_curve(target.curve) {
        return 54;
    }
    if develop_history.nonneutral_hsl(target.hsl) {
        return 42;
    }
    return 18;
}

// Accept an edit while an older preview is running. Each request names a new
// generation; the worker for the older generation cannot publish its result.
// Family 0 is a develop control, 1 HSL, 2 curve, 3 grading, 4 a wheel,
// and 5 a photo-picked color.
// The target is always assembled from the latest pending values, so edits to
// different controls made before a render completes are applied together.
// @neiv {"args":{"family":{"type":"int32","min":0,"max":5},"index":{"type":"int32","min":0,"max":23},"value":{"type":"int32","min":-100,"max":1000},"other":{"type":"int32","min":-100,"max":359}},"returns":"boolean"}
pub fn set_adjustment(family: i32, index: i32, value: i32, other: i32): i32 {
    const window = current_window();
    if window <= 0 or family < 0 or family > 5 or index < 0 or index > 23 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is slot_index {
        const current_slot = documents.slots[slot_index];
        if current_slot.state.has_photo and current_slot.exposure_available and
        develop_history.valid(&current_slot.history) and
        (not current_slot.state.opening or current_slot.pending_edit) {
            target = current_slot.history.entries[current_slot.history.cursor];
            if current_slot.state.opening {
                if current_slot.pending_geometry {
                    target = current_slot.pending_geometry_values;
                }
                target.exposure_tenths = current_slot.pending_exposure_tenths;
                target.contrast_percent = current_slot.pending_contrast_percent;
                target.shadows_percent = current_slot.pending_shadows_percent;
                target.highlights_percent = current_slot.pending_highlights_percent;
                target.blacks_percent = current_slot.pending_blacks_percent;
                target.whites_percent = current_slot.pending_whites_percent;
                target.warmth_percent = current_slot.pending_warmth_percent;
                target.tint_percent = current_slot.pending_tint_percent;
                target.vibrance_percent = current_slot.pending_vibrance_percent;
                target.saturation_percent = current_slot.pending_saturation_percent;
                target.clarity_percent = current_slot.pending_clarity_percent;
                target.texture_percent = current_slot.pending_texture_percent;
            }
            var valid = true;
            if family == 0 {
                if index > 11 or (index == 0 and (value < -40 or value > 40)) or
                (index != 0 and (value < -100 or value > 100)) {
                    valid = false;
                } else {
                    if index == 0 {
                        target.exposure_tenths = value;
                    }
                    if index == 1 {
                        target.contrast_percent = value;
                    }
                    if index == 2 {
                        target.shadows_percent = value;
                    }
                    if index == 3 {
                        target.highlights_percent = value;
                    }
                    if index == 4 {
                        target.blacks_percent = value;
                    }
                    if index == 5 {
                        target.whites_percent = value;
                    }
                    if index == 6 {
                        target.warmth_percent = value;
                    }
                    if index == 7 {
                        target.tint_percent = value;
                    }
                    if index == 8 {
                        target.vibrance_percent = value;
                    }
                    if index == 9 {
                        target.saturation_percent = value;
                    }
                    if index == 10 {
                        target.clarity_percent = value;
                    }
                    if index == 11 {
                        target.texture_percent = value;
                    }
                }
            } else if family == 1 {
                if index >= 24 or value < -100 or value > 100 {
                    valid = false;
                } else if develop_history.with_hsl_percent(target.hsl,
                    (index / 8) as usize, (index % 8) as usize, value
                ) is changed {
                    target.hsl = changed;
                } else {
                    valid = false;
                }
            } else if family == 2 {
                if index >= 12 or value < 0 or value > 1000 {
                    valid = false;
                } else {
                    target.curve[index as usize] = value;
                    valid = develop_history.valid_curve(target.curve);
                }
            } else if family == 3 {
                if index >= 20 {
                    valid = false;
                } else {
                    target.grade[index as usize] = value;
                    valid = develop_history.valid_grade(target.grade);
                }
            } else if family == 4 {
                if index >= 4 or value < 0 or value > 359 or other < 0 or other > 100 {
                    valid = false;
                } else {
                    target.grade[(index * 3) as usize] = value;
                    target.grade[(index * 3 + 1) as usize] = other;
                    valid = develop_history.valid_grade(target.grade);
                }
            } else {
                if value < 0 or value > 359 {
                    valid = false;
                } else {
                    target.grade[13] = value;
                    target.grade[19] = 1;
                    valid = develop_history.valid_grade(target.grade);
                }
            }
            if valid {
                if document_state.begin_open(current_slot.state) is opening {
                    var slot = current_slot;
                    slot.state = opening;
                    slot.pending_exposure_tenths = target.exposure_tenths;
                    slot.pending_contrast_percent = target.contrast_percent;
                    slot.pending_shadows_percent = target.shadows_percent;
                    slot.pending_highlights_percent = target.highlights_percent;
                    slot.pending_blacks_percent = target.blacks_percent;
                    slot.pending_whites_percent = target.whites_percent;
                    slot.pending_warmth_percent = target.warmth_percent;
                    slot.pending_tint_percent = target.tint_percent;
                    slot.pending_vibrance_percent = target.vibrance_percent;
                    slot.pending_saturation_percent = target.saturation_percent;
                    slot.pending_clarity_percent = target.clarity_percent;
                    slot.pending_texture_percent = target.texture_percent;
                    slot.pending_edit = true;
                    slot.pending_history_cursor = -1;
                    slot.pending_geometry = true;
                    slot.pending_geometry_values = target;
                    documents.slots[slot_index] = slot;
                    generation = opening.generation;
                }
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    var scheduled: i32 = 0;
    if history_request_length(target) == 18 and target.crop_width == 0 and
    target.crop_height == 0 and target.straighten_millidegrees == 0 and
    target.transform_code == 1 {
        scheduled = rerender_develop(window, generation, target.exposure_tenths,
            target.contrast_percent, target.shadows_percent, target.highlights_percent,
            target.blacks_percent, target.whites_percent, target.warmth_percent,
            target.tint_percent, target.vibrance_percent, target.saturation_percent,
            target.clarity_percent, target.texture_percent
        );
    } else {
        const values = history_request(target);
        scheduled = rerender_history(window, generation, values[0..].ptr,
            history_request_length(target)
        );
    }
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

fn commit_geometry_values(left: i32, top: i32, width: i32, height: i32,
    angle_millidegrees: i32, transform_code: i32
): i32 {
    const window = current_window();
    if window <= 0 or left < 0 or top < 0 or width < 0 or height < 0 or
    angle_millidegrees < -17000 or angle_millidegrees > 17000 or
    transform_code < 1 or transform_code > 8 or
    ((width == 0 or height == 0) and (left != 0 or top != 0 or width != 0 or height != 0)) or
    width > 10000 - left or height > 10000 - top {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and
        current_slot.exposure_available and develop_history.valid(&current_slot.history) {
            target = current_slot.history.entries[current_slot.history.cursor];
            if target.crop_left != left or target.crop_top != top or target.crop_width != width or
            target.crop_height != height or target.straighten_millidegrees != angle_millidegrees or
            target.transform_code != transform_code {
                const started = document_state.begin_open(current_slot.state);
                if started is opening {
                    var slot = current_slot;
                    target.crop_left = left;
                    target.crop_top = top;
                    target.crop_width = width;
                    target.crop_height = height;
                    target.straighten_millidegrees = angle_millidegrees;
                    target.transform_code = transform_code;
                    slot.state = opening;
                    slot.pending_exposure_tenths = target.exposure_tenths;
                    slot.pending_contrast_percent = target.contrast_percent;
                    slot.pending_shadows_percent = target.shadows_percent;
                    slot.pending_highlights_percent = target.highlights_percent;
                    slot.pending_blacks_percent = target.blacks_percent;
                    slot.pending_whites_percent = target.whites_percent;
                    slot.pending_warmth_percent = target.warmth_percent;
                    slot.pending_tint_percent = target.tint_percent;
                    slot.pending_vibrance_percent = target.vibrance_percent;
                    slot.pending_saturation_percent = target.saturation_percent;
                    slot.pending_clarity_percent = target.clarity_percent;
                    slot.pending_texture_percent = target.texture_percent;
                    slot.pending_edit = true;
                    slot.pending_history_cursor = -1;
                    slot.pending_geometry = true;
                    slot.pending_geometry_values = target;
                    documents.slots[index] = slot;
                    generation = opening.generation;
                }
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const values = history_request(target);
    const scheduled = rerender_history(window, generation, values[0..].ptr,
        history_request_length(target)
    );
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"args":{"left":{"type":"int32","min":0,"max":10000},"top":{"type":"int32","min":0,"max":10000},"width":{"type":"int32","min":0,"max":10000},"height":{"type":"int32","min":0,"max":10000},"angle_millidegrees":{"type":"int32","min":-17000,"max":17000}},"returns":"boolean"}
pub fn commit_geometry(left: i32, top: i32, width: i32, height: i32, angle_millidegrees: i32): i32 {
    const window = current_window();
    var code: i32 = 0;
    lock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and not slot.state.opening and
        develop_history.valid(&slot.history) {
            code = slot.history.entries[slot.history.cursor].transform_code;
        }
    }
    unlock_documents();
    return commit_geometry_values(left, top, width, height,
        angle_millidegrees, code
    );
}

// @neiv {"args":{"code":{"type":"int32","min":1,"max":8},"left":{"type":"int32","min":0,"max":10000},"top":{"type":"int32","min":0,"max":10000},"width":{"type":"int32","min":0,"max":10000},"height":{"type":"int32","min":0,"max":10000},"angle_millidegrees":{"type":"int32","min":-17000,"max":17000}},"returns":"int32"}
pub fn commit_transform(code: i32, left: i32, top: i32, width: i32, height: i32, angle_millidegrees: i32): i32 {
    const window = current_window();
    var old_code: i32 = 0;
    var generation: u32 = 0;
    lock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and not slot.state.opening and
        develop_history.valid(&slot.history) {
            old_code = slot.history.entries[slot.history.cursor].transform_code;
            generation = slot.state.committed_generation;
        }
    }
    unlock_documents();
    if generation == 0 or old_code < 1 or old_code > 8 or
    code < 1 or code > 8 {
        return -1;
    }
    var source_width: [1]usize = [0];
    var source_height: [1]usize = [0];
    const canvas_status = source_canvas_size(window, generation,
        source_width[0..].ptr, source_height[0..].ptr
    );
    if canvas_status != 1 {
        return -2;
    }
    var selected_left = left;
    var selected_top = top;
    var selected_width = width;
    var selected_height = height;
    if width != 0 or height != 0 {
        if left < 0 or top < 0 or width <= 0 or height <= 0 {
            return -3;
        }
        const mapped = orthogonal_transform.remap_rect({
                version: 1,
                code: old_code as u32
            }, {
                version: 1,
                code: code as u32
            }, source_width[0], source_height[0],
            left as usize, top as usize, width as usize, height as usize
        );
        if mapped.status != 0 or mapped.left > 10000 or mapped.top > 10000 or
        mapped.width > 10000 or mapped.height > 10000 {
            return -4;
        }
        selected_left = mapped.left as i32;
        selected_top = mapped.top as i32;
        selected_width = mapped.width as i32;
        selected_height = mapped.height as i32;
    }
    const applied = commit_geometry_values(selected_left, selected_top,
        selected_width, selected_height, angle_millidegrees, code
    );
    if applied == 0 {
        return -5;
    }
    return 1;
}

// @neiv {"args":{"kind":{"type":"int32","min":0,"max":2},"band":{"type":"int32","min":0,"max":7}},"returns":"int32"}
pub fn hsl_value(kind: i32, band: i32): i32 {
    if kind < 0 or kind > 2 or band < 0 or band > 7 {
        return 0;
    }
    const window = current_window();
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and develop_history.valid(&slot.history) {
            return develop_history.hsl_percent(slot.history.entries[slot.history.cursor].hsl,
                kind as usize, band as usize
            );
        }
    }
    return 0;
}

// @neiv {"args":{"kind":{"type":"int32","min":0,"max":2},"band":{"type":"int32","min":0,"max":7},"percent":{"type":"int32","min":-100,"max":100}},"returns":"boolean"}
pub fn set_hsl(kind: i32, band: i32, percent: i32): i32 {
    if kind < 0 or kind > 2 or band < 0 or band > 7 or percent < -100 or percent > 100 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and
        current_slot.exposure_available and develop_history.valid(&current_slot.history) {
            target = current_slot.history.entries[current_slot.history.cursor];
            if develop_history.hsl_percent(target.hsl, kind as usize, band as usize) != percent {
                const changed = develop_history.with_hsl_percent(target.hsl, kind as usize,
                    band as usize, percent
                );
                const started = document_state.begin_open(current_slot.state);
                if changed is recipe {
                    if started is opening {
                        var slot = current_slot;
                        target.hsl = recipe;
                        slot.state = opening;
                        slot.pending_exposure_tenths = target.exposure_tenths;
                        slot.pending_contrast_percent = target.contrast_percent;
                        slot.pending_shadows_percent = target.shadows_percent;
                        slot.pending_highlights_percent = target.highlights_percent;
                        slot.pending_blacks_percent = target.blacks_percent;
                        slot.pending_whites_percent = target.whites_percent;
                        slot.pending_warmth_percent = target.warmth_percent;
                        slot.pending_tint_percent = target.tint_percent;
                        slot.pending_vibrance_percent = target.vibrance_percent;
                        slot.pending_saturation_percent = target.saturation_percent;
                        slot.pending_clarity_percent = target.clarity_percent;
                        slot.pending_texture_percent = target.texture_percent;
                        slot.pending_edit = true;
                        slot.pending_history_cursor = -1;
                        slot.pending_geometry = true;
                        slot.pending_geometry_values = target;
                        documents.slots[index] = slot;
                        generation = opening.generation;
                    }
                }
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const values = history_request(target);
    const scheduled = rerender_history(window, generation, values[0..].ptr,
        history_request_length(target)
    );
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"args":{"channel":{"type":"int32","min":0,"max":3},"point":{"type":"int32","min":0,"max":2}},"returns":"int32"}
pub fn curve_value(channel: i32, point: i32): i32 {
    if channel < 0 or channel > 3 or point < 0 or point > 2 {
        return 0;
    }
    const window = current_window();
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and develop_history.valid(&slot.history) {
            return slot.history.entries[slot.history.cursor].curve[
                channel as usize * 3 + point as usize
            ];
        }
    }
    return develop_history.neutral_curve()[channel as usize * 3 + point as usize];
}

// @neiv {"args":{"channel":{"type":"int32","min":0,"max":3},"point":{"type":"int32","min":0,"max":2},"output":{"type":"int32","min":0,"max":1000}},"returns":"boolean"}
pub fn set_curve(channel: i32, point: i32, output: i32): i32 {
    if channel < 0 or channel > 3 or point < 0 or point > 2 or output < 0 or output > 1000 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and
        current_slot.exposure_available and develop_history.valid(&current_slot.history) {
            target = current_slot.history.entries[current_slot.history.cursor];
            if target.curve[channel as usize * 3 + point as usize] != output {
                const changed = develop_history.with_curve_point(target.curve,
                    channel as usize, point as usize, output
                );
                const started = document_state.begin_open(current_slot.state);
                if changed is recipe {
                    if started is opening {
                        var slot = current_slot;
                        target.curve = recipe;
                        slot.state = opening;
                        slot.pending_exposure_tenths = target.exposure_tenths;
                        slot.pending_contrast_percent = target.contrast_percent;
                        slot.pending_shadows_percent = target.shadows_percent;
                        slot.pending_highlights_percent = target.highlights_percent;
                        slot.pending_blacks_percent = target.blacks_percent;
                        slot.pending_whites_percent = target.whites_percent;
                        slot.pending_warmth_percent = target.warmth_percent;
                        slot.pending_tint_percent = target.tint_percent;
                        slot.pending_vibrance_percent = target.vibrance_percent;
                        slot.pending_saturation_percent = target.saturation_percent;
                        slot.pending_clarity_percent = target.clarity_percent;
                        slot.pending_texture_percent = target.texture_percent;
                        slot.pending_edit = true;
                        slot.pending_history_cursor = -1;
                        slot.pending_geometry = true;
                        slot.pending_geometry_values = target;
                        documents.slots[index] = slot;
                        generation = opening.generation;
                    }
                }
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const values = history_request(target);
    const scheduled = rerender_history(window, generation, values[0..].ptr,
        history_request_length(target)
    );
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"args":{"field":{"type":"int32","min":0,"max":19}},"returns":"int32"}
pub fn grade_value(field: i32): i32 {
    if field < 0 or field > 19 {
        return 0;
    }
    const window = current_window();
    lock_documents();
    defer unlock_documents();
    if document_registry.find(&documents, window) is index {
        const slot = documents.slots[index];
        if slot.state.has_photo and develop_history.valid(&slot.history) {
            return slot.history.entries[slot.history.cursor].grade[field as usize];
        }
    }
    return 0;
}

fn set_grade_changes(field: i32, value: i32, other_field: i32, other_value: i32): i32 {
    if field < 0 or field > 19 or other_field < 0 or other_field > 19 or
    value < -100 or value > 359 or other_value < -100 or other_value > 359 {
        return 0;
    }
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        if current_slot.state.has_photo and not current_slot.state.opening and
        current_slot.exposure_available and develop_history.valid(&current_slot.history) {
            target = current_slot.history.entries[current_slot.history.cursor];
            var changed = target.grade;
            changed[field as usize] = value;
            changed[other_field as usize] = other_value;
            if changed != target.grade and develop_history.valid_grade(changed) {
                const started = document_state.begin_open(current_slot.state);
                if started is opening {
                    var slot = current_slot;
                    target.grade = changed;
                    slot.state = opening;
                    slot.pending_exposure_tenths = target.exposure_tenths;
                    slot.pending_contrast_percent = target.contrast_percent;
                    slot.pending_shadows_percent = target.shadows_percent;
                    slot.pending_highlights_percent = target.highlights_percent;
                    slot.pending_blacks_percent = target.blacks_percent;
                    slot.pending_whites_percent = target.whites_percent;
                    slot.pending_warmth_percent = target.warmth_percent;
                    slot.pending_tint_percent = target.tint_percent;
                    slot.pending_vibrance_percent = target.vibrance_percent;
                    slot.pending_saturation_percent = target.saturation_percent;
                    slot.pending_clarity_percent = target.clarity_percent;
                    slot.pending_texture_percent = target.texture_percent;
                    slot.pending_edit = true;
                    slot.pending_history_cursor = -1;
                    slot.pending_geometry = true;
                    slot.pending_geometry_values = target;
                    documents.slots[index] = slot;
                    generation = opening.generation;
                }
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const values = history_request(target);
    const scheduled = rerender_history(window, generation, values[0..].ptr,
        history_request_length(target)
    );
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"args":{"field":{"type":"int32","min":0,"max":19},"value":{"type":"int32","min":-100,"max":359}},"returns":"boolean"}
pub fn set_grade(field: i32, value: i32): i32 {
    return set_grade_changes(field, value, field, value);
}

// @neiv {"args":{"wheel":{"type":"int32","min":0,"max":3},"hue":{"type":"int32","min":0,"max":359},"strength":{"type":"int32","min":0,"max":100}},"returns":"boolean"}
pub fn set_grade_wheel(wheel: i32, hue: i32, strength: i32): i32 {
    if wheel < 0 or wheel > 3 {
        return 0;
    }
    return set_grade_changes(wheel * 3, hue, wheel * 3 + 1, strength);
}

// @neiv {"args":{"hue":{"type":"int32","min":0,"max":359}},"returns":"boolean"}
pub fn set_picked_color(hue: i32): i32 {
    return set_grade_changes(13, hue, 19, 1);
}

// @neiv {"returns":"boolean"}
pub fn undo_edit(): i32 {
    return move_history(-1);
}

// @neiv {"returns":"boolean"}
pub fn redo_edit(): i32 {
    return move_history(1);
}

fn move_history(direction: i32): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var generation: u32 = 0;
    var target = develop_history.neutral();
    if document_registry.find(&documents, window) is index {
        const current_slot = documents.slots[index];
        var allowed = develop_history.can_redo(&current_slot.history);
        if direction < 0 {
            allowed = develop_history.can_undo(&current_slot.history);
        }
        if allowed and current_slot.state.has_photo and not current_slot.state.opening and current_slot.exposure_available {
            const started = document_state.begin_open(current_slot.state);
            if started is opening {
                var slot = current_slot;
                var cursor = slot.history.cursor + 1;
                if direction < 0 {
                    cursor = slot.history.cursor - 1;
                }
                target = slot.history.entries[cursor];
                slot.state = opening;
                slot.pending_exposure_tenths = target.exposure_tenths;
                slot.pending_contrast_percent = target.contrast_percent;
                slot.pending_shadows_percent = target.shadows_percent;
                slot.pending_highlights_percent = target.highlights_percent;
                slot.pending_blacks_percent = target.blacks_percent;
                slot.pending_whites_percent = target.whites_percent;
                slot.pending_warmth_percent = target.warmth_percent;
                slot.pending_tint_percent = target.tint_percent;
                slot.pending_vibrance_percent = target.vibrance_percent;
                slot.pending_saturation_percent = target.saturation_percent;
                slot.pending_clarity_percent = target.clarity_percent;
                slot.pending_texture_percent = target.texture_percent;
                slot.pending_edit = true;
                slot.pending_history_cursor = cursor as i32;
                documents.slots[index] = slot;
                generation = opening.generation;
            }
        }
    }
    unlock_documents();
    if generation == 0 {
        return 0;
    }
    const values = history_request(target);
    const scheduled = rerender_history(window, generation, values[0..].ptr,
        history_request_length(target)
    );
    if scheduled != 0 {
        complete_open(window, generation, scheduled);
        return 0;
    }
    return 1;
}

// @neiv {"returns":"boolean"}
pub fn cancel_open(): i32 {
    const window = current_window();
    if window <= 0 {
        return 0;
    }
    lock_documents();
    var cancelled = false;
    if document_registry.find(&documents, window) is index {
        const state = documents.slots[index].state;
        if state.opening {
            var slot = documents.slots[index];
            slot.state = document_state.cancel_open(state);
            documents.slots[index] = slot;
            discard_candidate(window, state.generation as u32);
            cancel_picker(window, state.generation as u32);
            cancelled = true;
        }
    }
    unlock_documents();
    if cancelled {
        return 1;
    }
    return 0;
}
