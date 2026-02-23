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
// const developer_ids: [_][]const u8 = @import("developer_ids.zon");

const KEY_WIDTH = 20;
const KEY_WIDTH_FMT = std.fmt.comptimePrint("{d}", .{KEY_WIDTH});

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
            .vtable = &.{
                .parseArgs = parseArgs,
                .do = displayInfo,
            },
            .usage = usage,
        };
    }
};

const Args = struct {
    rom_path: []const u8,
};
var args: Args = undefined;
fn parseArgs(args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len != 1) {
        disp.println("ROM path required");
        return Util.ParseArgsError{};
    }
    args = .{
        .rom_path = args_raw[0],
    };
}

fn displayInfo(allocator: *const std.mem.Allocator) void {
    const rom_path = args[0];
    const rom_file = std.fs.cwd().openFile(rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{rom_path});

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    const rom_bin = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not allocate buffer for ROM file");
    var rom = SnesRom.fromBin(rom_bin) catch fatal("could not create SnesRom struct from binary");

    disp.println("");

    const map_mode: SnesRom.SnesRomHeader.MapMode = @enumFromInt(rom.header.mode & 0x0f);
    displayInfoRow("Title", .String, &rom.header.title);
    displayInfoRow("Developer", .String, rom.getDeveloperName() orelse "Unkown (demo or beta ROM?)");
    displayInfoRow("Version", .VersionNumber, rom.header.version);
    displayInfoRow("Region", .String, rom.header.region.getDisplayName());
    if (rom.extended_header != null) {
        displayInfoRow("Game code", .String, rom.extended_header.?.game_code);
    }
    displayInfoRow("ROM size", .RomSize, rom.getPhysicalRomSizeMegabits());
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Internal: \x1b[1m{d}\x1b[0m Mb ({d} MB)\n", .{ rom.getInternalRomSizeMegabits(), rom.getInternalRomSizeMegabits() / 8 });
    displayInfoRow("RAM size", .RamSize, rom.getInternalRamSizeKilobits());
    displayInfoRow("Mapping", .String, map_mode.getDisplayText());
    displayInfoRow("Speed", .String, rom.header.getSpeedString());
    displayInfoRow("Chipset", .String, rom.header.chipset.getDisplayText(if (rom.extended_header != null) rom.extended_header.?.chipset_subtype else 0));

    // compare internal checksum to calculated checksum
    const checksum_calculated = rom.getCalculatedChecksum();
    const checksum_compl_calculated = ~checksum_calculated;
    const OK = "\x1b[32;1mOK\x1b[0m";
    const BAD = "\x1b[31;1mBAD\x1b[0m";
    displayInfoRow("Checksum", .String, if (checksum_calculated == rom.header.checksum) OK else BAD);
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{checksum_calculated});
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{rom.header.checksum});
    displayInfoRow("Checksum complement", .String, if (checksum_compl_calculated == rom.header.checksum_complement) OK else BAD);
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Calculated: \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{checksum_compl_calculated});
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Internal:   \x1b[0m0x\x1b[1m{x:0>4}\x1b[0m\n", .{rom.header.checksum_complement});
    displayInfoRow("Has copier header", .String, if (rom.hasCopierHeader()) "Yes" else "No");

    disp.printf("\n\n", .{});

    disp.printLoading("calculating hashes");

    // get various hashes of ROM data
    var md5: [16]u8 = undefined;
    var sha1: [20]u8 = undefined;
    var sha256: [32]u8 = undefined;
    const crc32 = std.hash.Crc32.hash(rom_bin);
    std.crypto.hash.Md5.hash(rom_bin, &md5, .{});
    std.crypto.hash.Sha1.hash(rom_bin, &sha1, .{});
    std.crypto.hash.sha2.Sha256.hash(rom_bin, &sha256, .{});
    disp.clearLine();
    disp.printf("{s:>" ++ KEY_WIDTH_FMT ++ "}\n\n", .{"Hashes"});
    displayInfoRow("CRC32", .HexNumber, crc32);
    displayInfoRow("MD5", .HexNumber, md5);
    displayInfoRow("SHA1", .HexNumber, sha1);
    displayInfoRow("SHA256", .HexNumber, sha256);

    disp.println("");

    // fatal("SNES ROM header was not found at any of the expected addresses");
}

fn displayInfoRow(key: []const u8, comptime T: FormatSpecifier, value: anytype) void {
    const BEFORE_SPECIFIER = "\x1b[90m{s:>" ++ KEY_WIDTH_FMT ++ "} \x1b[0;1m";
    const AFTER_SPECIFIER = "\x1b[0m\n";
    switch (T) {
        .String => disp.printf(BEFORE_SPECIFIER ++ "{s}" ++ AFTER_SPECIFIER, .{ key, value }),
        .HexNumber => disp.printf(BEFORE_SPECIFIER ++ "\x1b[0m0x\x1b[1m{x}" ++ AFTER_SPECIFIER, .{ key, value }),
        .VersionNumber => disp.printf(BEFORE_SPECIFIER ++ "1.{d}" ++ AFTER_SPECIFIER, .{ key, value }),
        .RomSize => disp.printf(BEFORE_SPECIFIER ++ "{d}\x1b[0m Mb ({d} MB)" ++ AFTER_SPECIFIER, .{ key, value, value / 8 }),
        .RamSize => disp.printf(BEFORE_SPECIFIER ++ "{d}\x1b[0m Kb ({d} KB)" ++ AFTER_SPECIFIER, .{ key, value, value / 8 }),
    }
}
