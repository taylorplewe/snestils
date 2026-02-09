// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("../Usage.zig");
const Util = @import("../Util.zig");
const Patcher = @import("./Patcher.zig");
const IpsPatcher = @import("./IpsPatcher.zig");
const UpsPatcher = @import("./UpsPatcher.zig");
const BpsPatcher = @import("./BpsPatcher.zig");

/// Maximum allocation size for each file's buffer
/// This is *not* the amount that is requested, but rather the value passed to `limit` when allocation is delegated elsewhere
const MAX_ALLOC_SIZE = std.math.maxInt(u32) * 8; // 32MB

const PatchFormat = enum {
    ips,
    ups,
    bps,
};

pub const PatchUtil = struct {
    pub const usage: Usage = .{
        .title = "patch",
        .description = "apply an IPS, UPS or BPS patch file to a ROM",
        .usage_lines = &.{
            "<rom-file> <patch-file>",
        },
        .sections = &.{},
    };
    pub fn init() Util {
        return .{
            .vtable = &.{ .do = patch },
            .action_num_args = 2,
            .usage = usage,
        };
    }
};

pub fn patch(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    if (args.len < 2) {
        fatal("must provide ROM filepath followed by patch filepath");
    }
    const original_rom_path = args[0];
    const patch_path = args[1];

    // patch file I/O
    const patch_path_ext = patch_path[((std.mem.lastIndexOfScalar(u8, patch_path, '.') orelse patch_path.len) + 1)..];
    const patch_file_format = std.meta.stringToEnum(PatchFormat, patch_path_ext) orelse fatalFmt("unsupported patch file extension \x1b[1m{s}\x1b[0m", .{patch_path_ext});
    const patch_file = std.fs.cwd().openFile(patch_path, .{ .mode = .read_only }) catch fatalFmt("could not open patch file \x1b[1m{s}\x1b[0m", .{patch_path});
    var patch_reader_buf: [2048]u8 = undefined;
    var patch_file_reader = patch_file.reader(&patch_reader_buf);
    var patch_reader = &patch_file_reader.interface;
    const patch_buf = patch_reader.allocRemaining(allocator.*, .limited(MAX_ALLOC_SIZE)) catch fatal("could not allocate buffer from patch file");

    // original ROM I/O
    const original_rom_path_last_index_of_period = std.mem.lastIndexOfScalar(u8, original_rom_path, '.') orelse original_rom_path.len;
    const original_rom_path_base = original_rom_path[0..original_rom_path_last_index_of_period];
    const original_rom_path_ext = original_rom_path[(original_rom_path_last_index_of_period + 1)..];
    const original_rom_file = std.fs.cwd().openFile(original_rom_path, .{ .mode = .read_only }) catch fatalFmt("could not open original ROM file \x1b[1m{s}\x1b[0m", .{original_rom_path});
    var original_rom_reader_buf: [2048]u8 = undefined;
    var original_rom_file_reader = original_rom_file.reader(&original_rom_reader_buf);
    var original_rom_reader = &original_rom_file_reader.interface;
    const original_rom_buf = original_rom_reader.allocRemaining(allocator.*, .limited(MAX_ALLOC_SIZE)) catch fatal("could not allocate buffer from original ROM file");

    defer {
        patch_file.close();
        original_rom_file.close();
    }

    var patcher: Patcher = switch (patch_file_format) {
        .ips => IpsPatcher.init(allocator, patch_buf, original_rom_buf),
        .ups => UpsPatcher.init(allocator, patch_buf, original_rom_buf),
        .bps => BpsPatcher.init(allocator, patch_buf, original_rom_buf),
    };

    disp.printLoading("validating ROM and patch file");
    patcher.validate();
    disp.clearLine();

    disp.printLoading("patching ROM");
    patcher.apply();
    disp.clearLine();

    // write patched ROM buffer to file
    const patched_rom_path = std.fmt.allocPrint(allocator.*, "{s}.patched.{s}", .{ original_rom_path_base, original_rom_path_ext }) catch fatal("could not allocate memory for patched ROM path");
    defer allocator.free(patched_rom_path);
    const patched_rom_file = std.fs.cwd().createFile(patched_rom_path, .{ .read = true }) catch fatalFmt("could not open patched ROM file \x1b[1m{s}\x1b[0m", .{patched_rom_path});
    var patched_rom_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var patched_rom_file_writer = patched_rom_file.writer(&patched_rom_writer_buf);
    var patched_rom_writer = &patched_rom_file_writer.interface;
    patched_rom_writer.writeAll(patcher.patched_rom.items) catch fatal("could not write patched ROM buffer to file");

    disp.printf("\n\x1b[32mROM file successfully patched to \x1b[0;1m{s}\x1b[0;32m", .{patched_rom_path});
}
