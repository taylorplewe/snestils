// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const SnesRom = shared.SnesRom;
const ansi = shared.ansi;

const Usage = @import("Usage.zig");
const Util = @import("Util.zig");

const KEY_WIDTH = 20;
const KEY_WIDTH_FMT = std.fmt.comptimePrint("{d}", .{KEY_WIDTH});

const FormatSpecifier = enum {
    String,
    HexNumber,
    VersionNumber,
    RomSize,
    RamSize,
};

const usage: Usage = .{
    .title = shared.PROGRAM_NAME ++ " info",
    .description = "print out information about a ROM",
    .usage_lines = &.{
        "<rom> [options]",
    },
    .sections = &.{
        .{
            .title = "Options",
            .items = &.{
                .{ .shorthand = "", .title = "--no-hashes", .arg = "", .description = "do not calculate & show hashes for ROM" },
                .{ .shorthand = "", .title = "--no-hexdump", .arg = "", .description = "do not show hexdump of ROM header" },
                .{ .shorthand = "", .title = "--upper-hex", .arg = "", .description = "display uppercase hex values in hexdump" },
                .{ .shorthand = "-h", .title = "--help", .arg = "", .description = "display this help text and quit" },
            },
        },
    },
};
pub const info_util: Util = .{
    .vtable = &.{
        .parseArgs = parseArgs,
        .do = displayInfo,
    },
    .usage = usage,
};

const Args = struct {
    rom_path: []const u8,
    no_hashes: bool,
    no_hexdump: bool,
    upper_hex: bool,
};
var args: Args = .{
    .rom_path = "",
    .no_hashes = false,
    .no_hexdump = false,
    .upper_hex = false,
};
fn parseArgs(_: *const std.mem.Allocator, args_raw: [][:0]u8) Util.ParseArgsError!void {
    if (args_raw.len < 1) {
        return Util.ParseArgsError.MissingRequiredArg;
    }
    for (args_raw) |arg| {
        if (std.mem.eql(u8, arg, "--no-hashes")) {
            args.no_hashes = true;
        } else if (std.mem.eql(u8, arg, "--no-hexdump")) {
            args.no_hexdump = true;
        } else if (std.mem.eql(u8, arg, "--upper-hex")) {
            args.upper_hex = true;
        } else {
            if (args.rom_path.len == 0) {
                args.rom_path = arg;
            } else {
                return Util.ParseArgsError.TooManyArgs;
            }
        }
    }
}

fn displayInfo(allocator: *const std.mem.Allocator) void {
    const rom_file = std.fs.cwd().openFile(args.rom_path, .{ .mode = .read_write }) catch fatalFmt("could not open file \x1b[1m{s}\x1b[0m", .{args.rom_path});

    var reader_buf: [std.math.maxInt(u16)]u8 = undefined;
    var rom_reader_core = rom_file.reader(&reader_buf);
    var rom_reader = &rom_reader_core.interface;

    const rom_bin = rom_reader.allocRemaining(allocator.*, .limited(std.math.maxInt(u32))) catch fatal("could not allocate buffer for ROM file");
    var rom = SnesRom.fromBin(rom_bin) catch fatal("could not create SnesRom struct from binary. Is it a valid SNES ROM file?");

    disp.println("");

    if (!args.no_hexdump) displayHexdump(rom.header_addr - 16, rom_bin[rom.header_addr - 16 .. rom.header_addr + 32]);

    const map_mode: SnesRom.SnesRomHeader.MapMode = @enumFromInt(rom.header.mode & 0x0f);
    displayInfoRow("Title", .String, &rom.header.title);
    displayInfoRow("Developer", .String, rom.getDeveloperName() orelse "Unknown (demo or beta ROM?)");
    displayInfoRow("Version", .VersionNumber, rom.header.version);
    displayInfoRow("Region", .String, rom.header.region.getDisplayName());
    if (rom.extended_header != null) {
        displayInfoRow("Game code", .String, rom.extended_header.?.game_code);
    }
    displayInfoRow("ROM size", .RomSize, rom.getPhysicalRomSizeMegabits());
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ "Internal: " ++ ansi.BRIGHT ++ "{d}" ++ ansi.WHITE ++ " Mb ({d} MB)\n", .{ rom.getInternalRomSizeMegabits(), rom.getInternalRomSizeMegabits() / 8 });
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
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ ansi.WHITE ++ "Calculated: " ++ ansi.WHITE ++ "0x" ++ ansi.BRIGHT ++ "{x:0>4}\x1b[0m\n", .{checksum_calculated});
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ ansi.WHITE ++ "Internal:   " ++ ansi.WHITE ++ "0x" ++ ansi.BRIGHT ++ "{x:0>4}\x1b[0m\n", .{rom.header.checksum});
    displayInfoRow("Checksum complement", .String, if (checksum_compl_calculated == rom.header.checksum_complement) OK else BAD);
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ ansi.WHITE ++ "Calculated: " ++ ansi.WHITE ++ "0x" ++ ansi.BRIGHT ++ "{x:0>4}\x1b[0m\n", .{checksum_compl_calculated});
    disp.printf((" " ** (KEY_WIDTH + 1)) ++ ansi.WHITE ++ "Internal:   " ++ ansi.WHITE ++ "0x" ++ ansi.BRIGHT ++ "{x:0>4}\x1b[0m\n", .{rom.header.checksum_complement});
    displayInfoRow("Has copier header", .String, if (rom.hasCopierHeader()) "Yes" else "No");

    if (args.no_hashes) {
        disp.println("");
        return;
    }

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
    disp.printf(ansi.WHITE ++ "{s:>" ++ KEY_WIDTH_FMT ++ "}\n\n", .{"Hashes"});
    displayInfoRow("CRC32", .HexNumber, crc32);
    displayInfoRow("MD5", .HexNumber, md5);
    displayInfoRow("SHA1", .HexNumber, sha1);
    displayInfoRow("SHA256", .HexNumber, sha256);

    disp.println("");
}

