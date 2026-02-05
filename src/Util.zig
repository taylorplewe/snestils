const std = @import("std");

const Util = @This();

vtable: *const VTable,
pub const VTable = struct {
    /// Perform main action associated with this utility
    ///
    /// e.g. the `patch` utility patches a ROM file via its `do` implementation
    do: *const fn (allocator: *const std.mem.Allocator, args: [][:0]u8) void,
};

pub fn do(self: *const Util, allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    self.vtable.do(allocator, args);
}
