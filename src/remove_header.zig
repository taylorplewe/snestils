// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const Util = @import("Util.zig");
const Usage = @import("Usage.zig");

pub const ChecksumUtil = struct {
    pub const usage: Usage = .{
        .title = shared.PROGRAM_NAME ++ " fix-checksum",
        .description = "write a ROM's correct checksum & complement to its header",
        .usage_lines = &.{
            "<rom-file> [options]",
        },
        .sections = &.{
            .{
                .title = "Options",
                .items = &.{
                    .{ .shorthand = "-o", .title = "--out", .arg = "<file>", .description = "specify the file to write to" },
                    .{ .shorthand = "", .title = "--overwrite", .arg = "", .description = "overwrite the original ROM file when fixing the checksum" },
                    .{ .shorthand = "", .title = "--quiet", .arg = "", .description = "do not output anything to stdout" },
                    .{ .shorthand = "-h", .title = " --help", .arg = "", .description = "display this help text and quit" },
                },
            },
        },
    };
    pub fn init() Util {
        return .{
            .vtable = &.{
                .parseArgs = parseArgs,
                .do = fixChecksum,
            },
            .usage = usage,
        };
    }
};
