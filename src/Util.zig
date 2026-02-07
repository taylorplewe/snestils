const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");

const Util = @This();

usage: ?Usage,
action_num_args: usize,
vtable: *const VTable,
pub const VTable = struct {
    /// Perform main action associated with this utility
    ///
    /// e.g. the `patch` utility patches a ROM file via its `do` implementation
    do: *const fn (allocator: *const std.mem.Allocator, args: [][:0]u8) void,
};

pub fn do(self: *const Util, allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    if (self.usage != null and args.len != self.action_num_args) {
        // fatalFmt("{d} argument(s) required!\n", .{self.action_num_args});
        self.usage.?.printAndExitWithError();
    }
    self.vtable.do(allocator, args);
}
