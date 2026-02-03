const std = @import("std");
const disp = @import("disp.zig");
const fatal = disp.fatal;
// const developer_ids: [_][]const u8 = @import("developer_ids.zon");

const SnesRomHeader = extern struct {
    title: [21]u8,
    mode: u8,
    chipset: u8,
    size_rom: u8,
    size_ram: u8,
    country: u8,
    publisher_id: u8,
    version: u8,
    checksum_complement: u16,
    checksum: u16,
    interrupt_vectors: [16]u16,
};

const possible_header_addrs: []const u24 = &[_]u24{
    0x007fc0,
    0x00ffc0,
    0x40ffc0,
};

pub fn displayInfo(rom_file: std.fs.File) void {
    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    for (possible_header_addrs) |addr| {
        if (addr > rom_reader_core.getSize() catch unreachable) {
            continue;
        }
        rom_reader_core.seekTo(addr) catch fatal("could not seek file");

        var header = rom_reader.takeStruct(SnesRomHeader, .little) catch fatal("could not read header struct");
        if (checkForHeader(&header)) {
            std.debug.print("Title: {s}\n", .{header.title});
        }
    }
}

fn checkForHeader(header: *SnesRomHeader) bool {
    // ascii name of ROM
    for (header.title) |byte| {
        if (!std.ascii.isAlphabetic(byte) and !std.ascii.isWhitespace(byte) and byte != 0)
            return false;
    }

    // mapper mode byte
    if (header.mode & 0b11100000 != 0b00100000) return false;
    const map_mode = header.mode & 0x0f;
    if (map_mode != 0 and map_mode != 1 and map_mode != 5) return false;

    // hardware info byte
    if (header.chipset != 0 and header.chipset != 1 and header.chipset != 2) {
        if ((header.chipset & 0x0f) > 6) return false;
        if ((header.chipset >> 4) > 0x5 and (header.chipset >> 4) < 0xe) return false;
    }

    // existing checksum & complement
    if (header.checksum ^ header.checksum_complement != 0xffff) return false;

    return true;
}
