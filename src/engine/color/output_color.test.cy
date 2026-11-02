import .engine.color.output_color;

test "split output operations reproduce accepted fused encoder" {
    var levels: [:]f64 = [-0.25, 0.0, 0.0031308, 0.18, 0.5, 1.0, 1.5];
    var i: usize = 0;
    while i < 7 {
        var j: usize = 0;
        while j < 7 {
            var k: usize = 0;
            while k < 7 {
                var channel: i32 = 0;
                while channel < 3 {
                    const fused = output_color.encode_channel(levels[i], levels[j], levels[k], channel);
                    const split = output_color.encode_channel_split(levels[i], levels[j], levels[k], channel);
                    assert(fused == split);
                    channel = channel + 1;
                }
                k = k + 1;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    assert(output_color.clip_linear_srgb(-0.1) == 0.0);
    assert(output_color.clip_linear_srgb(1.1) == 1.0);
}
