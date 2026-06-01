const std = @import("std");
const io_file = @import("./adapters/io_file.zig");
const path_policy = @import("./path_policy.zig");
const text_policy = @import("./text_policy.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const default_dir = "skills";
pub const max_skill_file_bytes = 8 * 1024;
pub const max_skill_count: usize = 32;
pub const max_summary_title_bytes: usize = 96;
pub const max_summary_description_bytes: usize = 256;

pub const SummaryFile = struct {
    path: []const u8,
    contents: []const u8,
};

pub fn appendDirectorySummary(
    allocator: Allocator,
    io: Io,
    writer: *Io.Writer,
    dir_path: []const u8,
) !bool {
    var dir = Io.Dir.cwd().openDir(io, dir_path, .{
        .iterate = true,
        .access_sub_paths = false,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound,
        error.NotDir,
        => return false,
        else => return err,
    };
    defer dir.close(io);

    var iter = dir.iterate();
    var names: [max_skill_count][]u8 = undefined;
    var name_count: usize = 0;
    defer {
        for (names[0..name_count]) |name| allocator.free(name);
    }

    while (iter.next(io) catch |err| return err) |entry| {
        switch (entry.kind) {
            .file, .unknown => {},
            else => continue,
        }
        if (!isSkillFileName(entry.name)) continue;
        try insertSkillName(allocator, &names, &name_count, entry.name);
    }

    var found = false;
    for (names[0..name_count]) |name| {
        const contents = readSkillFileAlloc(allocator, io, dir, name) catch |err| switch (err) {
            error.FileNotFound,
            error.IsDir,
            error.SymLinkLoop,
            => continue,
            error.StreamTooLong => return error.SkillFileTooLarge,
            else => return err,
        };
        defer allocator.free(contents);
        if (!isValidSkillContents(contents)) return error.InvalidSkillFileUtf8;

        if (!found) {
            try writer.print("\n\n## Skills ({s}/)\n", .{dir_path});
            try writer.writeAll(
                "Skills are local markdown instruction files. When a task matches a skill, read the full file with read_file before acting.\n",
            );
            found = true;
        }

        const skill_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, name });
        defer allocator.free(skill_path);
        try appendOneSummary(writer, .{ .path = skill_path, .contents = contents });
    }

    return found;
}

fn readSkillFileAlloc(allocator: Allocator, io: Io, dir: Io.Dir, name: []const u8) ![]u8 {
    var file = try dir.openFile(io, name, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    io_file.fixWindowsNoFollowFile(&file);
    defer file.close(io);

    var reader = file.reader(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(max_skill_file_bytes)) catch |err| switch (err) {
        error.ReadFailed => {
            if (reader.err) |read_err| return read_err;
            return error.ReadFailed;
        },
        error.OutOfMemory,
        error.StreamTooLong,
        => |e| return e,
    };
}

pub fn appendFilesSummary(writer: *Io.Writer, files: []const SummaryFile) !bool {
    var found = false;
    for (files) |file| {
        if (!isValidSkillContents(file.contents)) return error.InvalidSkillFileUtf8;
        if (!found) {
            try writer.writeAll("\n\n## Skills (skills/)\n");
            found = true;
        }
        try appendOneSummary(writer, file);
    }
    return found;
}

fn appendOneSummary(writer: *Io.Writer, file: SummaryFile) !void {
    const raw_title = titleFromContents(file.contents) orelse file.path;
    const title = if (hasInlineText(raw_title)) raw_title else file.path;
    const description = descriptionFromContents(file.contents);
    if (!hasInlineText(description)) {
        try writer.writeAll("- ");
        try writeInlineTextLimited(writer, title, max_summary_title_bytes);
        try writer.print(" (read with read_file: {s})\n", .{file.path});
    } else {
        try writer.writeAll("- ");
        try writeInlineTextLimited(writer, title, max_summary_title_bytes);
        try writer.writeAll(": ");
        try writeInlineTextLimited(writer, description, max_summary_description_bytes);
        try writer.print(" (read with read_file: {s})\n", .{file.path});
    }
}

fn isSkillFileName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!text_policy.isSingleLineText(name)) return false;
    if (path_policy.isWindowsReservedFilenameComponent(name)) return false;
    if (!std.mem.endsWith(u8, name, ".md")) return false;
    return std.mem.indexOfAny(u8, name, "/\\") == null;
}

