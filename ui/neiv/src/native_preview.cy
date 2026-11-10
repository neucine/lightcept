// C ABI adapter for the Lightcept native preview provider.
// Product modules import these functions; raw symbols are confined here.
import neiv.surface;
import .document_state;

extern c("lightcept_native_set_comparison") fn host_set_comparison(window: c_long, mode: c_int, proof: c_int): c_int;
pub fn set_comparison(window: i64, mode: i32, proof: i32): bool {
    return host_set_comparison(window as c_long, mode as c_int, proof as c_int) == 1;
}

extern c("lightcept_native_set_zoom") fn host_set_zoom(window: c_long, percent: c_int): c_int;
pub fn set_zoom(window: i64, percent: i32): bool {
    return host_set_zoom(window as c_long, percent as c_int) == 1;
}

extern c("lightcept_native_select_photo") fn host_select_photo(window: c_long, generation: c_uint): c_int;
pub fn select_photo(window: i64, generation: u32): i32 {
    return host_select_photo(window as c_long, generation as c_uint) as i32;
}

extern c("lightcept_native_select_project") fn host_select_project(window: c_long, generation: c_uint): c_int;
pub fn select_project(window: i64, generation: u32): i32 {
    return host_select_project(window as c_long, generation as c_uint) as i32;
}

extern c("lightcept_native_save_project") fn host_save_project(window: c_long, generation: c_uint, values: *const c_int, length: c_uint, cursor: c_uint, revision: c_uint): c_int;
pub fn save_project_native(window: i64, generation: u32, values: *const i32, length: u32, cursor: u32, revision: u32): i32 {
    return host_save_project(window as c_long, generation as c_uint, values as! *const c_int, length as c_uint, cursor as c_uint, revision as c_uint) as i32;
}

extern c("lightcept_native_export_tiff") fn host_export_tiff(window: c_long, generation: c_uint, values: *const c_int): c_int;
pub fn export_tiff_native(window: i64, generation: u32, values: *const i32): i32 {
    return host_export_tiff(window as c_long, generation as c_uint, values as! *const c_int) as i32;
}

extern c("lightcept_native_export_status") fn host_export_status(window: c_long): c_int;
pub fn export_status_native(window: i64): i32 {
    return host_export_status(window as c_long) as i32;
}

extern c("lightcept_native_cancel_export") fn host_cancel_export(window: c_long): void;
pub fn cancel_export_native(window: i64): void {
    host_cancel_export(window as c_long);
}

extern c("lightcept_native_cancel_picker") fn host_cancel_picker(window: c_long, generation: c_uint): void;
pub fn cancel_picker(window: i64, generation: u32): void {
    host_cancel_picker(window as c_long, generation as c_uint);
}

extern c("lightcept_native_write_snapshot") fn host_write_snapshot(out: *c_char, capacity: c_int, window: c_long, document_id: c_uint, generation: c_uint, committed: c_uint, phase: c_uint, has_photo: c_int, failure: c_uint, exposure_tenths: c_int, contrast_percent: c_int, shadows_percent: c_int, highlights_percent: c_int, blacks_percent: c_int, whites_percent: c_int, warmth_percent: c_int, tint_percent: c_int, vibrance_percent: c_int, saturation_percent: c_int, clarity_percent: c_int, texture_percent: c_int, exposure_available: c_int, edit_revision: c_uint, can_undo: c_int, can_redo: c_int, history_length: c_uint, history_cursor: c_uint, project_status: c_uint): c_int;
pub fn write_snapshot(out: *c_char, capacity: i32, window: i64, document_id: u32, generation: u32, committed: u32, phase: u32, has_photo: i32, failure: u32, exposure_tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32, exposure_available: i32, edit_revision: u32, can_undo: i32, can_redo: i32, history_length: u32, history_cursor: u32, project_status: u32): i32 {
    return host_write_snapshot(out, capacity as c_int, window as c_long, document_id as c_uint, generation as c_uint, committed as c_uint, phase as c_uint, has_photo as c_int, failure as c_uint, exposure_tenths as c_int, contrast_percent as c_int, shadows_percent as c_int, highlights_percent as c_int, blacks_percent as c_int, whites_percent as c_int, warmth_percent as c_int, tint_percent as c_int, vibrance_percent as c_int, saturation_percent as c_int, clarity_percent as c_int, texture_percent as c_int, exposure_available as c_int, edit_revision as c_uint, can_undo as c_int, can_redo as c_int, history_length as c_uint, history_cursor as c_uint, project_status as c_uint) as i32;
}

