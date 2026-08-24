// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const SnesRom = shared.SnesRom;

const Util = @import("Util.zig");
const Usage = @import("Usage.zig");

const usage: Usage = .{
    .title = shared.PROGRAM_NAME ++ " add-header",
    .description = "add a dummy 512-byte copier device header full of 0's; helpful for patch files which require headered ROMs",
    .usage_lines = &.{
        "<rom-file> [options]",
    },
    .sections = &.{
        .{
            .title = "Options",
            .items = &.{
                .{ .shorthand = "-o", .title = "--out", .arg = "<file>", .description = "specify the file to write to" },
                .{ .shorthand = "", .title = "--overwrite", .arg = "", .description = "overwrite the original ROM file when fixing the checksum" },
                .{ .shorthand = "", .title = "--quiet", .arg = "", .description = "do not output anything to stdout" },
                .{ .shorthand = "-h", .title = " --help", .arg = "", .description = "display this help text and quit" },
            },
        },
    },
};
pub const add_header_util: Util = .{
    .vtable = &.{
        .parseArgs = parseArgs,
        .do = addHeader,
    },
    .usage = usage,
};

const Args = struct {
    rom_path: []const u8,
    out_path: []const u8,
    overwrite: bool,
};
var args: Args = .{
    .rom_path = "",
    .out_path = "",
    .overwrite = false,
};
const ParseArgsState = enum {
    Init,
    OutPath,
};
fn parseArgs(allocator: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len < 1) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    var state: ParseArgsState = .Init;
    for (args_raw) |arg| {
        switch (state) {
            .Init => {
                if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--out")) {
                    state = .OutPath;
                } else if (std.mem.eql(u8, arg, "--overwrite")) {
                    args.overwrite = true;
                } else {
                    if (args.rom_path.len == 0) {
                        args.rom_path = arg;
                    } else {
                        return Util.ParseArgsError.TooManyArgs;
                    }
                }
            },
            .OutPath => {
                args.out_path = arg;
                state = .Init;
            },
        }
    }
    if (state == .OutPath) {
        return Util.ParseArgsError.MissingParameterArg;
    }
    if (args.rom_path.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    if (args.overwrite) {
        args.out_path = args.rom_path;
    } else if (args.out_path.len == 0) {
        // default out filepath
        const original_rom_path_last_index_of_period = std.mem.lastIndexOfScalar(u8, args.rom_path, '.') orelse args.rom_path.len;
        const original_rom_path_base = args.rom_path[0..original_rom_path_last_index_of_period];
        const original_rom_path_ext = args.rom_path[@min(original_rom_path_last_index_of_period + 1, args.rom_path.len)..];
        args.out_path = std.fmt.allocPrint(allocator.*, "{s}.headered.{s}", .{ original_rom_path_base, original_rom_path_ext }) catch fatal("could not allocate memory for patched ROM path");
    }
}

fn addHeader(io: std.Io, allocator: *const std.mem.Allocator) void {
    const rom_file = std.Io.Dir.cwd().openFile(io, args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{args.rom_path});
    defer rom_file.close(io);

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(io, &reader_buf);
    var rom_reader = &rom_reader_core.interface;

    const rom_bin = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not read ROM file into buffer for checksum fixing");
    var rom = SnesRom.fromBin(rom_bin) catch fatal("could not create SnesRom struct from binary. Is it a valid SNES ROM file?");

    if (rom.hasCopierHeader()) {
        disp.println("ROM already has a copier header!\n\x1b[34mNote:\x1b[0m a header added by a copier device is 512 bytes long and lives at the beginning of ROM data. For more details, see https://snes.nesdev.org/wiki/ROM_file_formats#Detecting_Headered_ROM");
        return;
    }

    const data_without_header = rom_bin;

    // write checksum to ROM header
    disp.printLoading("writing headerless data to ROM file");
    const out_file = if (!args.overwrite and !std.mem.eql(u8, args.rom_path, args.out_path))
        std.Io.Dir.cwd().createFile(io, args.out_path, .{}) catch fatalFmt("could not open out file {s}", .{args.out_path})
    else
        rom_file;
    var out_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var out_file_writer = out_file.writer(io, &out_writer_buf);
    var out_writer = &out_file_writer.interface;

    out_writer.splatByteAll(0, 512) catch fatal("could not write blank copier header to beginning of destination ROM file");
    out_writer.flush() catch fatal("could not flush ROM writer");

    _ = out_writer.write(data_without_header) catch fatal("could not write headerless data to destination ROM file");
    out_writer.flush() catch fatal("could not flush ROM writer");

    disp.clearLine();
    disp.println("\x1b[32mempty copier header prepended to ROM file.\x1b[0m");
}

test addHeader {
    // arrange
    const headered_rom_bin = @embedFile("shared/testing/sutah_with_copier_header.sfc");
    const headered_rom_crc32 = std.hash.Crc32.hash(headered_rom_bin);
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    try std.Io.Dir.cwd().copyFile(
        "src/shared/testing/sutah.sfc",
        tmp_dir.dir,
        "sutah.noheader.sfc",
        std.testing.io,
        .{},
    );
    const tmp_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    const rom_path = try std.fs.path.join(allocator, &.{ tmp_path, "sutah.noheader.sfc" });
    const out_path = try std.fs.path.join(allocator, &.{ tmp_path, "sutah.headered.sfc" });
    args = .{
        .rom_path = rom_path,
        .out_path = out_path,
        .overwrite = false,
    };
    defer {
        tmp_dir.cleanup();
        allocator.free(tmp_path);
        allocator.free(rom_path);
        allocator.free(out_path);
    }

    // act
    var arena = std.heap.ArenaAllocator.init(allocator);
    addHeader(std.testing.io, &arena.allocator());
    arena.deinit();

    // assert
    const new_rom_bin = try shared.testing.getBinFromFilePath(
        std.testing.io,
        &allocator,
        &tmp_dir.dir,
        "sutah.headered.sfc",
    );
    defer allocator.free(new_rom_bin);
    const new_rom_crc32 = std.hash.Crc32.hash(new_rom_bin);
    try std.testing.expectEqual(headered_rom_crc32, new_rom_crc32);
}
