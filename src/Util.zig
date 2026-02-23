// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");

const Util = @This();

usage: ?Usage,
vtable: *const VTable,
pub const VTable = struct {
    parseArgs: ?*const fn (*const std.mem.Allocator, [][:0]u8) ParseArgsError!void,

    /// Perform main action associated with this utility
    ///
    /// e.g. the `patch` utility patches a ROM file via its `do` implementation
    do: *const fn (*const std.mem.Allocator) void,
};

pub fn do(self: *const Util, allocator: *const std.mem.Allocator, args_raw: [][:0]u8) void {
    if (self.vtable.parseArgs != null) {
        self.vtable.parseArgs.?(allocator, args_raw) catch |e| {
            switch (e) {
                ParseArgsError.MissingRequiredArg => fatal("missing required argument"),
                ParseArgsError.MissingParameterArg => fatal("missing parameter argument"),
                ParseArgsError.TooManyArgs => fatal("too many arguments"),
            }
            // TODO: print usage as well (can't rn because fatal quits)
        };
    }
    self.vtable.do(allocator);
}

pub const ParseArgsError = error{
    MissingRequiredArg,
    MissingParameterArg,
    TooManyArgs,
};
