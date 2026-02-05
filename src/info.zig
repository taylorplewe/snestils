const std = @import("std");
const disp = @import("disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");
const checksum = @import("checksum.zig");
// const developer_ids: [_][]const u8 = @import("developer_ids.zon");

const KEY_WIDTH = 20;
const KEY_WIDTH_FMT = std.fmt.comptimePrint("{d}", .{KEY_WIDTH});

const SnesRomHeader = extern struct {
    title: [21]u8,
    mode: u8,
    chipset: u8,
    size_rom: u8,
    size_ram: u8,
    region: Region,
    publisher_id: u8,
    version: u8,
    checksum_complement: u16,
    checksum: u16,
    interrupt_vectors: [16]u16,
};
const FormatSpecifier = enum {
    String,
    HexNumber,
    VersionNumber,
    RomSize,
    RamSize,
};
/// Follows naming convention from the official SNES development manual page 1-2-20
const Region = enum(u8) {
    Japan,
    NorthAmerica,
    AllOfEurope,
    Scandinavia,
    French = 6,
    Dutch,
    Spanish,
    German,
    Italian,
    Chinese,
    Korean,
    Common,
    Canada,
    Brazil,
    Australia,
    OtherX,
    OtherY,
    OtherZ,

    fn getDisplayName(self: Region) []const u8 {
        return switch (self) {
            .Japan => "NTSC (Japan)",
            .NorthAmerica => "NTSC (North America)",
            .AllOfEurope => "PAL (Europe)",
            .Scandinavia => "PAL (Scandinavia)",
            .French => "PAL (French)",
            .Dutch => "PAL (Dutch)",
            .Spanish => "PAL (Spanish)",
            .German => "PAL (German)",
            .Italian => "PAL (Italian)",
            .Chinese => "PAL (Chinese)",
            .Korean => "NTSC (Korean)",
            .Common => "Common",
            .Canada => "NTSC (Canada)",
            .Brazil => "PAL (Brazil)",
            .Australia => "PAL (Australia)",
            else => "Other",
        };
    }
};

pub const InfoUtil = struct {
    pub const usage: Usage = .{
        .title = "info",
        .description = "print out information about a ROM",
        .usage_lines = &.{
            "<rom>",
        },
        .sections = &.{},
    };
    pub fn init() Util {
        return .{
            .vtable = &.{ .do = displayInfo },
            .action_num_args = 1,
            .usage = usage,
        };
    }
};

const possible_header_addrs: []const u24 = &[_]u24{
    0x40ffc0,
    0x00ffc0,
    0x007fc0,
};

