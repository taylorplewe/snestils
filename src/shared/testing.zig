const std = @import("std");

/// Useful for comparing ROM binary output in unit tests.
///
/// Caller owns returned memory.
pub fn getBinFromFilePath(io: std.Io, allocator: *const std.mem.Allocator, dir: *std.Io.Dir, path: []const u8) ![]u8 {
    const file = try dir.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var reader_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &reader_buf);
    var reader = &file_reader.interface;
    return try reader.allocRemaining(allocator.*, .unlimited);
}
