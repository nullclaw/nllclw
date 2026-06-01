const std = @import("std");
const builtin = @import("builtin");

/// Zig 0.16 opens Windows no-follow files as asynchronous handles, but reports
/// them as blocking. Mark them correctly so std.Io waits for STATUS_PENDING.
pub fn fixWindowsNoFollowFile(file: *std.Io.File) void {
    if (builtin.os.tag == .windows) file.flags.nonblocking = true;
}
