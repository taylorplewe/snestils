// the UPS patch file format documentation I used can be found here: http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)

const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const Patcher = @import("./Patcher.zig");

const UpsPatcher = @This();

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_buf: []u8,
    original_rom_buf: []u8,
) Patcher {
    const patched_rom_buf = allocator.dupe(u8, original_rom_buf) catch fatal("could not copy original ROM buffer");
    return .{
        .vtable = &.{
            .validate = UpsPatcher.validate,
            .apply = UpsPatcher.apply,
        },
        // is allocator even needed on Patcher?
        .allocator = allocator,
        .patch_buf = patch_buf,
        .original_rom_buf = original_rom_buf,
        .patched_rom = .fromOwnedSlice(patched_rom_buf),
        .patch_idx = 0,
        .original_rom_idx = 0,
    };
}

fn validate(self: *Patcher) void {
    // "UPS1" string
    if (!std.mem.eql(u8, self.patch_buf[0..4], "UPS1")) {
        fatal("UPS patch files must begin with the word \"UPS1\"");
    }

    // original ROM checksum
    {
        const checksum_expected = std.mem.readVarInt(u32, self.patch_buf[(self.patch_buf.len - 12)..(self.patch_buf.len - 8)], .little);
        const checksum_actual = Patcher.calcCrc32(self.original_rom_buf);
        if (checksum_expected != checksum_actual) {
            fatalFmt("original ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32moriginal ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // patch file checksum
    {
        const checksum_expected = std.mem.readVarInt(u32, self.patch_buf[(self.patch_buf.len - 4)..], .little);
        const checksum_actual = Patcher.calcCrc32(self.patch_buf[0 .. self.patch_buf.len - 4]);
        if (checksum_expected != checksum_actual) {
            fatalFmt("patch file checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
        } else {
            disp.clearAndPrint("\x1b[32mpatch file checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
        }
    }

    // file sizes
    const original_rom_file_size = self.original_rom_buf.len;
    self.patch_idx = 4;
    const expected_size_original_rom = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
    if (expected_size_original_rom != original_rom_file_size) {
        fatalFmt("original ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_original_rom, original_rom_file_size });
    } else {
        disp.clearAndPrint("\x1b[32moriginal ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_original_rom});
    }
}

fn apply(self: *Patcher) void {
    const expected_size_patched_rom = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx); // size of patched ROM file

    while (self.patch_idx < self.patch_buf.len - 12) {
        const bytes_to_skip = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
        if (bytes_to_skip > 0) {
            if (self.original_rom_idx >= self.original_rom_buf.len) {
                self.patched_rom.appendNTimes(self.allocator.*, 0, bytes_to_skip) catch fatal("could not write 0s to patched ROM file");
            } else {
                self.original_rom_idx += bytes_to_skip;
            }
        }

        var patch_byte_to_xor = self.patch_buf[self.patch_idx];
        self.patch_idx += 1;
        while (patch_byte_to_xor != 0) {
            const byte_to_write = blk: {
                if (self.original_rom_idx >= self.original_rom_buf.len) {
                    break :blk patch_byte_to_xor;
                } else {
                    const original_byte = self.original_rom_buf[self.original_rom_idx];
                    break :blk patch_byte_to_xor ^ original_byte;
                }
            };
            if (self.original_rom_idx >= self.original_rom_buf.len) {
                self.patched_rom.append(self.allocator.*, byte_to_write) catch fatal("could not append byte to patched ROM buffer");
            } else {
                self.patched_rom.items[self.original_rom_idx] = byte_to_write;
            }
            self.original_rom_idx += 1;

            patch_byte_to_xor = self.patch_buf[self.patch_idx];
            self.patch_idx += 1;
        }

        if (self.patch_idx < self.patch_buf.len - 12) {
            if (self.original_rom_idx >= self.original_rom_buf.len) {
                self.patched_rom.append(self.allocator.*, 0) catch fatal("could not append 0 to patched ROM buffer");
            } else {
                self.original_rom_idx += 1;
            }
        }
    }

    // validate patched ROM size
    if (self.patched_rom.items.len != expected_size_patched_rom) {
        fatalFmt("final patched ROM file size does not match expected size.\n  expected size: {d}\n  actual size: {d}\n", .{ expected_size_patched_rom, self.patched_rom.items.len });
    } else {
        disp.clearAndPrint("\x1b[32mfinal patched ROM file size matches expected size (\x1b[0;1m{d}\x1b[0;32m)\x1b[0m\n", .{expected_size_patched_rom});
    }

    // validate patched ROM checksum
    const checksum_expected = std.mem.readVarInt(u32, self.patch_buf[(self.patch_buf.len - 8)..(self.patch_buf.len - 4)], .little);
    const checksum_actual = Patcher.calcCrc32(self.patched_rom.items);
    if (checksum_expected != checksum_actual) {
        fatalFmt("patched ROM checksum does not match calculated checksum\n  expected: 0x{x:0>8}\n  actual: 0x{x:0>8}\n", .{ checksum_expected, checksum_actual });
    } else {
        disp.clearAndPrint("\x1b[32mpatched ROM checksum matches calculated checksum (\x1b[0;1m0x{x:0>8}\x1b[0;32m)\x1b[0m\n", .{checksum_actual});
    }
}
