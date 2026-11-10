import .engine.pipeline.develop_region;
import .engine.pipeline.preview_develop_plan;

fn no_cancel(context: usize): bool {
    const ignored = context;
    return false;
}

fn cancel(context: usize): bool {
    return context == 7;
}

fn controls(): preview_develop_plan.Controls {
    return {
        exposure_tenths: 5,
        contrast_percent: 10,
        shadows_percent: 10,
        highlights_percent: -10,
        blacks_percent: -10,
        whites_percent: 10,
        warmth_percent: 10,
        tint_percent: -10,
        vibrance_percent: 10,
        saturation_percent: 10,
        clarity_percent: 30,
        texture_percent: 40
    };
}

test "developed source regions match full preview at corners and interior with detail" {
    const width: usize = 16;
    const height: usize = 12;
    var working: [576]f64 = [0.0] ** 576;
    var full: [768]u8 = [0] ** 768;
    var pixel: usize = 0;
    while pixel < width * height {
        const x = pixel % width;
        const y = pixel / width;
        working[pixel * 3] = 0.05 + (x as f64) / 32.0;
        working[pixel * 3 + 1] = 0.08 + (y as f64) / 30.0;
        working[pixel * 3 + 2] = 0.10 + ((x + y) % 7) as f64 / 25.0;
        pixel = pixel + 1;
    }
    const edit = controls();
    assert(preview_develop_plan.render(working[0..].ptr, 576,
        full[0..].ptr, 768, width, height, 0.0, edit, no_cancel, 0
    ) == 0);
    const requests: [3]develop_region.Rect = [{
            left: 0,
            top: 0,
            width: 5,
            height: 5
        }, {
            left: 6,
            top: 4,
            width: 4,
            height: 4
        }, {
            left: 12,
            top: 9,
            width: 4,
            height: 3
        }
    ];
    var request_index: usize = 0;
    while request_index < 3 {
        const request = requests[request_index];
        const region = develop_region.bounds(width, height, request, edit);
        assert(region.status == 0);
        var expanded: [:]f64 = [: region.source.width * region.source.height * 3]f64;
        var row: usize = 0;
        while row < region.source.height {
            var column: usize = 0;
            while column < region.source.width {
                var channel: usize = 0;
                while channel < 3 {
                    expanded.push(working[((region.source.top + row) * width +
                        region.source.left + column
                    ) * 3 + channel]);
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        var tile: [:]u8 = [: request.width * request.height * 4]u8;
        while tile.len() < request.width * request.height * 4 {
            tile.push(0);
        }
        assert(develop_region.render(region, expanded[..], tile[..],
            0.0, edit, no_cancel, 0
        ) == 0);
        row = 0;
        while row < request.height {
            var column: usize = 0;
            while column < request.width {
                var channel: usize = 0;
                while channel < 4 {
                    assert(tile[(row * request.width + column) * 4 + channel] ==
                        full[((request.top + row) * width + request.left + column) * 4 + channel]
                    );
                    channel = channel + 1;
                }
                column = column + 1;
            }
            row = row + 1;
        }
        request_index = request_index + 1;
    }
}

test "developed region rejects invalid geometry and cancellation" {
    const edit = controls();
    const bad: develop_region.Rect = {
        left: 15,
        top: 0,
        width: 2,
        height: 2
    };
    assert(develop_region.bounds(16, 12, bad, edit).status == 4);
    const request: develop_region.Rect = {
        left: 0,
        top: 0,
        width: 2,
        height: 2
    };
    const region = develop_region.bounds(16, 12, request, edit);
    assert(region.status == 0);
    var expanded: [:]f64 = [: region.source.width * region.source.height * 3]f64;
    while expanded.len() < region.source.width * region.source.height * 3 {
        expanded.push(0.2);
    }
    var output: [16]u8 = [0] ** 16;
    assert(develop_region.render(region, expanded[..], output[0..],
        0.0, edit, cancel, 7
    ) == 7);
    assert(develop_region.render(region, expanded[0..expanded.len() - 1],
        output[0..], 0.0, edit, no_cancel, 0
    ) == 4);
    var changed = edit;
    changed.texture_percent = 0;
    assert(develop_region.render(region, expanded[..], output[0..],
        0.0, changed, no_cancel, 0
    ) == 5);
    changed.texture_percent = 101;
    assert(develop_region.bounds(16, 12, request, changed).status == 5);
}
