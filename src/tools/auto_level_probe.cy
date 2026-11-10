import std.fs;
import std.process;
import .engine.analysis.auto_level;

fn no_cancel(context: usize): bool {
    return false;
}

fn unsigned32(bytes: []const u8, offset: usize): usize {
    return (bytes[offset] as usize)
    | ((bytes[offset + 1] as usize) << 8)
    | ((bytes[offset + 2] as usize) << 16)
    | ((bytes[offset + 3] as usize) << 24);
}

// Read an eight-byte little-endian width/height request and row-major u8 luma.
// Print the version, status, angle, votes and edge count on separate lines.
fn main(): i32 {
    const args = process.args();
    if args.len() != 3 {
        return 4;
    }
    const request = fs.read_bytes(args[1]) catch (error) {
        return 1;
    };
    if request.len() != 8 {
        return 4;
    }
    const width = unsigned32(request[..], 0);
    const height = unsigned32(request[..], 4);
    const input = fs.read_bytes(args[2]) catch (error) {
        return 1;
    };
    const result = auto_level.estimate(input[..], width, height, no_cancel, 0);
    println(result.version);
    println(result.status);
    println(result.angle_millidegrees);
    println(result.votes);
    println(result.edge_pixels);
    return 0;
}
