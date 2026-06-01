const std = @import("std");
const chat = @import("./chat.zig");
const config_types = @import("./config/types.zig");
const text_policy = @import("./text_policy.zig");

const Allocator = std.mem.Allocator;

pub const Config = config_types.MemoryConfig;

pub const max_file_bytes = 256 * 1024;
pub const default_max_facts: usize = config_types.default_memory_max_facts;
pub const min_max_messages: usize = config_types.min_memory_max_messages;
pub const min_max_facts: usize = config_types.min_memory_max_facts;
pub const max_max_facts: usize = config_types.max_memory_max_facts;
pub const max_fact_key_bytes: usize = 64;
pub const max_fact_value_bytes: usize = 2048;

pub const Error = error{
    InvalidMemoryKey,
    InvalidMemoryLimit,
    InvalidMemoryLine,
    InvalidMemoryRole,
};

pub const StoreError = Error || Allocator.Error || error{
    StorageFailed,
    StreamTooLong,
};

pub const BuildError = Error || Allocator.Error || error{
    StreamTooLong,
};

pub const ParseError = Error || Allocator.Error;

pub const Entry = struct {
    role: []const u8,
    content: []const u8,
};

pub const Transcript = struct {
    entries: []Entry = &.{},

    pub fn deinit(self: *Transcript, allocator: Allocator) void {
        for (self.entries) |entry| freeEntry(allocator, entry);
        allocator.free(self.entries);
        self.* = .{};
    }
};

pub const Fact = struct {
    key: []const u8,
    value: []const u8,
};

pub const Facts = struct {
    entries: []Fact = &.{},

    pub fn deinit(self: *Facts, allocator: Allocator) void {
        for (self.entries) |entry| freeFact(allocator, entry);
        allocator.free(self.entries);
        self.* = .{};
    }
};

pub const TranscriptStore = struct {
    ptr: *anyopaque,
    load_fn: *const fn (*anyopaque, Allocator, usize) StoreError!Transcript,
    append_fn: *const fn (*anyopaque, Allocator, []const u8, []const u8, usize) StoreError!void,

    pub fn load(self: TranscriptStore, allocator: Allocator, max_messages: usize) StoreError!Transcript {
        try validateMaxMessages(max_messages);
        return self.load_fn(self.ptr, allocator, max_messages);
    }

    pub fn append(
        self: TranscriptStore,
        allocator: Allocator,
        user_prompt: []const u8,
        assistant_text: []const u8,
        max_messages: usize,
    ) StoreError!void {
        try validateMaxMessages(max_messages);
        return self.append_fn(self.ptr, allocator, user_prompt, assistant_text, max_messages);
    }
};

pub const FactStore = struct {
    ptr: *anyopaque,
    put_fn: *const fn (*anyopaque, Allocator, []const u8, []const u8, usize) StoreError!void,
    get_fn: *const fn (*anyopaque, Allocator, []const u8, usize) StoreError!?[]u8,
    list_fn: *const fn (*anyopaque, Allocator, usize) StoreError!Facts,
    delete_fn: *const fn (*anyopaque, Allocator, []const u8, usize) StoreError!bool,

    pub fn put(self: FactStore, allocator: Allocator, key: []const u8, value: []const u8, max_facts: usize) StoreError!void {
        try validateMaxFacts(max_facts);
        try self.put_fn(self.ptr, allocator, key, value, max_facts);
    }

    pub fn get(self: FactStore, allocator: Allocator, key: []const u8, max_facts: usize) StoreError!?[]u8 {
        try validateMaxFacts(max_facts);
        return try self.get_fn(self.ptr, allocator, key, max_facts);
    }

    pub fn list(self: FactStore, allocator: Allocator, max_facts: usize) StoreError!Facts {
        try validateMaxFacts(max_facts);
        return try self.list_fn(self.ptr, allocator, max_facts);
    }

    pub fn delete(self: FactStore, allocator: Allocator, key: []const u8, max_facts: usize) StoreError!bool {
        try validateMaxFacts(max_facts);
        return try self.delete_fn(self.ptr, allocator, key, max_facts);
    }
};

pub const State = struct {
    enabled: bool = false,
    transcript: Transcript = .{},
    history_messages: []chat.RequestMessage = &.{},

    pub fn deinit(self: *State, allocator: Allocator) void {
        if (self.history_messages.len != 0) allocator.free(self.history_messages);
        self.transcript.deinit(allocator);
        self.* = .{};
    }
};

const ParsedEntry = struct {
    role: []const u8,
    content: []const u8,
};

