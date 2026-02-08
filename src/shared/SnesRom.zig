const std = @import("std");

const SnesRom = @This();

bin: []const u8,
header: SnesRomHeader,
header_addr: u24,

pub const SnesRomHeader = extern struct {
    title: [21]u8,
    mode: u8,
    chipset: Chipset,
    size_rom: u8,
    size_ram: u8,
    region: Region,
    developer_id: u8,
    version: u8,
    checksum_complement: u16,
    checksum: u16,
    interrupt_vectors: [16]u16,

    const ParseError = error{
        InvalidHeader,
    };

    const possible_header_addrs: []const u24 = &[_]u24{
        0x40ffc0, // this must come first because Tales of Phantasia has a "true" header here and a "false" header (with bad checksums) at another location
        0x00ffc0,
        0x007fc0,
    };
    pub fn fromBin(bin: []const u8) ParseError!struct { SnesRomHeader, u24 } {
        var bin_reader = std.Io.Reader.fixed(bin);
        const has_copier_header = (bin.len & 0x3ff) == 512;

        for (possible_header_addrs) |addr| {
            const physical_addr = if (has_copier_header) addr + 512 else addr;
            if (physical_addr > bin.len) {
                continue;
            }
            bin_reader.seek = physical_addr;

            // check 1: `takeStruct` will implicitly check that `Chipset` and `Region` have valid values
            var header = bin_reader.takeStruct(SnesRomHeader, .little) catch continue;

            // check 2: title is all ASCII printable chars, mapping value is valid and checksums complement each other
            if (!header.isValid()) continue;

            return .{ header, physical_addr };
        }

        return ParseError.InvalidHeader;
    }
    fn isValid(possible_header: *SnesRomHeader) bool {
        // ascii name of ROM
        for (possible_header.title) |byte| {
            if (!std.ascii.isPrint(byte) and byte != 0)
                return false;
        }

        if (possible_header.mode & 0b11100000 != 0b00100000) return false;
        _ = std.enums.fromInt(MapMode, possible_header.mode & 0x0f) orelse return false;

        // if (possible_header.checksum ^ possible_header.checksum_complement != 0xffff) return false;

        return true;
    }
    pub inline fn getSpeedString(self: *SnesRomHeader) []const u8 {
        return if (self.mode & 0b0001_0000 != 0)
            "FastROM\x1b[0m (120ns)"
        else
            "SlowROM\x1b[0m (200ns)";
    }

    /// See https://problemkaputt.de/fullsnes.htm#snescartridgeromheader under "ROM Speed and Map Mode (FFD5h)"
    pub const MapMode = enum(u8) {
        LoROM,
        HiROM,
        LoROMSDD1,
        LoROMSA1,
        ExHiROM = 0x05,
        HiROMSPC7110 = 0x0a,

        pub fn getDisplayText(self: *const MapMode) []const u8 {
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

        pub fn getDisplayText(self: *const Chipset) []const u8 {
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

        pub fn getDisplayName(self: Region) []const u8 {
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
};

pub fn fromBin(bin: []const u8) SnesRomHeader.ParseError!SnesRom {
    return blk: {
        const header, const header_addr = try SnesRomHeader.fromBin(bin);
        break :blk .{
            .bin = bin,
            .header = header,
            .header_addr = header_addr,
        };
    };
}

pub inline fn hasCopierHeader(self: *SnesRom) bool {
    return (self.bin.len & 0x3ff) == 512;
}
pub inline fn hasExpandedHeader(self: *SnesRom) bool {
    return self.header.developer_id == 0x33;
}

pub fn getCalculatedChecksum(self: *SnesRom) u16 {
    var checksum: u16 = 0;
    for (self.bin) |byte| {
        checksum +%= byte;
    }

    var must_mirror = self.bin.len & (self.bin.len - 1) != 0;

    // special cases for certain games (Far East of Eden Zero and Momotaro Dentetsu Happy)
    if (self.header.chipset == .RomSpc7110RamBatteryRtc) {
        must_mirror = false;
    } else if (self.header.chipset == .RomCustomRamBattery and self.header.mode == 0x3a and self.getPhysicalRomSizeMegabits() == 24) {
        must_mirror = false;
        checksum *%= 2;
    }

    // ROM size must be a power of 2 for checksum calculation; a portion might have to be duplicated
    if (must_mirror) {
        // find the largest power of 2 less than or equal to self.bin.len
        var power_of_2: usize = 1024 * 1024 * 8; // 8MB; biggest game ever released was 6MB
        while (power_of_2 > self.bin.len) power_of_2 >>= 1;
        const duplicated_section = self.bin[power_of_2..];
        const num_times_to_duplicate = (power_of_2 / (self.bin.len - power_of_2)) - 1;
        for (0..num_times_to_duplicate) |_| {
            for (duplicated_section) |byte| {
                checksum +%= byte;
            }
        }
    }

    return checksum;
}
pub inline fn getInternalRomSizeKilobytes(self: *SnesRom) u32 {
    return @as(u32, 1) << @as(u5, @intCast(self.header.size_rom));
}
pub inline fn getInternalRamSizeKilobytes(self: *SnesRom) u32 {
    return @as(u32, 1) << @as(u5, @intCast(self.header.size_ram));
}
pub inline fn getInternalRomSizeMegabits(self: *SnesRom) u32 {
    return (self.getInternalRomSizeKilobytes() * 8) / 1024;
}
pub inline fn getInternalRamSizeKilobits(self: *SnesRom) u32 {
    return self.getInternalRamSizeKilobytes() * 8;
}
pub inline fn getPhysicalRomSizeMegabits(self: *SnesRom) usize {
    return (((self.bin.len * 8) / 1024) / 1024);
}
