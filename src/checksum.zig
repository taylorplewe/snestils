// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const SnesRom = shared.SnesRom;
const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

pub const ChecksumUtil = struct {
    pub const usage: Usage = .{
        .title = "fix-checksum",
        .description = "write a ROM's correct checksum & complement to its header",
        .usage_lines = &.{
            "<rom-file>",
        },
        .sections = &.{},
    };
    pub fn init() Util {
        return .{
            .vtable = &.{ .do = fixChecksum },
            .action_num_args = 1,
            .usage = usage,
        };
    }
};

pub fn fixChecksum(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    const rom_path = args[0];
    const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{rom_path});
    defer rom_file.close();

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    const rom_bin = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not read ROM file into buffer for checksum fixing");
    var rom = SnesRom.fromBin(rom_bin) catch fatal("could not create SnesRom struct from binary");

    // calculate checksum
    disp.printLoading("calculating checksum");
    const checksum = rom.getCalculatedChecksum();
    disp.clearLine();
    disp.printf("checksum: \x1b[33m0x{x}\x1b[0m\n", .{checksum});

    // write checksum to ROM header
    disp.printLoading("writing checksum to ROM header");
    var rom_writer_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_file_writer = rom_file.writer(&rom_writer_buf);
    var rom_writer = &rom_file_writer.interface;

    rom_file_writer.seekTo(rom.header_addr + 0x1c) catch fatal("could not seek file for writing calculated checksum");
    rom_writer.writeInt(u16, ~checksum, .little) catch fatal("could not write checksum complement to ROM file");
    rom_writer.writeInt(u16, checksum, .little) catch fatal("could not write checksum to ROM file");
    rom_writer.flush() catch fatal("could not flush ROM writer");

    disp.clearLine();
    disp.println("\x1b[32mchecksum written to ROM header.\x1b[0m");
}
