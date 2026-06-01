const std = @import("std");
const context = @import("./context.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const path = "HEARTBEAT.md";
pub const max_file_bytes = 16 * 1024;

pub fn loadPrompt(allocator: Allocator, io: Io) !?[]u8 {
    const contents = (try context.readLocalInstructionFileAlloc(
        allocator,
        io,
        Io.Dir.cwd(),
        path,
        max_file_bytes,
    )) orelse return null;
    defer allocator.free(contents);
    return buildPrompt(allocator, contents);
}

pub fn buildPrompt(allocator: Allocator, contents: []const u8) !?[]u8 {
    try context.validateContents(contents);

    var tasks: std.ArrayList([]const u8) = .empty;
    defer tasks.deinit(allocator);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (isActionable(line)) try tasks.append(allocator, line);
    }
    if (tasks.items.len == 0) return null;

    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll(
        "Heartbeat check. Review these pending local HEARTBEAT.md tasks and act on them if possible. Report what you did.\n\n",
    );
    for (tasks.items) |task| {
        try out.writer.writeAll(task);
        try out.writer.writeByte('\n');
    }
    return try out.toOwnedSlice();
}

fn isActionable(line: []const u8) bool {
    if (line.len == 0) return false;
    if (std.mem.startsWith(u8, line, "#")) return false;
    if (std.mem.startsWith(u8, line, "- [x]") or std.mem.startsWith(u8, line, "- [X]")) return false;
    if (std.mem.startsWith(u8, line, "- [ ]")) return true;
    return std.mem.startsWith(u8, line, "TODO:");
}

test "heartbeat builds prompt from unchecked tasks only" {
    const prompt = (try buildPrompt(std.testing.allocator,
        \\# HEARTBEAT
        \\plain policy text
        \\- [x] done
        \\- [ ] check status
        \\TODO: report
        \\
    )).?;
    defer std.testing.allocator.free(prompt);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "check status") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "plain policy") == null);
}

test "heartbeat returns null without tasks" {
    try std.testing.expect((try buildPrompt(std.testing.allocator, "# empty\n- [x] done\n")) == null);
}

test "heartbeat rejects invalid utf-8 task files" {
    try std.testing.expectError(
        error.InvalidContextFileUtf8,
        buildPrompt(std.testing.allocator, "- [ ] bad\xff\n"),
    );
    try std.testing.expectError(
        error.InvalidContextFileUtf8,
        buildPrompt(std.testing.allocator, "- [ ] bad\x1btask\n"),
    );
}
