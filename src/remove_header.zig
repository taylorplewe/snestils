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
    .title = shared.PROGRAM_NAME ++ " remove-header",
    .description = "remove a ROM's 512-byte copier device header, if it has one",
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
pub const remove_header_util: Util = .{
    .vtable = &.{
        .parseArgs = parseArgs,
        .do = removeHeader,
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
        args.out_path = std.fmt.allocPrint(allocator.*, "{s}.noheader.{s}", .{ original_rom_path_base, original_rom_path_ext }) catch fatal("could not allocate memory for patched ROM path");
    }
}

fn removeHeader(allocator: *const std.mem.Allocator) void {
    const rom_file = std.fs.cwd().openFile(args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{args.rom_path});
    defer rom_file.close();

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    const rom_bin = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not read ROM file into buffer for checksum fixing");
    var rom = SnesRom.fromBin(rom_bin) catch fatal("could not create SnesRom struct from binary. Is it a valid SNES ROM file?");

    if (!rom.hasCopierHeader()) {
        disp.println("ROM does not appear to have a copier header!\n\x1b[34mNote:\x1b[0m a header added by a copier device is 512 bytes long and lives at the beginning of ROM data. For more details, see https://snes.nesdev.org/wiki/ROM_file_formats#Detecting_Headered_ROM");
        return;
    }

    const data_without_header = rom_bin[512..];

    // write checksum to ROM header
    disp.printLoading("writing headerless data to ROM file");
    const out_file = if (!args.overwrite and !std.mem.eql(u8, args.rom_path, args.out_path))
        std.fs.cwd().createFile(args.out_path, .{}) catch fatalFmt("could not open out file {s}", .{args.out_path})
    else
        rom_file;
    var out_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var out_file_writer = out_file.writer(&out_writer_buf);
    var out_writer = &out_file_writer.interface;

    _ = out_writer.write(data_without_header) catch fatal("could not write headerless data to destination ROM file");
    out_writer.flush() catch fatal("could not flush ROM writer");

    disp.clearLine();
    disp.println("\x1b[32mheaderless data written to ROM file.\x1b[0m");
}

test removeHeader {}
