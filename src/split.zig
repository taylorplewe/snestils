// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

const usage: Usage = .{
    .title = shared.PROGRAM_NAME ++ " split",
    .description = "split a ROM file into multiple smaller files of a certain maximum size",
    .usage_lines = &.{
        "<rom-file> [options]",
    },
    .sections = &.{
        .{
            .title = "Options",
            .items = &.{
                .{ .shorthand = "-s", .title = "--size", .arg = "<size>", .description = "specify the maximum size in KiB each split file should be (512, 1024 or 2048)" },
                .{ .shorthand = "", .title = "--quiet", .arg = "", .description = "do not output anything to stdout" },
                .{ .shorthand = "-h", .title = "--help", .arg = "", .description = "display this help text and quit" },
            },
        },
    },
};
pub const split_util: Util = .{
    .vtable = &.{
        .parseArgs = parseArgs,
        .do = split,
    },
    .usage = usage,
};

const Args = struct {
    rom_path: []const u8,
    size: ?usize,
};
var args: Args = .{
    .rom_path = "",
    .size = null,
};
const ParseArgsState = enum {
    Init,
    Size,
};
fn parseArgs(_: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len < 1) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    var state: ParseArgsState = .Init;
    for (args_raw) |arg| {
        switch (state) {
            .Init => {
                if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--size")) {
                    state = .Size;
                } else {
                    if (args.rom_path.len == 0) {
                        args.rom_path = arg;
                    } else {
                        return Util.ParseArgsError.TooManyArgs;
                    }
                }
            },
            .Size => {
                const num = std.fmt.parseInt(usize, arg, 10) catch return Util.ParseArgsError.InvalidArgFormat;
                if (num == 512 or num == 1024 or num == 2048) {
                    args.size = num;
                } else {
                    return Util.ParseArgsError.InvalidArgFormat;
                }
                state = .Init;
            },
        }
    }
    if (state == .Size) {
        return Util.ParseArgsError.MissingParameterArg;
    }
    if (args.rom_path.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
}

fn split(allocator: *const std.mem.Allocator) void {
    const rom_file = std.fs.cwd().openFile(args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{args.rom_path});

    // get size in KiB from user
    const targ_size = blk: {
        if (args.size == null) {
            while (true) {
                var reader_buf: [1024]u8 = undefined;
                var stdin_core = std.fs.File.stdin().reader(&reader_buf);
                var stdin = &stdin_core.interface;

                disp.println("What size KiB chunks (512, 1024, or 2048)? ");
                var targ_size_input: []u8 = undefined;
                targ_size_input = stdin.takeDelimiter('\n') catch fatal("could not read input from user") orelse &.{};
                const input = std.fmt.parseInt(usize, std.mem.trimRight(u8, targ_size_input, " \n\r"), 10) catch {
                    disp.println("please provide a numeric value!");
                    continue;
                };
                if (input == 512 or input == 1024 or input == 2048) break :blk input;
                disp.println("please provide a valid KiB size!");
            }
        } else {
            break :blk args.size.?;
        }
    } * 1024; // KiB

    // get file size
    var remaining_size = rom_file.getEndPos() catch fatal("could not get size of file");
    if (remaining_size <= targ_size) {
        disp.printf("ROM file is already smaller or equal to {d} bytes!", .{targ_size});
        return;
    }

    // separate rom file extension from main part
    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, args.rom_path, '.')) |idx| idx else args.rom_path.len;
    const rom_file_name_base = args.rom_path[0..last_index_of_period];
    const rom_file_ext = args.rom_path[last_index_of_period..];

    var rom_reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_file_reader = rom_file.readerStreaming(&rom_reader_buf);
    var rom_reader = &rom_file_reader.interface;

    disp.printLoading("writing ROM data to split files");
    var iter: u8 = 0;
    while (remaining_size > 0) : (remaining_size -= targ_size) {
        const split_file_path = std.fmt.allocPrint(allocator.*, "{s}.split_{d:0>2}{s}", .{ rom_file_name_base, iter, rom_file_ext }) catch unreachable;
        const split_file = std.fs.cwd().createFile(split_file_path, .{}) catch
            fatalFmt("could not create split file {s}", .{split_file_path});
        defer split_file.close();

        var split_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
        var split_file_writer = split_file.writer(&split_writer_buf);

        rom_reader.streamExact(&split_file_writer.interface, targ_size) catch fatalFmt("could not stream data from {s} to {s}", .{ args.rom_path, split_file_path });
        split_file_writer.interface.flush() catch fatalFmt("could not flush writer for file {s}", .{split_file_path});

        iter += 1;
    }
    disp.clearLine();
    disp.println("\x1b[32msplit ROM files written to same directory as given ROM file.\x1b[0m");
}

test split {
    // arrange
    const split_rom_bin = @embedFile("shared/testing/sutah.split_00.sfc");
    const split_rom_crc32 = std.hash.Crc32.hash(split_rom_bin);
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    try std.fs.cwd().copyFile("src/shared/testing/sutah.sfc", tmp_dir.dir, "sutah.sfc", .{});
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    const rom_path = try std.fs.path.join(allocator, &.{ tmp_path, "sutah.sfc" });
    args = .{
        .rom_path = rom_path,
        .size = 32,
    };
    defer {
        tmp_dir.cleanup();
        allocator.free(tmp_path);
        allocator.free(rom_path);
    }

    // act
    var arena = std.heap.ArenaAllocator.init(allocator);
    split(&arena.allocator());
    arena.deinit();

    // assert
    for ([_][]const u8{
        "sutah.split_00.sfc",
        "sutah.split_01.sfc",
        "sutah.split_02.sfc",
        "sutah.split_03.sfc",
    }) |path| {
        try tmp_dir.dir.access(path, .{});
    }
    const new_rom_bin = try shared.testing.getBinFromFilePath(&allocator, &tmp_dir.dir, "sutah.split_00.sfc");
    defer allocator.free(new_rom_bin);
    const new_rom_crc32 = std.hash.Crc32.hash(new_rom_bin);
    try std.testing.expectEqual(split_rom_crc32, new_rom_crc32);
}