pub struct SnapshotValues {
    pub window: i64;
    pub document_id: u32;
    pub generation: u32;
    pub committed: u32;
    pub phase: document_state.DocumentPhase;
    pub has_photo: bool;
    pub failure: document_state.OpenStatus;
    pub exposure_tenths: i32;
    pub contrast_percent: i32;
    pub shadows_percent: i32;
    pub highlights_percent: i32;
    pub blacks_percent: i32;
    pub whites_percent: i32;
    pub warmth_percent: i32;
    pub tint_percent: i32;
    pub vibrance_percent: i32;
    pub saturation_percent: i32;
    pub clarity_percent: i32;
    pub texture_percent: i32;
    pub exposure_available: bool;
    pub edit_revision: u32;
    pub can_undo: bool;
    pub can_redo: bool;
    pub history_length: u32;
    pub history_cursor: u32;
    pub project_status: document_state.ProjectSaveStatus;
}

pub fn snapshot_text(values: SnapshotValues): string {
    var bytes: [4096]u8 = [0] ** 4096;
    var present: i32 = 0;
    var editable: i32 = 0;
    if values.has_photo {
        present = 1;
    }
    if values.exposure_available {
        editable = 1;
    }
    var undo_flag: i32 = 0;
    var redo_flag: i32 = 0;
    if values.can_undo {
        undo_flag = 1;
    }
    if values.can_redo {
        redo_flag = 1;
    }
    const count = write_snapshot(bytes[..].ptr as! *c_char, 4096,
        values.window, values.document_id,
        values.generation, values.committed, values.phase as u32, present, values.failure as u32,
        values.exposure_tenths, values.contrast_percent, values.shadows_percent, values.highlights_percent, values.blacks_percent, values.whites_percent, values.warmth_percent, values.tint_percent, values.vibrance_percent, values.saturation_percent, values.clarity_percent, values.texture_percent, editable, values.edit_revision, undo_flag, redo_flag, values.history_length, values.history_cursor, values.project_status as u32
    );
    if count < 0 {
        return "";
    }
    return string.from(bytes[..count as usize]);
}

extern c("lightcept_native_document_lock") fn host_lock_documents(): void;
pub fn lock_documents(): void {
    host_lock_documents();
}

extern c("lightcept_native_document_unlock") fn host_unlock_documents(): void;
pub fn unlock_documents(): void {
    host_unlock_documents();
}

extern c("lightcept_native_open_generation") fn host_open_generation(): c_uint;
pub fn open_generation(): u32 {
    return host_open_generation() as u32;
}

extern c("lightcept_native_open_exposure_tenths") fn host_open_exposure_tenths(): c_int;
pub fn open_exposure_tenths(): i32 {
    return host_open_exposure_tenths() as i32;
}

extern c("lightcept_native_open_contrast_percent") fn host_open_contrast_percent(): c_int;
pub fn open_contrast_percent(): i32 {
    return host_open_contrast_percent() as i32;
}

extern c("lightcept_native_open_shadows_percent") fn host_open_shadows_percent(): c_int;
pub fn open_shadows_percent(): i32 {
    return host_open_shadows_percent() as i32;
}

extern c("lightcept_native_open_highlights_percent") fn host_open_highlights_percent(): c_int;
pub fn open_highlights_percent(): i32 {
    return host_open_highlights_percent() as i32;
}

extern c("lightcept_native_open_blacks_percent") fn host_open_blacks_percent(): c_int;
pub fn open_blacks_percent(): i32 {
    return host_open_blacks_percent() as i32;
}
extern c("lightcept_native_open_whites_percent") fn host_open_whites_percent(): c_int;
pub fn open_whites_percent(): i32 {
    return host_open_whites_percent() as i32;
}