const ParsedFact = struct {
    key: []const u8,
    value: []const u8,
};

pub fn parseJsonl(allocator: Allocator, bytes: []const u8, max_messages: usize) ParseError!Transcript {
    try validateMaxMessages(max_messages);

    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        deinitEntries(allocator, entries.items);
        entries.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(ParsedEntry, allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidMemoryLine,
        };
        defer parsed.deinit();

        if (!isMemoryRole(parsed.value.role)) return error.InvalidMemoryRole;
        if (!isValidMemoryContent(parsed.value.content)) return error.InvalidMemoryLine;
        const role = try allocator.dupe(u8, parsed.value.role);
        errdefer allocator.free(role);
        const content = try allocator.dupe(u8, parsed.value.content);
        errdefer allocator.free(content);
        try entries.append(allocator, .{
            .role = role,
            .content = content,
        });

        while (entries.items.len > max_messages) {
            const removed = entries.orderedRemove(0);
            freeEntry(allocator, removed);
        }
    }

    return .{ .entries = try entries.toOwnedSlice(allocator) };
}

pub fn parseFactsJsonl(allocator: Allocator, bytes: []const u8, max_facts: usize) ParseError!Facts {
    try validateMaxFacts(max_facts);

    var entries: std.ArrayList(Fact) = .empty;
    errdefer {
        deinitFacts(allocator, entries.items);
        entries.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(ParsedFact, allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidMemoryLine,
        };
        defer parsed.deinit();

        const key = std.mem.trim(u8, parsed.value.key, &std.ascii.whitespace);
        if (!isValidFactKey(key)) return error.InvalidMemoryKey;
        if (!isValidFactValue(parsed.value.value)) return error.InvalidMemoryLine;

        for (entries.items, 0..) |entry, index| {
            if (std.mem.eql(u8, entry.key, key)) {
                const removed = entries.orderedRemove(index);
                freeFact(allocator, removed);
                break;
            }
        }

        const owned_key = try allocator.dupe(u8, key);
        errdefer allocator.free(owned_key);
        const owned_value = try allocator.dupe(u8, parsed.value.value);
        errdefer allocator.free(owned_value);
        try entries.append(allocator, .{
            .key = owned_key,
            .value = owned_value,
        });

        while (entries.items.len > max_facts) {
            const removed = entries.orderedRemove(0);
            freeFact(allocator, removed);
        }
    }

    return .{ .entries = try entries.toOwnedSlice(allocator) };
}

pub fn validateMaxMessages(max_messages: usize) Error!void {
    if (max_messages < min_max_messages) return error.InvalidMemoryLimit;
}

pub fn validateMaxFacts(max_facts: usize) Error!void {
    if (max_facts < min_max_facts or max_facts > max_max_facts) return error.InvalidMemoryLimit;
}

pub fn toRequestMessages(allocator: Allocator, entries: []const Entry) Allocator.Error![]chat.RequestMessage {
    const messages = try allocator.alloc(chat.RequestMessage, entries.len);
    for (entries, messages) |entry, *message| {
        message.* = .{
            .role = entry.role,
            .content = entry.content,
        };
    }
    return messages;
}

pub fn loadState(allocator: Allocator, cfg: Config, store: TranscriptStore) StoreError!State {
    if (!cfg.enabled) return .{};

    var transcript = try store.load(allocator, cfg.max_messages);
    errdefer transcript.deinit(allocator);

    const history_messages = try toRequestMessages(allocator, transcript.entries);
    errdefer if (history_messages.len != 0) allocator.free(history_messages);

    return .{
        .enabled = true,
        .transcript = transcript,
        .history_messages = history_messages,
    };
}

pub fn appendTurn(
    allocator: Allocator,
    cfg: Config,
    store: TranscriptStore,
    user_prompt: []const u8,
    assistant_text: []const u8,
) StoreError!void {
    if (!cfg.enabled) return;
    try store.append(allocator, user_prompt, assistant_text, cfg.max_messages);
}

pub fn buildUpdatedJsonl(
    allocator: Allocator,
    history: []const Entry,
    user_prompt: []const u8,
    assistant_text: []const u8,
    max_messages: usize,
) BuildError![]u8 {
    try validateMaxMessages(max_messages);

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    const total = history.len + 2;
    const start = if (total > max_messages) total - max_messages else 0;

    for (0..total) |index| {
        if (index < start) continue;
        if (index < history.len) {
            try writeEntry(&out.writer, history[index].role, history[index].content);
        } else if (index == history.len) {
            try writeEntry(&out.writer, "user", user_prompt);
        } else {
            try writeEntry(&out.writer, "assistant", assistant_text);
        }
        try ensureJsonlFits(&out);
    }

    return out.toOwnedSlice();
}

