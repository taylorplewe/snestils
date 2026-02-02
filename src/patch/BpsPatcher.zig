// the BPS patch file format documentation I used can be found here: http://justsolve.archiveteam.org/wiki/UPS_(binary_patch_format)

const std = @import("std");
const disp = @import("../disp.zig");
const fatal = disp.fatal;
const fatalFmt = disp.fatalFmt;
const Patcher = @import("./Patcher.zig");

const BpsPatcher = @This();
const ActionKind = enum {
    SourceRead,
    TargetRead,
    SourceCopy,
    TargetCopy,
};
const Action = struct {
    kind: ActionKind,
    length: usize,
};

pub fn init(
    allocator: *const std.mem.Allocator,
    patch_buf: []u8,
    original_rom_buf: []u8,
) Patcher {
    return .{
        .vtable = &.{
            .validate = BpsPatcher.validate,
            .apply = BpsPatcher.apply,
        },
        .allocator = allocator,
        .patch_buf = patch_buf,
        .original_rom_buf = original_rom_buf,
        .patched_rom = .empty,
        .patch_idx = 0,
        .original_rom_idx = 0,
    };
}

// TODO: might just reference UpsPatcher.validate instead of copying it here
fn validate(self: *Patcher) void {
    // "UPS1" string
    if (!std.mem.eql(u8, self.patch_buf[0..4], "BPS1")) {
        fatal("BPS patch files must begin with the word \"BPS1\"");
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

    // skip over optional metadata
    const metadata_len = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
    self.patch_idx += metadata_len;

    // main data portion
    var source_relative_offset: u64 = 0;
    var target_relative_offset: u64 = 0;
    var action_num: usize = 0;
    while (self.patch_idx < self.patch_buf.len - 12) {
        const action_kind_and_length = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
        const action: Action = .{
            .kind = @enumFromInt(action_kind_and_length & 0b11),
            .length = (action_kind_and_length >> 2) + 1,
        };

        switch (action.kind) {
            .SourceRead => {
                self.original_rom_idx = self.patched_rom.items.len;
                self.patched_rom.appendSlice(self.allocator.*, self.original_rom_buf[self.original_rom_idx..(self.original_rom_idx + action.length)]) catch fatal("could not perform SourceRead");
                self.original_rom_idx += action.length;
            },
            .TargetRead => {
                self.patched_rom.appendSlice(self.allocator.*, self.patch_buf[self.patch_idx..(self.patch_idx + action.length)]) catch fatal("could not perform TargetRead");
                self.patch_idx += action.length;
            },
            .SourceCopy => {
                const offset_data = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
                const relative_offset = offset_data >> 1;

                if (offset_data & 1 == 1) {
                    if (relative_offset > source_relative_offset) {
                        fatalFmt("SourceCopy negative relative offset is larger than the current source relative offset\n relative offset: {}\n source relative offset: {}", .{ relative_offset, source_relative_offset });
                    }
                    source_relative_offset -= relative_offset;
                } else {
                    if (source_relative_offset + relative_offset > self.original_rom_buf.len) {
                        fatalFmt("SourceCopy positive relative offset is larger than the original ROM size\n relative offset: {}\n original ROM file size: {}", .{ relative_offset, self.original_rom_buf.len });
                    }
                    source_relative_offset += relative_offset;
                }

                self.original_rom_idx = source_relative_offset;
                self.patched_rom.appendSlice(self.allocator.*, self.original_rom_buf[self.original_rom_idx..(self.original_rom_idx + action.length)]) catch fatal("could not perform SourceCopy");
                source_relative_offset += action.length;
            },
            .TargetCopy => {
                const offset_data = Patcher.takeVariableWidthInteger(self.patch_buf, &self.patch_idx);
                const relative_offset = offset_data >> 1;
                if (offset_data & 1 == 1) {
                    if (relative_offset > target_relative_offset) {
                        fatalFmt("TargetCopy negative relative offset is larger than the current target relative offset\n relative offset: {}\n target relative offset: {}", .{ relative_offset, target_relative_offset });
                    }
                    target_relative_offset -= relative_offset;
                } else {
                    if (target_relative_offset + relative_offset > self.patched_rom.items.len) {
                        fatalFmt("TargetCopy positive relative offset is larger than the current patched ROM file size\n relative offset: {}\n patched ROM file size: {}", .{ relative_offset, self.patched_rom.items.len });
                    }
                    target_relative_offset += relative_offset;
                }

                for (0..action.length) |_| {
                    self.patched_rom.append(self.allocator.*, self.patched_rom.items[target_relative_offset]) catch fatal("could not copy byte from patched ROM to itself");
                    target_relative_offset += 1;
                }
            },
        }
        action_num += 1; // NOTE: debug
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
