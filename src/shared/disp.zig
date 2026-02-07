const std = @import("std");

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;
    stdout.print(fmt, args) catch return;
    stdout.flush() catch unreachable;
    return;
}
pub inline fn clearLine() void {
    printf("\x1b[2K\x1b[G", .{});
}
pub inline fn println(comptime msg: []const u8) void {
    printf("{s}\n", .{msg});
}
pub inline fn printLoading(comptime msg: []const u8) void {
    printf("{s}...\x1b[G", .{msg});
}

pub fn fatalFmt(comptime fmt: []const u8, args: anytype) noreturn {
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    var stderr = &stderr_writer.interface;
    stderr.print("\x1b[2K\x1b[G\x1b[1;31mERROR:\x1b[0m ", .{}) catch unreachable;
    stderr.print(fmt, args) catch unreachable;
    stderr.print("\n", .{}) catch unreachable;
    stderr.flush() catch unreachable;
    std.process.exit(1);
}
pub inline fn fatal(comptime msg: []const u8) noreturn {
    fatalFmt(msg, .{});
}