pub fn buildFactsJsonl(allocator: Allocator, facts: []const Fact) BuildError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    for (facts) |fact| {
        try writeFact(&out.writer, fact.key, fact.value);
        try ensureJsonlFits(&out);
    }
    return out.toOwnedSlice();
}

pub fn isValidFactKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_fact_key_bytes) return false;
    for (key) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (byte == '_' or byte == '-' or byte == '.') continue;
        return false;
    }
    return true;
}

pub fn isValidFactValue(value: []const u8) bool {
    if (value.len == 0 or value.len > max_fact_value_bytes) return false;
    if (std.mem.trim(u8, value, &std.ascii.whitespace).len == 0) return false;
    return text_policy.isSingleLineText(value);
}

fn writeEntry(writer: *std.Io.Writer, role: []const u8, content: []const u8) (Error || Allocator.Error)!void {
    if (!isMemoryRole(role)) return error.InvalidMemoryRole;
    if (!isValidMemoryContent(content)) return error.InvalidMemoryLine;

    var json: std.json.Stringify = .{
        .writer = writer,
        .options = .{},
    };

    json.beginObject() catch return error.OutOfMemory;
    json.objectField("role") catch return error.OutOfMemory;
    json.write(role) catch return error.OutOfMemory;
    json.objectField("content") catch return error.OutOfMemory;
    json.write(content) catch return error.OutOfMemory;
    json.endObject() catch return error.OutOfMemory;
    writer.writeByte('\n') catch return error.OutOfMemory;
}

fn writeFact(writer: *std.Io.Writer, key: []const u8, value: []const u8) (Error || Allocator.Error)!void {
    if (!isValidFactKey(key)) return error.InvalidMemoryKey;
    if (!isValidFactValue(value)) return error.InvalidMemoryLine;

    var json: std.json.Stringify = .{
        .writer = writer,
        .options = .{},
    };

    json.beginObject() catch return error.OutOfMemory;
    json.objectField("key") catch return error.OutOfMemory;
    json.write(key) catch return error.OutOfMemory;
    json.objectField("value") catch return error.OutOfMemory;
    json.write(value) catch return error.OutOfMemory;
    json.endObject() catch return error.OutOfMemory;
    writer.writeByte('\n') catch return error.OutOfMemory;
}

fn ensureJsonlFits(out: *std.Io.Writer.Allocating) error{StreamTooLong}!void {
    if (out.written().len > max_file_bytes) return error.StreamTooLong;
}

fn isMemoryRole(role: []const u8) bool {
    return std.mem.eql(u8, role, "user") or std.mem.eql(u8, role, "assistant");
}

fn isValidMemoryContent(content: []const u8) bool {
    return text_policy.isMultilineText(content);
}

fn freeEntry(allocator: Allocator, entry: Entry) void {
    allocator.free(entry.role);
    allocator.free(entry.content);
}

fn deinitEntries(allocator: Allocator, entries: []Entry) void {
    for (entries) |entry| freeEntry(allocator, entry);
}

fn freeFact(allocator: Allocator, fact: Fact) void {
    allocator.free(fact.key);
    allocator.free(fact.value);
}

fn deinitFacts(allocator: Allocator, entries: []Fact) void {
    for (entries) |entry| freeFact(allocator, entry);
}

test "parses jsonl transcript and keeps newest messages" {
    var transcript = try parseJsonl(
        std.testing.allocator,
        "{\"role\":\"user\",\"content\":\"one\"}\n{\"role\":\"assistant\",\"content\":\"two\"}\n{\"role\":\"user\",\"content\":\"three\"}\n",
        2,
    );
    defer transcript.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), transcript.entries.len);
    try std.testing.expectEqualStrings("assistant", transcript.entries[0].role);
    try std.testing.expectEqualStrings("two", transcript.entries[0].content);
    try std.testing.expectEqualStrings("user", transcript.entries[1].role);
    try std.testing.expectEqualStrings("three", transcript.entries[1].content);
}

test "parses fact memory and keeps newest facts" {
    var facts = try parseFactsJsonl(
        std.testing.allocator,
        "{\"key\":\"name\",\"value\":\"nllclw\"}\n{\"key\":\"lang\",\"value\":\"zig\"}\n",
        1,
    );
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), facts.entries.len);
    try std.testing.expectEqualStrings("lang", facts.entries[0].key);
    try std.testing.expectEqualStrings("zig", facts.entries[0].value);
}

