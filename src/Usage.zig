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
        title: []const u8,
        description: []const u8,
    },
};

const TAB = "    ";
pub fn printAndExitWithCode(self: *const Usage, code: u8) noreturn {
    disp.printf("\x1b[1;33m{s}\x1b[0m - {s}\n\n", .{ self.title, self.description });
    disp.println("Usage:");
    for (self.usage_lines) |line| {
        disp.printf(TAB ++ "{s} {s}\n", .{ self.title, line });
    }
    for (self.sections) |section| {
        disp.printf("\n{s}:\n", .{section.title});
        for (section.items) |item| {
            disp.printf(TAB ++ "\x1b[33m{s}\x1b[0m - {s}\n", .{ item.title, item.description });
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