fn isValidSkillContents(contents: []const u8) bool {
    return text_policy.isMultilineText(contents);
}

fn insertSkillName(
    allocator: Allocator,
    names: *[max_skill_count][]u8,
    name_count: *usize,
    name: []const u8,
) Allocator.Error!void {
    if (name_count.* == max_skill_count and !nameLessThan(name, names[name_count.* - 1])) return;

    const owned = try allocator.dupe(u8, name);
    errdefer allocator.free(owned);

    if (name_count.* < max_skill_count) {
        var index = name_count.*;
        while (index > 0 and nameLessThan(owned, names[index - 1])) : (index -= 1) {
            names[index] = names[index - 1];
        }
        names[index] = owned;
        name_count.* += 1;
        return;
    }

    allocator.free(names[name_count.* - 1]);
    var index = name_count.* - 1;
    while (index > 0 and nameLessThan(owned, names[index - 1])) : (index -= 1) {
        names[index] = names[index - 1];
    }
    names[index] = owned;
}

fn nameLessThan(lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn titleFromContents(contents: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "# ")) return std.mem.trim(u8, line[2..], &std.ascii.whitespace);
        return line;
    }
    return null;
}

fn descriptionFromContents(contents: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    var saw_title = false;
    var started = false;
    var start: usize = 0;
    var end: usize = 0;
    var offset: usize = 0;

    while (lines.next()) |raw| {
        const line_with_newline_len = raw.len + if (offset + raw.len < contents.len) @as(usize, 1) else 0;
        defer offset += line_with_newline_len;

        const line = std.mem.trim(u8, raw, &std.ascii.whitespace);
        if (!saw_title) {
            if (line.len == 0) continue;
            saw_title = true;
            continue;
        }
        if (line.len == 0 or std.mem.startsWith(u8, line, "##")) break;
        if (!started) {
            start = offset;
            started = true;
        }
        end = offset + raw.len;
    }

    if (!started) return "";
    return std.mem.trim(u8, contents[start..end], &std.ascii.whitespace);
}

fn hasInlineText(text: []const u8) bool {
    for (text) |byte| {
        if (!isInlineSeparator(byte)) return true;
    }
    return false;
}

fn writeInlineTextLimited(writer: *Io.Writer, text: []const u8, max_bytes: usize) !void {
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    var pending_space = false;
    var wrote = false;
    var written: usize = 0;
    var index: usize = 0;

    while (index < trimmed.len) {
        const byte = trimmed[index];
        if (isInlineSeparator(byte)) {
            pending_space = wrote;
            index += 1;
            continue;
        }

        const width = std.unicode.utf8ByteSequenceLength(byte) catch return;
        if (index + width > trimmed.len) return;
        const pending_space_bytes: usize = if (pending_space) 1 else 0;
        if (written + pending_space_bytes + width > max_bytes) return;

        if (pending_space) {
            try writer.writeByte(' ');
            written += 1;
            pending_space = false;
        }
        try writer.writeAll(trimmed[index .. index + width]);
        written += width;
        wrote = true;
        index += width;
    }
}

fn isInlineSeparator(byte: u8) bool {
    return byte < 0x20 or byte == 0x7f;
}

test "skills summary extracts title and description" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const files = [_]SummaryFile{.{
        .path = "skills/weather.md",
        .contents =
        \\# Weather
        \\Use this skill for weather checks.
        \\
        \\## Details
        \\Ignored.
        ,
    }};
    try std.testing.expect(try appendFilesSummary(&out.writer, &files));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Weather: Use this skill for weather checks.") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "skills/weather.md") != null);
}

