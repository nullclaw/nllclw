const std = @import("std");
const diagnostics = @import("../diagnostics.zig");
const persona = @import("../persona.zig");

pub const Command = union(enum) {
    none,
    help,
    chat_id,
    settings,
    diag: diagnostics.Scope,
    invalid_diag,
    persona: PersonaCommand,
    pause,
    resume_intake,
};

pub const PersonaCommand = union(enum) {
    show,
    set: persona.Kind,
    invalid,
};

pub const help_text =
    \\nllclw commands:
    \\  /start, /help          show this help
    \\  /settings              show local runtime status
    \\  /diag [scope]          show diagnostics: quick, runtime, memory, rates, time, all
    \\  /persona [mode]        show or set persona: neutral, friendly, technical, witty
    \\  /stop                  pause Telegram intake for this process
    \\  /resume                resume Telegram intake
    \\  /chatid                print Telegram chat id
    \\
;

pub fn parse(line: []const u8) Command {
    const text = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (text.len == 0 or text[0] != '/') return .none;

    if (matches(text, "start") or matches(text, "help")) return .help;
    if (matches(text, "chatid")) return .chat_id;
    if (matches(text, "settings")) return .settings;
    if (matches(text, "stop")) return .pause;
    if (matches(text, "resume")) return .resume_intake;
    if (matches(text, "persona")) return .{ .persona = parsePersona(payloadFor(text, "persona")) };
    if (matches(text, "diag")) {
        const payload = payloadFor(text, "diag");
        return if (parseDiagScope(payload)) |scope| .{ .diag = scope } else .invalid_diag;
    }
    return .none;
}

fn matches(text: []const u8, name: []const u8) bool {
    if (text.len < name.len + 1 or text[0] != '/') return false;
    if (!std.mem.eql(u8, text[1 .. 1 + name.len], name)) return false;
    if (text.len == name.len + 1) return true;
    const next = text[name.len + 1];
    if (std.ascii.isWhitespace(next)) return true;
    if (next != '@') return false;
    var index = name.len + 2;
    if (index >= text.len) return false;
    while (index < text.len and !std.ascii.isWhitespace(text[index])) : (index += 1) {}
    return true;
}

fn payloadFor(text: []const u8, name: []const u8) []const u8 {
    var index: usize = name.len + 1;
    if (index < text.len and text[index] == '@') {
        index += 1;
        while (index < text.len and !std.ascii.isWhitespace(text[index])) : (index += 1) {}
    }
    while (index < text.len and std.ascii.isWhitespace(text[index])) : (index += 1) {}
    return text[index..];
}

fn parseDiagScope(payload: []const u8) ?diagnostics.Scope {
    var parts = std.mem.tokenizeAny(u8, payload, " \t\r\n");
    const first = parts.next() orelse return .quick;
    if (parts.next() != null) return null;
    return diagnostics.parseScopeName(first);
}

fn parsePersona(payload: []const u8) PersonaCommand {
    var parts = std.mem.tokenizeAny(u8, payload, " \t\r\n");
    const first = parts.next() orelse return .show;
    if (parts.next() != null) return .invalid;
    const kind = persona.parse(first) orelse return .invalid;
    return .{ .set = kind };
}

test "slash command parser supports bot suffix and payload" {
    try std.testing.expectEqual(Command.help, parse("/help@my_bot"));
    try std.testing.expectEqual(Command.chat_id, parse(" /chatid "));
    try std.testing.expectEqual(diagnostics.Scope.memory, parse("/diag memory").diag);
    try std.testing.expectEqual(Command.invalid_diag, parse("/diag typo"));
    try std.testing.expectEqual(Command.invalid_diag, parse("/diag memory extra"));
    try std.testing.expectEqual(PersonaCommand.show, parse("/persona").persona);
    try std.testing.expectEqual(persona.Kind.technical, parse("/persona@my_bot technical").persona.set);
    try std.testing.expectEqual(PersonaCommand.invalid, parse("/persona loud").persona);
    try std.testing.expectEqual(PersonaCommand.invalid, parse("/persona technical extra").persona);
    try std.testing.expectEqual(Command.none, parse("/unknown"));
}
