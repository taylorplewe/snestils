// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

pub const SplitUtil = struct {
    pub const usage: Usage = .{
        .title = "split",
        .description = "split a ROM file into multiple smaller files of a certain maximum size",
        .usage_lines = &.{
            "<rom-file> [options]",
        },
        .sections = &.{
            .{
                .title = "Options",
                .items = &.{
                    .{ .title = "-h, --help", .description = "display this help text and quit" },
                },
            },
        },
    };
    pub fn init() Util {
        return .{
            .vtable = &.{
                .parseArgs = parseArgs,
                .do = split,
            },
            .usage = usage,
        };
    }
};

const Args = struct {
    rom_path: []const u8,
};
var args: Args = .{
    .rom_path = "",
};
fn parseArgs(_: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len != 1) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    args = .{
        .rom_path = args_raw[0],
    };
}

fn split(allocator: *const std.mem.Allocator) void {
    const rom_file = std.fs.cwd().openFile(args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{args.rom_path});

    // get size in KiB from user
    var targ_size_input: []u8 = undefined;
    var targ_size: u64 = 0;
    while (true) {
        var reader_buf: [1024]u8 = undefined;
        var stdin_core = std.fs.File.stdin().reader(&reader_buf);
        var stdin = &stdin_core.interface;

        disp.println("What size KiB chunks (512, 1024, or 2048)? ");
        targ_size_input = stdin.takeDelimiter('\n') catch fatal("could not read input from user") orelse &.{};
        targ_size = std.fmt.parseInt(u64, std.mem.trimRight(u8, targ_size_input, "\n\r"), 10) catch {
            disp.println("please provide a numeric value!");
            continue;
        };
        if (targ_size == 512 or targ_size == 1024 or targ_size == 2048) break;
        disp.println("please provide a valid KiB size!");
    }
    targ_size *= 1024; // KiB

    // get file size
    rom_file.seekFromEnd(0) catch unreachable;
    var remaining_size = rom_file.getPos() catch fatal("could not get size of file");
    if (remaining_size < targ_size) {
        disp.printf("ROM file is already smaller or equal to {d} bytes!", .{targ_size});
        std.process.exit(0);
    }

    // write split files
    rom_file.seekTo(0) catch unreachable;
    const buf = allocator.alloc(u8, targ_size) catch fatal("could not allocate buffer");
    var iter: u8 = 0;

    // separate rom file extension from main part
    const last_index_of_period = if (std.mem.lastIndexOfScalar(u8, args.rom_path, '.')) |idx| idx else args.rom_path.len;
    const rom_file_name_base = args.rom_path[0..last_index_of_period];
    const rom_file_ext = args.rom_path[last_index_of_period..];

    while (remaining_size > 0) : (remaining_size -= targ_size) {
        const split_file_path = std.fmt.allocPrint(allocator.*, "{s}_{d:0>2}{s}", .{ rom_file_name_base, iter, rom_file_ext }) catch unreachable;
        const split_file = std.fs.cwd().createFile(split_file_path, .{}) catch
            fatalFmt("could not create split file {s}", .{split_file_path});
        defer split_file.close();
        _ = rom_file.read(buf) catch fatal("could not read ROM file into split buffer");
        _ = split_file.write(buf) catch fatal("could not write split buffer into split file");
        iter += 1;
    }
    disp.println("\x1b[32msplit ROM files written to same directory as given ROM file.\x1b[0m");
}
