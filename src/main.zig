const std = @import("std");
const builtin = @import("builtin");

const disp = @import("disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");
const InfoUtil = @import("info.zig").InfoUtil;
const ChecksumUtil = @import("checksum.zig").ChecksumUtil;
const SplitUtil = @import("split.zig").SplitUtil;
const PatchUtil = @import("patch/patch.zig").PatchUtil;

const UtilKind = enum {
    info,
    @"fix-checksum",
    split,
    patch,
    help,
};
const util_init_funcs = [_]*const fn () Util{
    InfoUtil.init,
    ChecksumUtil.init,
    SplitUtil.init,
    PatchUtil.init,
    HelpUtil.init,
};

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(arena.allocator()) catch fatal("unable to allocate memory for arguments");

    switch (args.len) {
        0...1 => usage.printAndExit(),
        2 => {
            const util_name = args[1];

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
    fn printHelp(_: *const std.mem.Allocator, _: [][:0]u8) void {
        usage.printAndExit();
    }
    pub fn init() Util {
        return .{
            .action_num_args = 0,
            .vtable = &.{
                .do = printHelp,
            },
            .usage = null,
        };
    }
};

const EXE = if (builtin.os.tag == .windows) ".exe" else "";
const usage = Usage{
    .title = "snestils" ++ EXE,
    .description = "suite of SNES ROM utilities",
    .usage_lines = &.{
        "<util> [options]",
        "<rom>",
    },
    .sections = &.{
        .{
            .title = "Utils",
            .items = &.{
                .{ .title = "info", .description = "print out information about a ROM" },
                .{ .title = "fix-checksum", .description = "calculate the ROM's correct checksum and write it to the ROM's internal header" },
                .{ .title = "split", .description = "repeat a ROM's contents to fill a certain amount of memory" },
                .{ .title = "patch", .description = "apply an IPS, UPS or BPS patch file to a ROM" },
                .{ .title = "help", .description = "print this help message and exit" },
            },
        },
    },
};
