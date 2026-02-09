// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

// the IPS patch file format documentation I used can be found here: https://zerosoft.zophar.net/ips.php

const std = @import("std");
const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const Patcher = @import("./Patcher.zig");

const IpsPatcher = @This();
const IpsPatchRecord = packed struct {
    offset: u24,
    length: u16,
};

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_buf: []u8,
    original_rom_buf: []u8,
) Patcher {
    const patched_rom_buf = allocator.dupe(u8, original_rom_buf) catch fatal("could not copy original ROM buffer");
    return .{
        .vtable = &.{
            .validate = IpsPatcher.validate,
            .apply = IpsPatcher.apply,
        },
        .allocator = allocator,
        .patch_buf = patch_buf,
        .original_rom_buf = original_rom_buf,
        .patched_rom = .fromOwnedSlice(patched_rom_buf),
        .patch_idx = 0,
        .original_rom_idx = 0,
    };
}

fn validate(self: *Patcher) void {
    if (!std.mem.eql(u8, self.patch_buf[0..5], "PATCH")) {
        fatal("IPS patch files must begin with the word \"PATCH\"");
    }
    if (!std.mem.eql(u8, self.patch_buf[self.patch_buf.len - 3 ..], "EOF")) {
        fatal("IPS patch files must end with the word \"EOF\"");
    }
}

fn apply(self: *Patcher) void {
    self.patch_idx = 5;
    while (self.patch_idx < self.patch_buf.len - 3) {
        const record: IpsPatchRecord = .{
            .offset = std.mem.readVarInt(u24, self.patch_buf[self.patch_idx .. self.patch_idx + 3], .big),
            .length = std.mem.readVarInt(u16, self.patch_buf[self.patch_idx + 3 .. self.patch_idx + 5], .big),
        };
        self.patch_idx += 5;

        if (record.length > 0) {
            const replace_len =
                if (self.patched_rom.items.len < record.offset + record.length)
                    self.patched_rom.items.len -| record.offset
                else
                    record.length;
            if (replace_len == 0) {
                self.patched_rom.appendNTimes(self.allocator.*, 0, record.offset -| self.patched_rom.items.len) catch fatal("could not append 0s to patched ROM file");
                self.patched_rom.appendSlice(self.allocator.*, self.patch_buf[self.patch_idx..(self.patch_idx + record.length)]) catch fatal("could not append bytes to patched ROM file");
            } else {
                self.patched_rom.replaceRange(self.allocator.*, record.offset, replace_len, self.patch_buf[self.patch_idx..(self.patch_idx + record.length)]) catch fatal("could not write bytes to patched ROM file");
            }
            self.patch_idx += record.length;
        } else {
            const rle_len = std.mem.readVarInt(u16, self.patch_buf[self.patch_idx..(self.patch_idx + 2)], .big);
            self.patch_idx += @sizeOf(u16);

            const rle_byte = self.patch_buf[self.patch_idx];
            self.patch_idx += 1;

            Patcher.replaceNTimes(self.allocator, &self.patched_rom, record.offset, rle_len, rle_byte) catch fatal("could not place RLE bytes into patched ROM file");
        }
    }
}