test "skills summary keeps model-facing index lines compact" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const files = [_]SummaryFile{.{
        .path = "skills/deploy.md",
        .contents = "# Deploy\n" ++
            "First line.\n" ++
            "Second line\twith tab.\n\n" ++
            "## Details\n" ++
            "Ignored.\n",
    }};
    try std.testing.expect(try appendFilesSummary(&out.writer, &files));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "Deploy: First line. Second line with tab.") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\nSecond line") == null);
}

test "skills summary caps long inline title and description" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const long_title =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const long_description =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const files = [_]SummaryFile{.{
        .path = "skills/long.md",
        .contents = "# " ++ long_title ++ "\n" ++ long_description,
    }};
    try std.testing.expect(try appendFilesSummary(&out.writer, &files));

    try std.testing.expect(std.mem.indexOf(u8, out.written(), long_title) == null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), long_description) == null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), long_title[0..max_summary_title_bytes]) != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), long_description[0..max_summary_description_bytes]) != null);
}

test "skills inline cap does not split utf-8 sequences" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try writeInlineTextLimited(&out.writer, "éx", 1);
    try std.testing.expectEqualStrings("", out.written());

    out.clearRetainingCapacity();
    try writeInlineTextLimited(&out.writer, "éx", 2);
    try std.testing.expectEqualStrings("é", out.written());
}

test "in-memory skills summary validates markdown contents" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const files = [_]SummaryFile{.{
        .path = "skills/bad.md",
        .contents = "# Bad\nno\x1bpe",
    }};
    try std.testing.expectError(error.InvalidSkillFileUtf8, appendFilesSummary(&out.writer, &files));
}

test "skills reject hidden non-markdown and nested names" {
    try std.testing.expect(isSkillFileName("deploy.md"));
    try std.testing.expect(!isSkillFileName(".secret.md"));
    try std.testing.expect(!isSkillFileName("deploy.txt"));
    try std.testing.expect(!isSkillFileName("nested/deploy.md"));
    try std.testing.expect(!isSkillFileName("bad?.md"));
    try std.testing.expect(!isSkillFileName("NUL.md"));
    try std.testing.expect(!isSkillFileName("trailing.md."));
    try std.testing.expect(!isSkillFileName("trailing.md "));
    try std.testing.expect(!isSkillFileName("bad\nname.md"));
    try std.testing.expect(!isSkillFileName("bad\xff.md"));
}

test "skills reject binary control bytes in markdown contents" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "skills", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "skills/bad.md", .data = "# Bad\nno\x1bpe" });

    const dir_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/skills", .{tmp.sub_path});
    defer std.testing.allocator.free(dir_path);

    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expectError(error.InvalidSkillFileUtf8, appendDirectorySummary(std.testing.allocator, io, &out.writer, dir_path));
}

test "skills directory summary ignores non-directory default path" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "skills", .data = "not a directory" });

    const dir_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/skills", .{tmp.sub_path});
    defer std.testing.allocator.free(dir_path);

    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expect(!try appendDirectorySummary(std.testing.allocator, io, &out.writer, dir_path));
    try std.testing.expectEqualStrings("", out.written());
}

test "skills directory summary is deterministic by filename" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "skills", .default_dir);
    try tmp.dir.createDir(io, "skills/z.md", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "skills/b.md", .data = "# B\nSecond." });
    try tmp.dir.writeFile(io, .{ .sub_path = "skills/a.md", .data = "# A\nFirst." });

    const dir_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/skills", .{tmp.sub_path});
    defer std.testing.allocator.free(dir_path);

    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expect(try appendDirectorySummary(std.testing.allocator, io, &out.writer, dir_path));

    const first = std.mem.indexOf(u8, out.written(), "A: First.").?;
    const second = std.mem.indexOf(u8, out.written(), "B: Second.").?;
    try std.testing.expect(first < second);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "z.md") == null);
}
