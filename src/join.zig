// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

pub const JoinUtil = struct {
    pub const usage: Usage = .{
        .title = shared.PROGRAM_NAME ++ " join",
        .description = "join multiple binary files into a single output file",
        .usage_lines = &.{
            "<bin-file> <bin-file> [bin-file ...] [options]",
        },
        .sections = &.{
            .{
                .title = "Options",
                .items = &.{
                    .{ .shorthand = "-o", .title = "--out", .arg = "<file>", .description = "specify the file to write to" },
                    .{ .shorthand = "", .title = "--overwrite", .arg = "", .description = "overwrite the first input file with the joined output" },
                    .{ .shorthand = "", .title = "--quiet", .arg = "", .description = "do not output anything to stdout" },
                    .{ .shorthand = "-h", .title = "--help", .arg = "", .description = "display this help text and quit" },
                },
            },
        },
    };
    pub fn init() Util {
        return .{
            .vtable = &.{
                .parseArgs = parseArgs,
                .do = join,
            },
            .usage = usage,
        };
    }
};

const Args = struct {
    in_paths: std.ArrayListUnmanaged([]const u8),
    out_path: []const u8,
    overwrite: bool,
};
const ParseArgsState = enum {
    Init,
    OutPath,
};

var args: Args = .{
    .in_paths = .{},
    .out_path = "",
    .overwrite = false,
};

fn parseArgs(allocator: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    args.in_paths.deinit(allocator.*);
    args.in_paths = .{};
    errdefer args.in_paths.deinit(allocator.*);

    args.out_path = "";
    args.overwrite = false;

    if (args_raw.len == 0) {
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
                    args.in_paths.append(allocator.*, arg) catch fatal("could not allocate memory for input paths");
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

    if (args.in_paths.items.len == 0) {
        return Util.ParseArgsError.MissingRequiredArg;
    }

    if (args.overwrite) {
        args.out_path = args.in_paths.items[0];
    } else if (args.out_path.len == 0) {
        const first_input = args.in_paths.items[0];
        const last_index_of_period = std.mem.lastIndexOfScalar(u8, first_input, '.') orelse first_input.len;
        const base = first_input[0..last_index_of_period];
        const ext = first_input[@min(last_index_of_period + 1, first_input.len)..];
        args.out_path = std.fmt.allocPrint(allocator.*, "{s}.joined.{s}", .{ base, ext }) catch fatal("could not allocate memory for joined output path");
    }
}

fn join(allocator: *const std.mem.Allocator) void {
    var joined_data = std.ArrayListUnmanaged(u8){};
    defer joined_data.deinit(allocator.*);

    var out_file: std.fs.File = undefined;
    var out_file_initialized = false;
    defer if (out_file_initialized) out_file.close();

    disp.printLoading("reading input files");

    for (args.in_paths.items, 0..) |path, idx| {
        const is_output_source = args.overwrite and idx == 0;
        var file = std.fs.cwd().openFile(path, .{
            .mode = if (is_output_source) .read_write else .read_only,
        }) catch fatalFmt("could not open input file \x1b[1m{s}\x1b[0m", .{path});
        defer if (!is_output_source) file.close();

        const file_size_u64 = file.getEndPos() catch fatalFmt("could not determine size of file \x1b[1m{s}\x1b[0m", .{path});
        const file_size = std.math.cast(usize, file_size_u64) orelse fatalFmt("file \x1b[1m{s}\x1b[0m is too large to join", .{path});
        file.seekTo(0) catch fatalFmt("could not seek input file \x1b[1m{s}\x1b[0m", .{path});

        if (file_size != 0) {
            const required_capacity = std.math.add(usize, joined_data.items.len, file_size) catch fatal("joined data would exceed addressable memory");
            joined_data.ensureTotalCapacity(allocator.*, required_capacity) catch fatal("could not allocate memory for joined data");
            const dest = joined_data.addManyAsSlice(allocator.*, file_size) catch fatal("could not grow joined data buffer");

            var total_read: usize = 0;
            while (total_read < dest.len) {
                const read_bytes = file.read(dest[total_read..]) catch fatalFmt("could not read input file \x1b[1m{s}\x1b[0m", .{path});
                if (read_bytes == 0) {
                    fatalFmt("could not read input file \x1b[1m{s}\x1b[0m", .{path});
                }
                total_read += read_bytes;
            }
        }

        if (is_output_source) {
            out_file = file;
            out_file_initialized = true;
        }
    }

    disp.clearLine();

    if (!out_file_initialized) {
        out_file = std.fs.cwd().createFile(args.out_path, .{}) catch fatalFmt("could not create output file \x1b[1m{s}\x1b[0m", .{args.out_path});
        out_file_initialized = true;
    } else {
        out_file.setEndPos(0) catch fatalFmt("could not truncate output file \x1b[1m{s}\x1b[0m", .{args.out_path});
        out_file.seekTo(0) catch fatalFmt("could not seek output file \x1b[1m{s}\x1b[0m", .{args.out_path});
    }

    disp.printLoading("writing output file");

    var writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var writer_core = out_file.writer(&writer_buf);
    var writer = &writer_core.interface;
    writer.writeAll(joined_data.items) catch fatal("could not write joined data to output file");
    writer.flush() catch fatal("could not flush output file");

    disp.clearLine();
    disp.printf("\x1b[32mjoined file written to \x1b[0;1m{s}\x1b[0;32m\n", .{args.out_path});

    args.in_paths.deinit(allocator.*);
    args.in_paths = .{};
}
