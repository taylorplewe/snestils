// Copyright (c) 2026 Taylor Plewe
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, see
// <https://www.gnu.org/licenses/>.

const std = @import("std");
const builtin = @import("builtin");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const ChecksumUtil = @import("checksum.zig").ChecksumUtil;
const InfoUtil = @import("info.zig").InfoUtil;
const PatchUtil = @import("patch/patch.zig").PatchUtil;
const SplitUtil = @import("split.zig").SplitUtil;
const JoinUtil = @import("join.zig").JoinUtil;
const RemoveHeaderUtil = @import("remove_header.zig").RemoveHeaderUtil;
const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

const UtilKind = enum {
    info,
    @"fix-checksum",
    split,
    patch,
    join,
    @"remove-header",
    help,
};
const util_init_funcs = [_]*const fn () Util{
    InfoUtil.init,
    ChecksumUtil.init,
    SplitUtil.init,
    PatchUtil.init,
    JoinUtil.init,
    RemoveHeaderUtil.init,
    HelpUtil.init,
};

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args: [][:0]u8 = blk: {
        var kept_args: std.ArrayList([:0]u8) = .empty;
        var args_it = std.process.argsWithAllocator(arena.allocator()) catch fatal("could not allocate memory for args iterator");
        while (args_it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--quiet")) {
                disp.quiet = true;
            } else {
                kept_args.append(arena.allocator(), @constCast(arg)) catch fatal("could not allocate memory for next argument");
            }
        }
        break :blk kept_args.items;
    };

    switch (args.len) {
        0...1 => usage.printAndExit(),
        2 => {
            const util_name = blk: {
                if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
                    break :blk "help";
                } else {
                    break :blk args[1];
                }
            };

            const util_kind: UtilKind = std.meta.stringToEnum(UtilKind, util_name) orelse .info;
            const util = util_init_funcs[@intFromEnum(util_kind)]();
            util.do(&arena.allocator(), if (util_kind == .info) args[1..2] else &.{});
        },
        else => {
            const util_name = args[1];

            const util_kind = std.meta.stringToEnum(UtilKind, util_name) orelse fatalFmt("no util found with name \x1b[1m{s}\x1b[0m\n", .{util_name});
            const util = util_init_funcs[@intFromEnum(util_kind)]();
            util.do(&arena.allocator(), args[2..]);
        },
    }
}

const HelpUtil = struct {
    fn printHelp(_: *const std.mem.Allocator) void {
        usage.printAndExit();
    }
    pub fn init() Util {
        return .{
            .vtable = &.{
                .parseArgs = null,
                .do = printHelp,
            },
            .usage = null,
        };
    }
};

const usage = Usage{
    .title = shared.PROGRAM_NAME,
    .description = "suite of SNES ROM utilities",
    .usage_lines = &.{
        "<util> [options]",
        "<rom>",
    },
    .sections = &.{
        .{
            .title = "Utils",
            .items = &.{
                .{ .shorthand = "", .title = "info", .arg = "", .description = "print out information about a ROM" },
                .{ .shorthand = "", .title = "fix-checksum", .arg = "", .description = "calculate the ROM's correct checksum and write it to the ROM's internal header" },
                .{ .shorthand = "", .title = "split", .arg = "", .description = "repeat a ROM's contents to fill a certain amount of memory" },
                .{ .shorthand = "", .title = "patch", .arg = "", .description = "apply an IPS, UPS or BPS patch file to a ROM" },
                .{ .shorthand = "", .title = "join", .arg = "", .description = "join split binary chunks into a single ROM file" },
                .{ .shorthand = "", .title = "remove-header", .arg = "", .description = "remove a ROM's 512-byte copier device header, if it has one" },
                .{ .shorthand = "-h", .title = "--help", .arg = "", .description = "print this help message and exit" },
            },
        },
    },
};
