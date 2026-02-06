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
/// See https://problemkaputt.de/fullsnes.htm#snescartridgeromheader under "ROM Speed and Map Mode (FFD5h)"
const MapMode = enum(u8) {
    LoROM,
    HiROM,
    LoROMSDD1,
    LoROMSA1,
    ExHiROM = 0x05,
    HiROMSPC7110 = 0x0a,

    fn getDisplayText(self: *const MapMode) []const u8 {
        return switch (self.*) {
            .LoROM => "LoROM",
            .HiROM => "HiROM",
            .LoROMSDD1 => "LoROM",
            .LoROMSA1 => "LoROM",
            .ExHiROM => "ExHiROM",
            .HiROMSPC7110 => "HiROM",
        };
    }
};
/// See https://problemkaputt.de/fullsnes.htm#snescartridgeromheader under "Chipset (ROM/RAM information on cart) (FFD6h) (and some subclassed via FFBFh)"
const Chipset = enum(u8) {
    Rom,
    RomRam,
    RomRamBattery,
    RomDsp,
    RomDspRam,
    RomDspRamBattery,
    RomMarioChip1ExpansionRam = 0x13,
    RomGsuRam = 0x14,
    RomGsuRamBattery = 0x15,
    RomGsu1RamBatteryFastMode = 0x1a,
    RomObc1RamBattery = 0x25,
    RomSa1RamBatteryF1GrandPrix = 0x32,
    RomSa1Ram = 0x34,
    RomSa1RamBattery = 0x35,
    RomSdd1 = 0x43,
    RomSdd1RamBattery = 0x45,
    RomSrtcRamBattery = 0x55,
    RomSuperGameboy = 0xe3,
    RomSatellaviewBios = 0xe5,
    RomCustom = 0xf3,
    RomCustomRamBattery = 0xf5,
    RomCustomBattery = 0xf6,
    RomSpc7110RamBatteryRtc = 0xf9,

    fn getDisplayText(self: *const Chipset) []const u8 {
        return switch (self.*) {
            .Rom => "ROM",
            .RomRam => "ROM + RAM",
            .RomRamBattery => "ROM + RAM + Battery",
            .RomDsp => "ROM + DSP + RAM + Battery",
            .RomDspRam => "ROM + DSP + RAM",
            .RomDspRamBattery => "ROM + DSP + RAM + Battery",
            .RomMarioChip1ExpansionRam => "ROM + Mario Chip 1/Expansion RAM",
            .RomGsuRam => "ROM + GSU (SuperFX) + RAM",
            .RomGsuRamBattery => "ROM + GSU (SuperFX) + RAM + Battery",
            .RomGsu1RamBatteryFastMode => "ROM + GSU1 (SuperFX) + RAM + Battery + Fast Mode",
            .RomObc1RamBattery => "ROM + OBC1 + RAM + Battery",
            .RomSa1RamBatteryF1GrandPrix => "ROM + SA-1 + RAM + Battery + F1 Grand Prix",
            .RomSa1Ram => "ROM + SA-1 + RAM",
            .RomSa1RamBattery => "ROM + SA-1 + RAM + Battery",
            .RomSdd1 => "ROM + S-DD1",
            .RomSdd1RamBattery => "ROM + S-DD1 + RAM + Battery",
            .RomSrtcRamBattery => "ROM + S-RTC + RAM + Battery",
            .RomSuperGameboy => "ROM + Super Game Boy",
            .RomSatellaviewBios => "ROM + Satellite View BIOS",
            .RomCustom => "ROM + Custom",
            .RomCustomRamBattery => "ROM + Custom + RAM + Battery",
            .RomCustomBattery => "ROM + Custom + Battery",
            .RomSpc7110RamBatteryRtc => "ROM + SPC-7110 + RAM + Battery + RTC",
        };
    }
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

const FormatSpecifier = enum {
    String,
    HexNumber,
    VersionNumber,
    RomSize,
    RamSize,
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
    0x40ffc0, // this must come first because Tales of Phantasia has a "true" header here and a "false" header (with bad checksums) at another location
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
            const map_mode: MapMode = @enumFromInt(header.mode & 0x0f);
            const chipset: Chipset = @enumFromInt(header.chipset);
            displayInfoRow("Title", .String, &header.title);
            displayInfoRow("Version", .VersionNumber, header.version);
            displayInfoRow("Region", .String, header.region.getDisplayName());
            displayInfoRow("ROM size", .RomSize, physical_rom_size_megabits);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal: \x1b[1m{d}\x1b[0m Mb\n", .{internal_rom_size_megabits});
            displayInfoRow("RAM size", .RamSize, internal_ram_size_kilobits);
            displayInfoRow("Mapping", .String, map_mode.getDisplayText());
            displayInfoRow("Speed", .String, getSpeedString(header.mode));
            displayInfoRow("Chipset", .String, chipset.getDisplayText());

            // compare internal checksum to calculated checksum
            const checksum_calculated = checksum.calcChecksum(rom);
            const checksum_compl_calculated = checksum_calculated ^ 0xffff;
            const OK = "\x1b[32;1mOK\x1b[0m";
            const BAD = "\x1b[31;1mBAD\x1b[0m";
            displayInfoRow("Checksum", .String, if (checksum_calculated == header.checksum) OK else BAD);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{checksum_calculated});
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{header.checksum});
            displayInfoRow("Checksum complement", .String, if (checksum_compl_calculated == header.checksum_complement) OK else BAD);
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{checksum_compl_calculated});
            disp.clearAndPrint((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{header.checksum_complement});

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

fn checkForHeader(possible_header: *SnesRomHeader) bool {
    // ascii name of ROM
    for (possible_header.title) |byte| {
        if (!std.ascii.isPrint(byte) and byte != 0)
            return false;
    }

    if (possible_header.mode & 0b11100000 != 0b00100000) return false;
    _ = std.enums.fromInt(MapMode, possible_header.mode & 0x0f) orelse return false;
    _ = std.enums.fromInt(Chipset, possible_header.chipset) orelse return false;

    // existing checksum & complement
    if (possible_header.checksum ^ possible_header.checksum_complement != 0xffff) return false;

    return true;
}

inline fn getSpeedString(mode: u8) []const u8 {
    return if (mode & 0b0001_0000 != 0)
        "FastROM\x1b[0m (120ns)"
    else
        "SlowROM\x1b[0m (200ns)";
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
