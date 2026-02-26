// Copyright (c) 2026 Taylor Plewe
// See `main.zig` for full usage and warranty notice

const std = @import("std");

const shared = @import("shared");
const disp = shared.disp;

const Usage = @This();

title: []const u8,
description: []const u8,
usage_lines: []const []const u8,
sections: []const Section,

const Section = struct {
    title: []const u8,
    items: []const struct {
        shorthand: []const u8,
        title: []const u8,
        arg: []const u8,
        description: []const u8,
    },
};

const TAB = "     ";
const TAB_SHORTHAND = " ";
pub fn printAndExitWithCode(self: *const Usage, code: u8) noreturn {
    disp.printf("\x1b[1;33m{s}\x1b[0m - {s}\n\n", .{ self.title, self.description });
    disp.println("Usage:");
    for (self.usage_lines) |line| {
        disp.printf(TAB ++ "{s} {s}\n", .{ self.title, line });
    }
    for (self.sections) |section| {
        disp.printf("\n{s}:\n", .{section.title});
        const do_any_items_have_args = blk: {
            for (section.items) |item| {
                if (item.arg.len > 0) break :blk true;
            }
            break :blk false;
        };
        var shorthand_buf: [4]u8 = undefined;
        if (do_any_items_have_args) {
            for (section.items) |item| {
                disp.printf(TAB_SHORTHAND ++ "\x1b[0;33m{s:<4}{s:<14}\x1b[90m{s:<8}\x1b[0m{s}\n", .{
                    if (item.shorthand.len > 0) std.fmt.bufPrint(&shorthand_buf, "{s},", .{item.shorthand}) catch unreachable else "",
                    item.title,
                    item.arg,
                    item.description,
                });
            }
        } else {
            for (section.items) |item| {
                disp.printf(TAB_SHORTHAND ++ "\x1b[0;33m{s:<4}{s:<14}\x1b[0m{s}\n", .{
                    if (item.shorthand.len > 0) std.fmt.bufPrint(&shorthand_buf, "{s},", .{item.shorthand}) catch unreachable else "",
                    item.title,
                    item.description,
                });
            }
        }
    }
    std.process.exit(code);
}

pub inline fn printAndExit(self: *const Usage) noreturn {
    self.printAndExitWithCode(0);
}
pub inline fn printAndExitWithError(self: *const Usage) noreturn {
    self.printAndExitWithCode(1);
}
