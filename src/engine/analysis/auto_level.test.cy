import .engine.analysis.auto_level;

fn no_cancel(context: usize): bool {
    return false;
}
fn cancel(context: usize): bool {
    return true;
}

fn line(width: usize, height: usize, rise: i32, run: i32): [:]u8 {
    var image: [:]u8 = [: width * height]u8;
    while image.len() < width * height {
        image.push(0);
    }
    var y: usize = 0;
    while y < height {
        var x: usize = 0;
        while x < width {
            const boundary = 48 + ((x as i32) - 64) * rise / run;
            if (y as i32) >= boundary {
                image[y * width + x] = 220;
            } else {
                image[y * width + x] = 20;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    return image;
}

test "dominant horizon suggests the opposite signed correction" {
    const rising = line(128, 96, 1, 10);
    const estimate = auto_level.estimate(rising[..], 128, 96, no_cancel, 0);
    assert(estimate.status == 0);
    assert(estimate.angle_millidegrees <= -4500);
    assert(estimate.angle_millidegrees >= -6500);
    assert(estimate.votes >= 32);
    const falling = line(128, 96, -1, 10);
    const opposite = auto_level.estimate(falling[..], 128, 96, no_cancel, 0);
    assert(opposite.status == 0);
    assert(opposite.angle_millidegrees >= 4500);
    assert(opposite.angle_millidegrees <= 6500);
}

test "flat image has no horizon and cancellation returns no suggestion" {
    var flat: [:]u8 = [: 4096]u8;
    while flat.len() < 4096 {
        flat.push(0);
    }
    const absent = auto_level.estimate(flat[..], 64, 64, no_cancel, 0);
    assert(absent.status == 2 and absent.angle_millidegrees == 0);
    const cancelled = auto_level.estimate(flat[..], 64, 64, cancel, 0);
    assert(cancelled.status == 7 and cancelled.angle_millidegrees == 0);
    const invalid = auto_level.estimate(flat[..], 65, 64, no_cancel, 0);
    assert(invalid.status == 1);
}

test "vertical structure does not claim a horizon" {
    var vertical: [:]u8 = [: 4096]u8;
    while vertical.len() < 4096 {
        vertical.push(0);
    }
    var y: usize = 0;
    while y < 64 {
        var x: usize = 0;
        while x < 64 {
            if x >= 32 {
                vertical[y * 64 + x] = 220;
            }
            x = x + 1;
        }
        y = y + 1;
    }
    const estimate = auto_level.estimate(vertical[..], 64, 64, no_cancel, 0);
    assert(estimate.status == 2 and estimate.angle_millidegrees == 0);
}