extern c("lightcept_native_open_warmth_percent") fn host_open_warmth_percent(): c_int;
pub fn open_warmth_percent(): i32 {
    return host_open_warmth_percent() as i32;
}
extern c("lightcept_native_open_tint_percent") fn host_open_tint_percent(): c_int;
pub fn open_tint_percent(): i32 {
    return host_open_tint_percent() as i32;
}
extern c("lightcept_native_open_vibrance_percent") fn host_open_vibrance_percent(): c_int;
pub fn open_vibrance_percent(): i32 {
    return host_open_vibrance_percent() as i32;
}

extern c("lightcept_native_open_saturation_percent") fn host_open_saturation_percent(): c_int;
pub fn open_saturation_percent(): i32 {
    return host_open_saturation_percent() as i32;
}

extern c("lightcept_native_open_texture_percent") fn host_open_texture_percent(): c_int;
pub fn open_texture_percent(): i32 {
    return host_open_texture_percent() as i32;
}

extern c("lightcept_native_open_clarity_percent") fn host_open_clarity_percent(): c_int;
pub fn open_clarity_percent(): i32 {
    return host_open_clarity_percent() as i32;
}

extern c("lightcept_native_rerender_develop") fn host_rerender_develop(window: c_long, generation: c_uint, tenths: c_int, contrast_percent: c_int, shadows_percent: c_int, highlights_percent: c_int, blacks_percent: c_int, whites_percent: c_int, warmth_percent: c_int, tint_percent: c_int, vibrance_percent: c_int, saturation_percent: c_int, clarity_percent: c_int, texture_percent: c_int): c_int;
pub fn rerender_develop(window: i64, generation: u32, tenths: i32, contrast_percent: i32, shadows_percent: i32, highlights_percent: i32, blacks_percent: i32, whites_percent: i32, warmth_percent: i32, tint_percent: i32, vibrance_percent: i32, saturation_percent: i32, clarity_percent: i32, texture_percent: i32): i32 {
    return host_rerender_develop(window as c_long, generation as c_uint, tenths as c_int, contrast_percent as c_int, shadows_percent as c_int, highlights_percent as c_int, blacks_percent as c_int, whites_percent as c_int, warmth_percent as c_int, tint_percent as c_int, vibrance_percent as c_int, saturation_percent as c_int, clarity_percent as c_int, texture_percent as c_int) as i32;
}

extern c("lightcept_native_rerender_history") fn host_rerender_history(window: c_long, generation: c_uint, values: *const c_int, length: c_size_t): c_int;
extern c("lightcept_native_source_canvas_size") fn host_source_canvas_size(window: c_long, generation: c_uint, width: *c_size_t, height: *c_size_t): c_int;
pub fn source_canvas_size(window: i64, generation: u32, width: *usize, height: *usize): i32 {
    return host_source_canvas_size(window as c_long, generation as c_uint,
        width as! *c_size_t, height as! *c_size_t
    ) as i32;
}
extern c("lightcept_native_set_crop_mode") fn host_set_crop_mode(window: c_long, enabled: c_int): c_int;
extern c("lightcept_native_set_color_pick_mode") fn host_set_color_pick_mode(window: c_long, enabled: c_int): c_int;
extern c("lightcept_native_show_color_selection") fn host_show_color_selection(window: c_long, enabled: c_int, hue: c_int, width: c_int, softness: c_int): c_int;
extern c("lightcept_native_set_crop_aspect") fn host_set_crop_aspect(window: c_long, preset: c_int): c_int;
pub fn set_crop_aspect(window: i64, preset: i32): i32 {
    return host_set_crop_aspect(window as c_long, preset as c_int) as i32;
}
pub fn set_crop_mode(window: i64, enabled: bool): i32 {
    var flag: c_int = 0;
    if enabled {
        flag = 1;
    }
    return host_set_crop_mode(window as c_long, flag) as i32;
}
pub fn set_color_pick_mode(window: i64, enabled: bool): i32 {
    var flag: c_int = 0;
    if enabled {
        flag = 1;
    }
    return host_set_color_pick_mode(window as c_long, flag) as i32;
}
pub fn show_color_selection(window: i64, enabled: bool, hue: i32,
    width: i32, softness: i32
): i32 {
    var flag: c_int = 0;
    if enabled {
        flag = 1;
    }
    return host_show_color_selection(window as c_long, flag, hue as c_int,
        width as c_int, softness as c_int
    ) as i32;
}
pub fn rerender_history(window: i64, generation: u32, values: *const i32, length: usize): i32 {
    return host_rerender_history(window as c_long, generation as c_uint,
        values as! *const c_int, length as c_size_t
    ) as i32;
}

