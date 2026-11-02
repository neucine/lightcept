import std.math;

test "standard rounded conversion accepts ordinary finite camera values" {
    const rounded = math.to_f32_rounded(0.1);
    if rounded is value {
        assert((value as f64) > 0.1 and (value as f64) < 0.11);
    } else {
        assert(false);
    }
    const exact = math.to_f32_rounded(0.5);
    if exact is value {
        assert(value == 0.5);
    } else {
        assert(false);
    }
}