fn displayInfoRow(key: []const u8, comptime T: FormatSpecifier, value: anytype) void {
    const BEFORE_SPECIFIER = ansi.DIM ++ "{s:>" ++ KEY_WIDTH_FMT ++ "} " ++ ansi.BRIGHT;
    const AFTER_SPECIFIER = "\x1b[0m\n";
    switch (T) {
        .String => disp.printf(BEFORE_SPECIFIER ++ "{s}" ++ AFTER_SPECIFIER, .{ key, value }),
        .HexNumber => disp.printf(BEFORE_SPECIFIER ++ ansi.WHITE ++ "0x" ++ ansi.BRIGHT ++ "{x}" ++ AFTER_SPECIFIER, .{ key, value }),
        .VersionNumber => disp.printf(BEFORE_SPECIFIER ++ "1.{d}" ++ AFTER_SPECIFIER, .{ key, value }),
        .RomSize => disp.printf(BEFORE_SPECIFIER ++ "{d}" ++ ansi.WHITE ++ " Mb ({d} MB)" ++ AFTER_SPECIFIER, .{ key, value, value / 8 }),
        .RamSize => disp.printf(BEFORE_SPECIFIER ++ "{d}" ++ ansi.WHITE ++ " Kb ({d} KB)" ++ AFTER_SPECIFIER, .{ key, value, value / 8 }),
    }
}

fn displayHexdump(addr: u24, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) : (i += 16) {
        // disp.printf(" \x1b[48;2;32;32;32m\x1b[38;2;190;190;190m", .{}); // fancy bg colors
        disp.printf(" " ++ ansi.DIM, .{});
        if (args.upper_hex) {
            disp.printf("{X:0>8} ", .{addr + i});
        } else {
            disp.printf("{x:0>8} ", .{addr + i});
        }
        // disp.printf("\x1b[38;2;255;255;255m", .{});
        disp.printf(ansi.WHITE, .{});

        // disp.printf("\x1b[48;2;16;16;16m\x1b[38;2;255;255;255m ", .{});
        for (0..4) |group| {
            for (0..4) |j| {
                if (args.upper_hex) {
                    disp.printf("{X:0>2} ", .{data[i + (group * 4 + j)]});
                } else {
                    disp.printf("{x:0>2} ", .{data[i + (group * 4 + j)]});
                }
            }
            if (group < 3) {
                disp.printf(" ", .{});
            }
        }
        // disp.printf("\x1b[48;2;32;32;32m\x1b[38;2;190;190;190m ", .{});
        disp.printf(ansi.DIM, .{});
        for (i..i + 16) |c| {
            if (std.ascii.isPrint(data[c])) {
                disp.printf("{c}", .{data[c]});
            } else {
                disp.printf(" ", .{});
            }
        }
        disp.println(" \x1b[0m");
    }
    disp.println("");
}