test "fact memory duplicate keys are last wins" {
    var facts = try parseFactsJsonl(
        std.testing.allocator,
        "{\"key\":\"name\",\"value\":\"old\"}\n{\"key\":\"name\",\"value\":\"new\"}\n",
        8,
    );
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), facts.entries.len);
    try std.testing.expectEqualStrings("name", facts.entries[0].key);
    try std.testing.expectEqualStrings("new", facts.entries[0].value);
}

test "validates fact keys" {
    try std.testing.expect(isValidFactKey("project.name"));
    try std.testing.expect(isValidFactKey("user-name"));
    try std.testing.expect(!isValidFactKey(""));
    try std.testing.expect(!isValidFactKey("../secret"));
    try std.testing.expect(!isValidFactKey("has space"));
}

test "validates fact values" {
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"\"}\n", 8),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"   \"}\n", 8),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"bad\\u0000value\"}\n", 8),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"bad\\nvalue\"}\n", 8),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"bad\\u001bvalue\"}\n", 8),
    );
}

test "rejects invalid memory retention limits" {
    try std.testing.expectError(
        error.InvalidMemoryLimit,
        parseJsonl(std.testing.allocator, "{\"role\":\"user\",\"content\":\"one\"}\n", min_max_messages - 1),
    );
    try std.testing.expectError(
        error.InvalidMemoryLimit,
        buildUpdatedJsonl(std.testing.allocator, &.{}, "user", "assistant", min_max_messages - 1),
    );
    try std.testing.expectError(
        error.InvalidMemoryLimit,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"nllclw\"}\n", min_max_facts - 1),
    );
    try std.testing.expectError(
        error.InvalidMemoryLimit,
        parseFactsJsonl(std.testing.allocator, "{\"key\":\"name\",\"value\":\"nllclw\"}\n", max_max_facts + 1),
    );
}

test "builds fact jsonl with escaping" {
    const facts = [_]Fact{
        .{ .key = "quote", .value = "say \"hi\"" },
    };
    const jsonl = try buildFactsJsonl(std.testing.allocator, &facts);
    defer std.testing.allocator.free(jsonl);

    try std.testing.expectEqualStrings("{\"key\":\"quote\",\"value\":\"say \\\"hi\\\"\"}\n", jsonl);
}

test "jsonl builders reject invalid domain text" {
    const history = [_]Entry{
        .{ .role = "system", .content = "bad role" },
    };
    try std.testing.expectError(
        error.InvalidMemoryRole,
        buildUpdatedJsonl(std.testing.allocator, &history, "user", "assistant", 4),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        buildUpdatedJsonl(std.testing.allocator, &.{}, "bad\xff", "assistant", 4),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        buildUpdatedJsonl(std.testing.allocator, &.{}, "bad\x1bprompt", "assistant", 4),
    );

    const facts = [_]Fact{
        .{ .key = "ok", .value = "bad\xff" },
    };
    try std.testing.expectError(error.InvalidMemoryLine, buildFactsJsonl(std.testing.allocator, &facts));

    const control_fact = [_]Fact{
        .{ .key = "ok", .value = "bad\x1bvalue" },
    };
    try std.testing.expectError(error.InvalidMemoryLine, buildFactsJsonl(std.testing.allocator, &control_fact));
}

test "jsonl builders reject snapshots larger than the readable memory file limit" {
    const allocator = std.testing.allocator;

    const large_content = try allocator.alloc(u8, max_file_bytes);
    defer allocator.free(large_content);
    @memset(large_content, 'x');

    try std.testing.expectError(
        error.StreamTooLong,
        buildUpdatedJsonl(allocator, &.{}, large_content, "assistant", 4),
    );

    const large_fact_value = try allocator.alloc(u8, max_fact_value_bytes);
    defer allocator.free(large_fact_value);
    @memset(large_fact_value, 'v');

    const facts = try allocator.alloc(Fact, 140);
    defer allocator.free(facts);
    for (facts) |*fact| {
        fact.* = .{ .key = "k", .value = large_fact_value };
    }

    try std.testing.expectError(error.StreamTooLong, buildFactsJsonl(allocator, facts));
}

