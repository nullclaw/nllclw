const cli = @import("./channels/cli.zig");
const std = @import("std");

pub fn main(init: std.process.Init.Minimal) !void {
    cli.run(init);
}