extern c("lightcept_native_commit_frame") fn host_commit_frame(window: c_long, generation: c_uint): c_int;
pub fn commit_frame(window: i64, generation: u32): i32 {
    return host_commit_frame(window as c_long, generation as c_uint) as i32;
}

extern c("lightcept_native_discard_candidate") fn host_discard_candidate(window: c_long, generation: c_uint): void;
pub fn discard_candidate(window: i64, generation: u32): void {
    host_discard_candidate(window as c_long, generation as c_uint);
}

extern c("lightcept_native_create_preview") fn host_create_preview(window: c_long): c_long;
pub fn create_preview(window: i64): i64 {
    return host_create_preview(window as c_long) as i64;
}

extern c("lightcept_native_create_navigator_preview") fn host_create_navigator_preview(window: c_long): c_long;
pub fn create_navigator_preview(window: i64): i64 {
    return host_create_navigator_preview(window as c_long) as i64;
}

extern c("lightcept_native_create_filmstrip_preview") fn host_create_filmstrip_preview(window: c_long): c_long;
pub fn create_filmstrip_preview(window: i64): i64 {
    return host_create_filmstrip_preview(window as c_long) as i64;
}

extern c("lightcept_native_create_histogram") fn host_create_histogram(window: c_long): c_long;
pub fn create_histogram(window: i64): i64 {
    return host_create_histogram(window as c_long) as i64;
}

extern c("lightcept_native_file_size") fn host_file_size(path: *const c_char): c_size_t;
pub fn file_size(path: *const u8): usize {
    return host_file_size(path as! *const c_char) as usize;
}

extern c("lightcept_native_read_file") fn host_read_file(path: *const c_char, output: *c_uchar, length: c_size_t): c_int;
pub fn read_file(path: *const u8, output: *u8, length: usize): i32 {
    return host_read_file(path as! *const c_char, output as! *c_uchar, length as c_size_t) as i32;
}

extern c("lightcept_native_publish_frame") fn host_publish_frame(pixels: *const c_uchar, length: c_size_t, width: c_size_t, height: c_size_t, generation: c_uint): c_int;
pub fn publish_frame(pixels: *const u8, length: usize, width: usize, height: usize, generation: u32): i32 {
    return host_publish_frame(pixels as! *const c_uchar, length as c_size_t, width as c_size_t, height as c_size_t, generation as c_uint) as i32;
}

extern c("lightcept_native_should_cancel") fn host_should_cancel(): c_int;
pub fn should_cancel(): bool {
    return host_should_cancel() != 0;
}

pub fn surface_alive(handle: i64): i32 {
    const surface_id = surface.from_raw_handle(handle as c_long) catch (error) {
        return 0;
    };
    if surface.is_alive(surface_id) {
        return 1;
    }
    return 0;
}
pub fn destroy_surface(handle: i64): i32 {
    const surface_id = surface.from_raw_handle(handle as c_long) catch (error) {
        return 1;
    };
    surface.destroy(surface_id) catch (error) {
        return 1;
    };
    return 0;
}

extern c("lightcept_native_publish_prepared") fn host_publish_prepared(working: *const c_uchar, working_length: c_size_t, baseline: *const c_uchar, width: c_size_t, height: c_size_t, source_width: c_size_t, source_height: c_size_t, generation: c_uint): c_int;
pub fn publish_prepared(working: *const f64, working_length: usize, baseline: *const f64, width: usize, height: usize, source_width: usize, source_height: usize, generation: u32): i32 {
    return host_publish_prepared(working as! *const c_uchar, working_length as c_size_t, baseline as! *const c_uchar, width as c_size_t, height as c_size_t, source_width as c_size_t, source_height as c_size_t, generation as c_uint) as i32;
}
