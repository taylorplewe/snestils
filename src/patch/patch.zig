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
            "<rom-file> [-p|--patch] <patch-file> [options]",
            "<rom-file> [-p|--patch] <patch-file> (-o|--out) <out-file> [options]",
        },
        .sections = &.{
            .{
                .title = "Options",
                .items = &.{
                    .{ .title = "--overwrite", .description = "overwrite the original ROM file with the patched version" },
                },
            },
        },
    };
    pub fn init() Util {
        return .{
            .vtable = &.{
                .parseArgs = parseArgs,
                .do = patch,
            },
            .usage = usage,
        };
    }
};
const Args = struct {
    rom_path: []const u8,
    patch_path: []const u8,
    out_path: []const u8,
    overwrite: bool,
};
const ParseArgsState = enum {
    Init,
    PatchPath,
    OutPath,
};
var args: Args = .{
    .rom_path = "",
    .patch_path = "",
    .out_path = "",
    .overwrite = false,
};
fn parseArgs(allocator: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len < 1) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    var state: ParseArgsState = .Init;
    for (args_raw) |arg| {
        switch (state) {
            .Init => {
                if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--patch")) {
                    state = .PatchPath;
                } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--out")) {
                    state = .OutPath;
                } else if (std.mem.eql(u8, arg, "--overwrite")) {
                    args.overwrite = true;
                } else {
                    if (args.rom_path.len == 0) {
                        args.rom_path = arg;
                    } else if (args.patch_path.len == 0) {
                        args.patch_path = arg;
                    } else {
                        return Util.ParseArgsError.TooManyArgs;
                    }
                }
            },
            .PatchPath => {
                args.patch_path = arg;
                state = .Init;
            },
            .OutPath => {
                args.out_path = arg;
                state = .Init;
            },
        }
    }
    if (state == .OutPath or state == .PatchPath) {
        return Util.ParseArgsError.MissingParameterArg;
    }
    if (args.rom_path.len == 0 or args.patch_path.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    if (args.overwrite) {
        args.out_path = args.rom_path;
    } else if (args.out_path.len == 0) {
        // default out filepath
        const original_rom_path_last_index_of_period = std.mem.lastIndexOfScalar(u8, args.rom_path, '.') orelse args.rom_path.len;
        const original_rom_path_base = args.rom_path[0..original_rom_path_last_index_of_period];
        const original_rom_path_ext = args.rom_path[(original_rom_path_last_index_of_period + 1)..];
        args.out_path = std.fmt.allocPrint(allocator.*, "{s}.patched.{s}", .{ original_rom_path_base, original_rom_path_ext }) catch fatal("could not allocate memory for patched ROM path");
    }
}

fn patch(allocator: *const std.mem.Allocator) void {
    // patch file I/O
    const patch_path_ext = args.patch_path[((std.mem.lastIndexOfScalar(u8, args.patch_path, '.') orelse args.patch_path.len) + 1)..];
    const patch_file_format = std.meta.stringToEnum(PatchFormat, patch_path_ext) orelse fatalFmt("unsupported patch file extension \x1b[1m{s}\x1b[0m", .{patch_path_ext});
    const patch_file = std.fs.cwd().openFile(args.patch_path, .{ .mode = .read_only }) catch fatalFmt("could not open patch file \x1b[1m{s}\x1b[0m", .{args.patch_path});
    var patch_reader_buf: [2048]u8 = undefined;
    var patch_file_reader = patch_file.reader(&patch_reader_buf);
    var patch_reader = &patch_file_reader.interface;
    const patch_buf = patch_reader.allocRemaining(allocator.*, .limited(MAX_ALLOC_SIZE)) catch fatal("could not allocate buffer from patch file");

    // original ROM I/O
    const original_rom_file = std.fs.cwd().openFile(args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open original ROM file \x1b[1m{s}\x1b[0m", .{args.rom_path});
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
    const patched_rom_file = if (args.overwrite) original_rom_file else std.fs.cwd().createFile(args.out_path, .{}) catch fatalFmt("could not open out file {s}", .{args.out_path});
    var patched_rom_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var patched_rom_file_writer = patched_rom_file.writer(&patched_rom_writer_buf);
    var patched_rom_writer = &patched_rom_file_writer.interface;
    patched_rom_writer.writeAll(patcher.patched_rom.items) catch fatal("could not write patched ROM buffer to file");

    disp.printf("\n\x1b[32mROM file successfully patched to \x1b[0;1m{s}\x1b[0;32m", .{args.out_path});
}
