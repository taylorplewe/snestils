const std = @import("std");
const disp = @import("disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

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

const possible_header_addrs: []const u24 = &[_]u24{
    0x007fc0,
    0x00ffc0,
    0x40ffc0,
};
pub fn fixChecksum(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    const rom_path = args[0];
    const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{rom_path});

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;
    const rom = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not read ROM file into buffer for checksum fixing");

    // calculate checksum
    disp.printLoading("calculating checksum");
    const checksum = calcChecksum(rom);
    disp.clearAndPrint("checksum: \x1b[33m0x{x}\x1b[0m\n", .{checksum});

    // write checksum to ROM header
    disp.printLoading("writing checksum to ROM header");
    var header_buf: [32]u8 = undefined;
    for (possible_header_addrs) |addr| {
        rom_reader_core.seekTo(addr) catch fatal("could not seek file");
        _ = rom_reader.readSliceShort(&header_buf) catch fatal("could not read header into buffer");
        if (checkForHeader(&header_buf)) {
            var rom_writer_buf: [1024]u8 = undefined;
            var rom_writer_core = rom_file.writer(&rom_writer_buf);
            var rom_writer = &rom_writer_core.interface;
            rom_writer_core.seekTo(addr + 0x1c) catch fatal("could not seek file for writing");
            rom_writer.writeInt(u16, checksum ^ 0xffff, std.builtin.Endian.little) catch fatal("could not write checksum complement to file");
            rom_writer.writeInt(u16, checksum, std.builtin.Endian.little) catch fatal("could not write checksum to file");
            rom_writer.flush() catch fatal("could not flush ROM writer");
            disp.clearAndPrint("\x1b[32mchecksum written to ROM header.\x1b[0m\n", .{});

            return;
        }
    }
    fatal("could not find header in ROM\n  a ROM header must meet the criteria as described at \x1b]8;;https://snes.nesdev.org/wiki/ROM_header\x1b\\https://snes.nesdev.org/wiki/ROM_header\x1b]8;;\x1b\\");
}

pub fn calcChecksum(rom: []u8) u16 {
    var checksum: u16 = 0;
    for (rom) |byte| {
        checksum +%= byte;
    }

    // ROM size must be a power of 2 for checksum calculation; a portion might have to be duplicated
    if (rom.len & (rom.len - 1) != 0) {
        // find the largest power of 2 less than or equal to rom.len
        var power_of_2: usize = 1024 * 1024 * 8; // 8MB; biggest game ever released was 6MB
        while (power_of_2 > rom.len) power_of_2 >>= 1;
        const duplicated_section = rom[power_of_2..];
        const num_times_to_duplicate = (power_of_2 / (rom.len - power_of_2)) - 1;
        for (0..num_times_to_duplicate) |_| {
            for (duplicated_section) |byte| {
                checksum +%= byte;
            }
        }
    }

    return checksum;
}

fn checkForHeader(memory: []u8) bool {
    // ascii name of ROM
    for (memory[0..0x15]) |byte| {
        if (!std.ascii.isAlphabetic(byte) and !std.ascii.isWhitespace(byte) and byte != 0)
            return false;
    }

    // mapper mode byte
    if (memory[0x15] & 0b11100000 != 0b00100000) return false;
    const map_mode = memory[0x15] & 0x0f;
    if (map_mode != 0 and map_mode != 1 and map_mode != 5) return false;

    // hardware info byte
    const hardware = memory[0x16];
    if (hardware != 0 and hardware != 1 and hardware != 2) {
        if ((hardware & 0x0f) > 6) return false;
        if ((hardware >> 4) > 0x5 and (hardware >> 4) < 0xe) return false;
    }

    // existing checksum & complement
    if (memory[0x1c] ^ memory[0x1e] != 0xff or memory[0x1d] ^ memory[0x1f] != 0xff) return false;

    return true;
}
