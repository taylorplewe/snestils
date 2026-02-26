const builtin = @import("builtin");

pub const SnesRom = @import("SnesRom.zig");
pub const disp = @import("disp.zig");
pub const ansi = @import("ansi.zig");

const EXE = if (builtin.os.tag == .windows) ".exe" else "";
pub const PROGRAM_NAME = "snestils" ++ EXE;
