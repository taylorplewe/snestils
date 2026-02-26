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
    .title = shared.PROGRAM_NAME ++ " join",
    .description = "join multiple binary files into a single output file",
    .usage_lines = &.{
        "<bin-file> [<bin-file> ...] [options]",
    },
    .sections = &.{
        .{
            .title = "Options",
            .items = &.{
                .{ .shorthand = "-o", .title = "--out", .arg = "<file>", .description = "specify the file to write to" },
                .{ .shorthand = "", .title = "--quiet", .arg = "", .description = "do not output anything to stdout" },
                .{ .shorthand = "-h", .title = "--help", .arg = "", .description = "display this help text and quit" },
            },
        },
    },
};
pub const join_util: Util = .{
    .vtable = &.{
        .parseArgs = parseArgs,
        .do = join,
    },
    .usage = usage,
};

const Args = struct {
    in_paths: [][:0]const u8,
    out_path: []const u8,
};
var args: Args = .{
    .in_paths = &.{},
    .out_path = "",
};
const ParseArgsState = enum {
    Init,
    OutPath,
};
fn parseArgs(allocator: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    var in_paths: std.ArrayList([:0]const u8) = .empty;

    if (args_raw.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }

    var state: ParseArgsState = .Init;
    for (args_raw) |arg| {
        switch (state) {
            .Init => {
                if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--out")) {
                    state = .OutPath;
                } else {
                    in_paths.append(allocator.*, arg) catch fatal("could not allocate memory for input paths");
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

    if (in_paths.items.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    args.in_paths = in_paths.items;

    if (args.out_path.len == 0) {
        const first_input = args.in_paths[0];
        const last_index_of_period = std.mem.lastIndexOfScalar(u8, first_input, '.') orelse first_input.len;
        const base = first_input[0..last_index_of_period];
        const ext = first_input[@min(last_index_of_period + 1, first_input.len)..];
        args.out_path = std.fmt.allocPrint(allocator.*, "{s}.joined.{s}", .{ base, ext }) catch fatal("could not allocate memory for joined output path");
    }
}

fn join(allocator: *const std.mem.Allocator) void {
    var joined_writer: std.Io.Writer.Allocating = .init(allocator.*);
    defer joined_writer.deinit();

    disp.printLoading("reading input files into joined data buffer");
    var file_stream_buf: [std.math.maxInt(u16)]u8 = undefined;
    for (args.in_paths) |path| {
        var in_file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch fatalFmt("could not open input file \x1b[1m{s}\x1b[0m", .{path});
        defer in_file.close();

        var in_file_reader = in_file.readerStreaming(&file_stream_buf);
        var in_reader = &in_file_reader.interface;

        _ = in_reader.streamRemaining(&joined_writer.writer) catch fatalFmt("could not stream data from {s} to joined data buffer writer", .{path});
    }
    disp.clearLine();

    disp.printLoading("writing joined data to output file");
    const joined_rom_file = std.fs.cwd().createFile(args.out_path, .{}) catch fatalFmt("could not open out file {s}", .{args.out_path});
    var joined_rom_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var joined_rom_file_writer = joined_rom_file.writer(&joined_rom_writer_buf);
    var joined_rom_writer = &joined_rom_file_writer.interface;
    joined_rom_writer.writeAll(joined_writer.written()) catch fatal("could not write joined ROM buffer to file");
    disp.clearLine();
    disp.printf("\x1b[32mjoined file written to \x1b[0;1m{s}\x1b[0;32m\n", .{args.out_path});
}

test join {
    // arrange
    const joined_rom_bin = @embedFile("shared/testmatter/sutah.sfc");
    const joined_rom_crc32 = std.hash.Crc32.hash(joined_rom_bin);
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    var in_paths: std.ArrayList([:0]const u8) = .empty;
    inline for ([_][]const u8{
        "sutah.split_00.sfc",
        "sutah.split_01.sfc",
        "sutah.split_02.sfc",
        "sutah.split_03.sfc",
    }) |path| {
        try std.fs.cwd().copyFile("src/shared/testmatter/" ++ path, tmp_dir.dir, path, .{});
        try in_paths.append(allocator, try std.fs.path.joinZ(allocator, &.{ tmp_path, path }));
    }
    const out_path = try std.fs.path.join(allocator, &.{ tmp_path, "sutah.joined.sfc" });
    args = .{
        .in_paths = try in_paths.toOwnedSlice(allocator),
        .out_path = out_path,
    };
    defer {
        tmp_dir.cleanup();
        allocator.free(tmp_path);
        for (args.in_paths) |path| {
            allocator.free(path);
        }
        allocator.free(args.in_paths);
        allocator.free(args.out_path);
    }

    // act
    var arena = std.heap.ArenaAllocator.init(allocator);
    join(&arena.allocator());
    arena.deinit();

    // assert
    try tmp_dir.dir.access("sutah.joined.sfc", .{});
    const new_rom_file = try tmp_dir.dir.openFile("sutah.joined.sfc", .{ .mode = .read_only });
    defer new_rom_file.close();
    try std.testing.expectEqual(try new_rom_file.getEndPos(), 128 * 1024);
    var new_rom_reader_buf: [1024]u8 = undefined;
    var new_rom_file_reader = new_rom_file.reader(&new_rom_reader_buf);
    var new_rom_reader = &new_rom_file_reader.interface;
    const new_rom_bin = try new_rom_reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(new_rom_bin);
    const new_rom_crc32 = std.hash.Crc32.hash(new_rom_bin);
    try std.testing.expectEqual(joined_rom_crc32, new_rom_crc32);
}
