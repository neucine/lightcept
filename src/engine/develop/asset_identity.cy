import .engine.develop.tone_curve;
import .engine.develop.channel_mixer;

// Exact IEEE-754 bit identity for validated Cyna-only develop assets.
// This fixed-size in-memory key is not a file format or cryptographic digest.
pub fn float_bits(value: f64): u64 {
    return value as! u64;
}

pub struct CurveKey {
    pub valid: bool;
    pub version: u32;
    pub strength: u64;
    pub count: usize;
    pub words: [64]u64;
}

pub struct MixerKey {
    pub valid: bool;
    pub version: u32;
    pub red_from_green: u64;
    pub red_from_blue: u64;
    pub green_from_red: u64;
    pub green_from_blue: u64;
    pub blue_from_red: u64;
    pub blue_from_green: u64;
}

pub fn capture_curve(asset: tone_curve.CurveAsset): CurveKey {
    var words: [64]u64 = [0] ** 64;
    if not tone_curve.valid(&asset) {
        return {
            valid: false,
            version: 0,
            strength: 0,
            count: 0,
            words: words
        };
    }
    var index: usize = 0;
    while index < asset.nodes.len() {
        words[index * 2] = float_bits(asset.nodes[index].input);
        words[index * 2 + 1] = float_bits(asset.nodes[index].output);
        index = index + 1;
    }
    return {
        valid: true,
        version: asset.version,
        strength: float_bits(asset.strength),
        count: asset.nodes.len(),
        words: words
    };
}

pub fn matches_curve(key: &const CurveKey, asset: &const tone_curve.CurveAsset): bool {
    if not key.valid or key.version != asset.version or key.strength != float_bits(asset.strength)
    or key.count != asset.nodes.len() {
        return false;
    }
    var index: usize = 0;
    while index < key.count {
        if key.words[index * 2] != float_bits(asset.nodes[index].input)
        or key.words[index * 2 + 1] != float_bits(asset.nodes[index].output) {
            return false;
        }
        index = index + 1;
    }
    return true;
}

pub fn capture_mixer(asset: channel_mixer.MixerAsset): MixerKey {
    if not channel_mixer.valid(asset) {
        return {
            valid: false,
            version: 0,
            red_from_green: 0,
            red_from_blue: 0,
            green_from_red: 0,
            green_from_blue: 0,
            blue_from_red: 0,
            blue_from_green: 0
        };
    }
    return {
        valid: true,
        version: asset.version,
        red_from_green: float_bits(asset.red_from_green),
        red_from_blue: float_bits(asset.red_from_blue),
        green_from_red: float_bits(asset.green_from_red),
        green_from_blue: float_bits(asset.green_from_blue),
        blue_from_red: float_bits(asset.blue_from_red),
        blue_from_green: float_bits(asset.blue_from_green)
    };
}

pub fn matches_mixer(key: MixerKey, asset: channel_mixer.MixerAsset): bool {
    return key.valid and channel_mixer.valid(asset) and key.version == asset.version
    and key.red_from_green == float_bits(asset.red_from_green)
    and key.red_from_blue == float_bits(asset.red_from_blue)
    and key.green_from_red == float_bits(asset.green_from_red)
    and key.green_from_blue == float_bits(asset.green_from_blue)
    and key.blue_from_red == float_bits(asset.blue_from_red)
    and key.blue_from_green == float_bits(asset.blue_from_green);
}