pub fn displayInfo(allocator: *const std.mem.Allocator, args: [][:0]u8) void {
    const rom_path = args[0];
    const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{rom_path});

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    for (possible_header_addrs) |addr| {
        if (addr > rom_reader_core.getSize() catch fatal("could not get size of ROM file")) {
            continue;
        }
        rom_reader_core.seekTo(addr) catch fatal("could not seek file");

        var header = rom_reader.takeStruct(SnesRomHeader, .little) catch continue;
        if (checkForHeader(&header)) {
            rom_reader_core.seekTo(0) catch fatal("could not reset seek position of ROM reader");
            const rom = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not allocate buffer for ROM file");
            defer allocator.free(rom);

            disp.clearAndPrint("\n{s:>" ++ KEY_WIDTH_FMT ++ "}\n\n", .{"Header"});

            const internal_rom_size_kilobytes = @as(u32, 1) << @as(u5, @intCast(header.size_rom));
            const internal_ram_size_kilobytes = @as(u32, 1) << @as(u5, @intCast(header.size_ram));
            const internal_rom_size_megabits = (internal_rom_size_kilobytes * 8) / 1024;
            const internal_ram_size_kilobits = internal_ram_size_kilobytes * 8;
            const physical_rom_size_megabits = (((rom.len * 8) / 1024) / 1024);
            displayInfoRow("Title", .String, &header.title);
            displayInfoRow("Version", .VersionNumber, header.version);
            displayInfoRow("Region", .String, header.region.getDisplayName());
            displayInfoRow("ROM size", .RomSize, physical_rom_size_megabits);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal: \x1b[1m{d}\x1b[0m Mb\n", .{internal_rom_size_megabits});
            displayInfoRow("RAM size", .RamSize, internal_ram_size_kilobits);
            displayInfoRow("Mapping", .String, getMappingString(header.mode));
            displayInfoRow("Speed", .String, getSpeedString(header.mode));
            displayInfoRow("Chipset", .String, getChipsetString(header.chipset));

            // compare internal checksum to calculated checksum
            const checksum_calculated = checksum.calcChecksum(rom);
            const checksum_compl_calculated = checksum_calculated ^ 0xffff;
            const OK = "\x1b[32;1mOK\x1b[0m";
            const BAD = "\x1b[31;1mBAD\x1b[0m";
            displayInfoRow("Checksum", .String, if (checksum_calculated == header.checksum) OK else BAD);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[1m0x{x:0>4}\x1b[0m\n", .{checksum_calculated});
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[1m0x{x:0>4}\x1b[0m\n", .{header.checksum});
            displayInfoRow("Checksum complement", .String, if (checksum_compl_calculated == header.checksum_complement) OK else BAD);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[1m0x{x:0>4}\x1b[0m\n", .{checksum_compl_calculated});
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[1m0x{x:0>4}\x1b[0m\n", .{header.checksum_complement});

            disp.clearAndPrint("\n\n{s:>" ++ KEY_WIDTH_FMT ++ "}\n\n", .{"Hashes"});
            disp.printLoading("calculating hashes");

            // get various hashes of ROM data
            var md5: [16]u8 = undefined;
            var sha1: [20]u8 = undefined;
            var sha256: [32]u8 = undefined;
            const crc32 = std.hash.Crc32.hash(rom);
            std.crypto.hash.Md5.hash(rom, &md5, .{});
            std.crypto.hash.Sha1.hash(rom, &sha1, .{});
            std.crypto.hash.sha2.Sha256.hash(rom, &sha256, .{});
            displayInfoRow("CRC32", .HexNumber, crc32);
            displayInfoRow("MD5", .HexNumber, md5);
            displayInfoRow("SHA1", .HexNumber, sha1);
            displayInfoRow("SHA256", .HexNumber, sha256);

            disp.clearAndPrint("\n", .{});

            return;
        }
    }

    fatal("SNES ROM header was not found at any of the expected addresses");
}

fn checkForHeader(header: *SnesRomHeader) bool {
    // ascii name of ROM
    // std.debug.print("title: {s}\n", .{header.title});
    // std.debug.print("hex title: {x}\n", .{header.title});
    for (header.title) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and !std.ascii.isWhitespace(byte) and byte != 0)
            return false;
    }
    // std.debug.print("here\n", .{});

    // mapper mode byte
    if (header.mode & 0b11100000 != 0b00100000) return false;
    // std.debug.print("here 2\n", .{});
    const map_mode = header.mode & 0x0f;
    // std.debug.print("map mode: {d}\n", .{map_mode});
    // std.debug.print("header.mode: {x}\n", .{header.mode});
    if (map_mode != 0 and map_mode != 1 and map_mode != 5) return false;

    // std.debug.print("here 3\n", .{});

    // hardware info byte
    if (header.chipset != 0 and header.chipset != 1 and header.chipset != 2) {
        if ((header.chipset & 0x0f) > 6) return false;
        if ((header.chipset >> 4) > 0x5 and (header.chipset >> 4) < 0xe) return false;
    }

    // existing checksum & complement
    if (header.checksum ^ header.checksum_complement != 0xffff) return false;

    return true;
}

inline fn getMappingString(mode: u8) []const u8 {
    return if (mode & 0x0f == 0)
        "LoROM"
    else if (mode & 0x0f == 1)
        "HiROM"
    else if (mode & 0x0f == 5)
        "ExHiROM"
    else
        "Unknown";
}

inline fn getSpeedString(mode: u8) []const u8 {
    return if (mode & 0b0001_0000 != 0)
        "FastROM"
    else
        "SlowROM";
}

inline fn getChipsetString(chipset: u8) []u8 {
    const coprocessor = chipset >> 4;
    const chipset_type = chipset & 0xf;

    var chipset_string_buf: [1024]u8 = undefined;

    const coprocessor_string: []const u8 = if (chipset_type == 3 or chipset_type == 4 or chipset_type == 5 or chipset_type == 6) switch (coprocessor) {
        0x00 => "DSP",
        0x01 => "SuperFX",
        0x02 => "OBC1",
        0x03 => "SA-1",
        0x04 => "S-DD1",
        0x05 => "S-RTC",
        0x0e => "Other (Super Game Boy/Satellaview)",
        0x0f => "Custom",
        else => "Unknown",
    } else "";
    const chipset_before = switch (chipset_type) {
        0x00 => "ROM only",
        0x01 => "ROM + RAM",
        0x02 => "ROM + RAM + battery",
        0x03 => "ROM + ",
        0x04 => "ROM + ",
        0x05 => "ROM + ",
        0x06 => "ROM + ",
        else => "Unknown",
    };
    const chipset_after = switch (chipset_type) {
        0x04 => " + RAM",
        0x05 => " + RAM + battery",
        0x06 => " + battery",
        else => "",
    };
    return std.fmt.bufPrint(&chipset_string_buf, "{s}{s}{s}", .{ chipset_before, coprocessor_string, chipset_after }) catch fatal("could not print to chipset string buffer");
}

fn displayInfoRow(key: []const u8, comptime T: FormatSpecifier, value: anytype) void {
    const BEFORE_SPECIFIER = "\x1b[90m{s:>" ++ KEY_WIDTH_FMT ++ "} \x1b[0;1m";
    const AFTER_SPECIFIER = "\x1b[0m\n";
    switch (T) {
        .String => disp.clearAndPrint(BEFORE_SPECIFIER ++ "{s}" ++ AFTER_SPECIFIER, .{ key, value }),
        .HexNumber => disp.clearAndPrint(BEFORE_SPECIFIER ++ "\x1b[0m0x\x1b[1m{x}" ++ AFTER_SPECIFIER, .{ key, value }),
        .VersionNumber => disp.clearAndPrint(BEFORE_SPECIFIER ++ "1.{d}" ++ AFTER_SPECIFIER, .{ key, value }),
        .RomSize => disp.clearAndPrint(BEFORE_SPECIFIER ++ "{d}\x1b[0m Mb" ++ AFTER_SPECIFIER, .{ key, value }),
        .RamSize => disp.clearAndPrint(BEFORE_SPECIFIER ++ "{d}\x1b[0m Kb" ++ AFTER_SPECIFIER, .{ key, value }),
    }
}
