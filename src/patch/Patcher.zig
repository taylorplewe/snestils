// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

//! An interface which any patch format must implement

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;
const fatal = disp.fatal;

const Patcher = @This();

vtable: *const VTable,
allocator: *const std.mem.Allocator,

patch_buf: []u8,
original_rom_buf: []u8,
patched_rom: std.ArrayList(u8),

patch_idx: usize,
original_rom_idx: usize,

pub const VTable = struct {
    /// Validate that the file meets the format criteria
    validate: *const fn (self: *Patcher) void,

    /// Apply the patch to the ROM provided at initialization
    apply: *const fn (self: *Patcher) void,
};

pub fn validate(self: *Patcher) void {
    self.vtable.validate(self);
}

pub fn apply(self: *Patcher) void {
    self.vtable.apply(self);
}

pub fn replaceNTimes(
    allocator: *const std.mem.Allocator,
    list: *std.ArrayList(u8),
    start: usize,
    len: usize,
    byte: u8,
) std.mem.Allocator.Error!void {
    const replace_len =
        if (start + len > list.items.len)
            list.items.len -| start
        else
            len;
    if (replace_len > 0) {
        const range = list.items[start..(start + replace_len)];
        @memset(range, byte);
    }
    const append_len = len - replace_len;
    if (append_len > 0) {
        try list.appendNTimes(allocator.*, byte, append_len);
    }
}

pub fn takeVariableWidthInteger(data: []u8, idx: *usize) usize {
    var result: usize = 0;
    var shift: u6 = 0;
    while (true) {
        const byte = data[idx.*];
        idx.* += 1;
        if ((byte & 0x80) != 0) {
            result += @as(usize, byte & 0x7f) << shift;
            break;
        }
        result += @as(usize, byte | 0x80) << shift;
        shift += 7;
    }
    return result;
}

/// Calculates a 32-bit CRC checksum from a slice of bytes.
/// I am aware of std.hash.Crc32--see `src/info.zig` for an example of it in use
///
/// I didn't hear about it until after I had already written my own implemnetation here. I'm keeping this around because
/// - It's a much simpler implementation than that in the standard library
/// - It taught me about unit testing in Zig and generating a static table at comptime, both of which I'm not ready to just throw away
pub fn calcCrc32(data: []const u8) u32 {
    var crc32: u32 = 0xffffffff;
    for (data) |byte| {
        crc32 ^= byte;
        crc32 = (crc32 >> 8) ^ crc32_table[crc32 & 0xff];
    }
    return ~crc32;
}

test calcCrc32 {
    try std.testing.expectEqual(0x8587D865, calcCrc32("abcde"));
    try std.testing.expectEqual(0x0f5cc4b4, calcCrc32(&[_]u8{ 0xf3, 0x85, 0x9a, 0x84, 0xfc, 0x24, 0xde, 0x22 }));
}

pub const crc32_table = blk: {
    var table: [256]u32 = undefined;
    table[0] = 0;

    var crc32: u32 = 1;
    var i: usize = 128;
    while (i != 0) : (i >>= 1) {
        crc32 = (crc32 >> 1) ^ (if ((crc32 & 1) != 0) 0xedb88320 else 0);
        var j: usize = 0;
        while (j < 256) : (j += 2 * i) {
            table[i + j] = crc32 ^ table[j];
        }
    }

    break :blk table;
};

test crc32_table {
    try std.testing.expectEqual(crc32_table[0], 0);
    try std.testing.expectEqual(crc32_table[1], 0x77073096);
    try std.testing.expectEqual(crc32_table[2], 0xee0e612c);
    try std.testing.expectEqual(crc32_table[255], 0x02d02ef8d);
}
