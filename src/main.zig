const std = @import("std");
const builtin = @import("builtin");

const disp = @import("disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

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
};
const util_init_funcs = [_]*const fn () Util{
    InfoUtil.init,
    ChecksumUtil.init,
    SplitUtil.init,
    PatchUtil.init,
};

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = std.process.argsAlloc(arena.allocator()) catch fatal("unable to allocate memory for arguments");

    switch (args.len) {
        0...1 => printUsageAndExit(),
        2 => {
            const util = InfoUtil.init();
            util.do(&arena.allocator(), args[1..]);
        },
        else => {
            const util_name = args[1];

            const util_kind = std.meta.stringToEnum(UtilKind, util_name) orelse fatalFmt("no util found with name \x1b[1m{s}\x1b[0m\n", .{util_name});
            const util = util_init_funcs[@intFromEnum(util_kind)]();
            util.do(&arena.allocator(), args[2..]);
        },
    }
}

fn printUsageAndExit() noreturn {
    const EXE = if (builtin.os.tag == .windows) ".exe" else "";
    const TAB = "    ";
    disp.clearAndPrint("\x1b[1;33msnestils" ++ EXE ++ "\x1b[0m - modify an SNES ROM\n" ++
        "\n" ++
        "Usage:\n" ++
        TAB ++ "\x1b[0msnestils" ++ EXE ++ " <util> <path-to-rom> [path-to-patch-file]\n" ++
        "\n" ++
        "Utils:\n" ++
        TAB ++ "\x1b[33minfo\x1b[0m - print out information about a ROM\n" ++
        TAB ++ "\x1b[33mfix-checksum\x1b[0m - calculate the ROM's correct checksum and write it to the ROM's internal header\n" ++
        TAB ++ "\x1b[33msplit\x1b[0m - repeat a ROM's contents to fill a certain amount of memory\n" ++
        TAB ++ "\x1b[33mpatch\x1b[0m - apply an IPS patch file to a ROM\n", .{});
    // TAB ++ "\x1b[33mremove-header\x1b[0m - remove a ROM's header\n", .{});
    std.process.exit(0);
}
