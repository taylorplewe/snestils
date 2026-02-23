// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");

const Util = @This();

usage: ?Usage,
vtable: *const VTable,
pub const VTable = struct {
    parseArgs: *const fn (args: [][:0]u8) void,

    /// Perform main action associated with this utility
    ///
    /// e.g. the `patch` utility patches a ROM file via its `do` implementation
    do: *const fn (allocator: *const std.mem.Allocator) void,
};

pub fn do(self: *const Util, allocator: *const std.mem.Allocator, args_raw: [][:0]u8) void {
    self.vtable.parseArgs(args_raw);
    self.vtable.do(allocator);
}

pub const ParseArgsError = error{};
