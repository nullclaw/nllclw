const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Kind = enum {
    neutral,
    friendly,
    technical,
    witty,
};

pub const default_kind: Kind = .neutral;
pub const names = block: {
    var value: []const u8 = "";
    for (@typeInfo(Kind).@"enum".fields, 0..) |field, index| {
        value = value ++ if (index == 0) field.name else "|" ++ field.name;
    }
    break :block value;
};

pub fn parse(value: []const u8) ?Kind {
    const trimmed = std.mem.trim(u8, value, &std.ascii.whitespace);
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        if (std.mem.eql(u8, trimmed, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub fn instruction(kind: Kind) []const u8 {
    return switch (kind) {
        .neutral => "Use a neutral, direct voice. Keep answers concise and balanced.",
        .friendly => "Use a warm, approachable voice. Stay concise and do not add filler.",
        .technical => "Use a precise engineering voice. State assumptions, tradeoffs, and concrete next steps.",
        .witty => "Use light wit when it fits. Keep the answer useful, respectful, and concise.",
    };
}

pub fn buildPrompt(allocator: Allocator, base_prompt: []const u8, kind: Kind) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll(base_prompt);
    try appendPrompt(&out.writer, kind);
    return out.toOwnedSlice();
}

pub fn appendPrompt(writer: *std.Io.Writer, kind: Kind) !void {
    try writer.print(
        "\n\n## Runtime Persona ({s})\n{s}\nThis controls presentation style only; it does not override local context, safety, memory, or tool policy files.\n",
        .{ @tagName(kind), instruction(kind) },
    );
}

test "persona parsing accepts canonical names only" {
    try std.testing.expectEqualStrings("neutral|friendly|technical|witty", names);
    try std.testing.expectEqual(Kind.neutral, parse("neutral").?);
    try std.testing.expectEqual(Kind.friendly, parse(" friendly ").?);
    try std.testing.expectEqual(Kind.technical, parse("technical").?);
    try std.testing.expectEqual(Kind.witty, parse("witty").?);
    try std.testing.expect(parse("Friendly") == null);
    try std.testing.expect(parse("TECHNICAL") == null);
    try std.testing.expect(parse("sarcastic") == null);
}

test "persona prompt appends scoped runtime instructions" {
    const prompt = try buildPrompt(std.testing.allocator, "base", .technical);
    defer std.testing.allocator.free(prompt);

    try std.testing.expect(std.mem.indexOf(u8, prompt, "base") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "Runtime Persona (technical)") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt, "presentation style only") != null);
}