test "rejects invalid memory line and role" {
    try std.testing.expectError(error.InvalidMemoryLine, parseJsonl(std.testing.allocator, "not-json\n", 20));
    try std.testing.expectError(
        error.InvalidMemoryRole,
        parseJsonl(std.testing.allocator, "{\"role\":\"system\",\"content\":\"x\"}\n", 20),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseJsonl(std.testing.allocator, "{\"role\":\"user\",\"content\":\"bad\xff\"}\n", 20),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseJsonl(std.testing.allocator, "{\"role\":\"user\",\"content\":\"bad\\u0000value\"}\n", 20),
    );
    try std.testing.expectError(
        error.InvalidMemoryLine,
        parseJsonl(std.testing.allocator, "{\"role\":\"user\",\"content\":\"bad\\u001bvalue\"}\n", 20),
    );
}

test "memory parsers preserve allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn runTranscript(allocator: Allocator) !void {
            var transcript = try parseJsonl(allocator, "{\"role\":\"user\",\"content\":\"hello\"}\n", 20);
            defer transcript.deinit(allocator);
            try std.testing.expectEqualStrings("hello", transcript.entries[0].content);
        }
    }.runTranscript, .{});

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn runFacts(allocator: Allocator) !void {
            var facts = try parseFactsJsonl(allocator, "{\"key\":\"name\",\"value\":\"nllclw\"}\n", 20);
            defer facts.deinit(allocator);
            try std.testing.expectEqualStrings("nllclw", facts.entries[0].value);
        }
    }.runFacts, .{});
}

test "builds updated jsonl snapshot with escaping and trimming" {
    var transcript = try parseJsonl(
        std.testing.allocator,
        "{\"role\":\"user\",\"content\":\"old\"}\n{\"role\":\"assistant\",\"content\":\"older\"}\n",
        20,
    );
    defer transcript.deinit(std.testing.allocator);

    const jsonl = try buildUpdatedJsonl(std.testing.allocator, transcript.entries, "say \"hi\"", "ok\nnow", 3);
    defer std.testing.allocator.free(jsonl);

    const expected =
        "{\"role\":\"assistant\",\"content\":\"older\"}\n" ++
        "{\"role\":\"user\",\"content\":\"say \\\"hi\\\"\"}\n" ++
        "{\"role\":\"assistant\",\"content\":\"ok\\nnow\"}\n";
    try std.testing.expectEqualStrings(expected, jsonl);
}

const FakeTranscriptStore = struct {
    transcript: []const Entry = &.{},
    appended: bool = false,

    fn port(self: *FakeTranscriptStore) TranscriptStore {
        return .{
            .ptr = self,
            .load_fn = load,
            .append_fn = append,
        };
    }

    fn load(ptr: *anyopaque, allocator: Allocator, _: usize) StoreError!Transcript {
        const self: *FakeTranscriptStore = @ptrCast(@alignCast(ptr));
        var entries = try allocator.alloc(Entry, self.transcript.len);
        var initialized: usize = 0;
        errdefer {
            for (entries[0..initialized]) |entry| {
                allocator.free(entry.role);
                allocator.free(entry.content);
            }
            allocator.free(entries);
        }

        for (self.transcript, entries) |entry, *out| {
            const role = try allocator.dupe(u8, entry.role);
            errdefer allocator.free(role);
            const content = try allocator.dupe(u8, entry.content);
            errdefer allocator.free(content);
            out.* = .{
                .role = role,
                .content = content,
            };
            initialized += 1;
        }
        return .{ .entries = entries };
    }

    fn append(ptr: *anyopaque, _: Allocator, _: []const u8, _: []const u8, _: usize) StoreError!void {
        const self: *FakeTranscriptStore = @ptrCast(@alignCast(ptr));
        self.appended = true;
    }
};

test "memory state is skipped when disabled" {
    var fake: FakeTranscriptStore = .{};
    var state = try loadState(std.testing.allocator, .{ .enabled = false }, fake.port());
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(!state.enabled);
    try std.testing.expectEqual(@as(usize, 0), state.history_messages.len);
}

test "memory state loads request messages through port" {
    const entries = [_]Entry{
        .{ .role = "user", .content = "one" },
        .{ .role = "assistant", .content = "two" },
    };
    var fake: FakeTranscriptStore = .{ .transcript = &entries };
    var state = try loadState(std.testing.allocator, .{}, fake.port());
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.enabled);
    try std.testing.expectEqualStrings("user", state.history_messages[0].role);
    try std.testing.expectEqualStrings("two", state.history_messages[1].content.?);
}

test "append turn is skipped when memory is disabled" {
    var fake: FakeTranscriptStore = .{};
    try appendTurn(std.testing.allocator, .{ .enabled = false }, fake.port(), "u", "a");
    try std.testing.expect(!fake.appended);

    try appendTurn(std.testing.allocator, .{}, fake.port(), "u", "a");
    try std.testing.expect(fake.appended);
}
