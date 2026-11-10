import .nef.camera_open;
import { open_generation, open_exposure_tenths, open_contrast_percent, open_shadows_percent, open_highlights_percent, open_blacks_percent, open_whites_percent, open_warmth_percent, open_tint_percent, open_vibrance_percent, open_saturation_percent, open_clarity_percent, open_texture_percent } from .native_preview;

// @neiv-callback
pub fn open_camera_nef(path: *const u8): i32 {
    return camera_open.open(path, open_generation(), open_exposure_tenths(), open_contrast_percent(), open_shadows_percent(), open_highlights_percent(), open_blacks_percent(), open_whites_percent(), open_warmth_percent(), open_tint_percent(), open_vibrance_percent(), open_saturation_percent(), open_clarity_percent(), open_texture_percent());
}
