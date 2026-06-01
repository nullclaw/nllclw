const std = @import("std");
const memory = @import("../memory.zig");
const state_file = @import("./state_file.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Store = struct {
    io: Io,
    path: []const u8,

    pub fn port(self: *Store) memory.TranscriptStore {
        return .{
            .ptr = self,
            .load_fn = loadPort,
            .append_fn = appendPort,
        };
    }

    fn loadPort(ptr: *anyopaque, allocator: Allocator, max_messages: usize) memory.StoreError!memory.Transcript {
        const self: *Store = @ptrCast(@alignCast(ptr));
        return load(allocator, self.io, self.path, max_messages);
    }

    fn appendPort(
        ptr: *anyopaque,
        allocator: Allocator,
        user_prompt: []const u8,
        assistant_text: []const u8,
        max_messages: usize,
    ) memory.StoreError!void {
        const self: *Store = @ptrCast(@alignCast(ptr));
        return append(allocator, self.io, self.path, user_prompt, assistant_text, max_messages);
    }
};

pub const FactStore = struct {
    io: Io,
    path: []const u8,

    pub fn port(self: *FactStore) memory.FactStore {
        return .{
            .ptr = self,
            .put_fn = putFactPort,
            .get_fn = getFactPort,
            .list_fn = listFactsPort,
            .delete_fn = deleteFactPort,
        };
    }

    fn putFactPort(ptr: *anyopaque, allocator: Allocator, key: []const u8, value: []const u8, max_facts: usize) memory.StoreError!void {
        const self: *FactStore = @ptrCast(@alignCast(ptr));
        return putFact(allocator, self.io, self.path, key, value, max_facts);
    }

    fn getFactPort(ptr: *anyopaque, allocator: Allocator, key: []const u8, max_facts: usize) memory.StoreError!?[]u8 {
        const self: *FactStore = @ptrCast(@alignCast(ptr));
        return getFact(allocator, self.io, self.path, key, max_facts);
    }

    fn listFactsPort(ptr: *anyopaque, allocator: Allocator, max_facts: usize) memory.StoreError!memory.Facts {
        const self: *FactStore = @ptrCast(@alignCast(ptr));
        return loadFacts(allocator, self.io, self.path, max_facts);
    }

    fn deleteFactPort(ptr: *anyopaque, allocator: Allocator, key: []const u8, max_facts: usize) memory.StoreError!bool {
        const self: *FactStore = @ptrCast(@alignCast(ptr));
        return deleteFact(allocator, self.io, self.path, key, max_facts);
    }
};

pub fn load(allocator: Allocator, io: Io, path: []const u8, max_messages: usize) memory.StoreError!memory.Transcript {
    try memory.validateMaxMessages(max_messages);

    const contents = (state_file.readAlloc(allocator, io, path, memory.max_file_bytes) catch |err| return mapReadError(err)) orelse return .{};
    defer allocator.free(contents);

    return memory.parseJsonl(allocator, contents, max_messages);
}

pub fn append(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    user_prompt: []const u8,
    assistant_text: []const u8,
    max_messages: usize,
) memory.StoreError!void {
    try memory.validateMaxMessages(max_messages);

    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);

    var latest = try load(allocator, io, path, max_messages);
    defer latest.deinit(allocator);

    const snapshot = try memory.buildUpdatedJsonl(
        allocator,
        latest.entries,
        user_prompt,
        assistant_text,
        max_messages,
    );
    defer allocator.free(snapshot);

    try writeAtomic(io, path, snapshot);
}

pub fn loadFacts(allocator: Allocator, io: Io, path: []const u8, max_facts: usize) memory.StoreError!memory.Facts {
    try memory.validateMaxFacts(max_facts);

    const contents = (state_file.readAlloc(allocator, io, path, memory.max_file_bytes) catch |err| return mapReadError(err)) orelse return .{};
    defer allocator.free(contents);

    return memory.parseFactsJsonl(allocator, contents, max_facts);
}

pub fn clear(allocator: Allocator, io: Io, path: []const u8) memory.StoreError!void {
    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);
    try writeAtomic(io, path, "");
}

pub fn getFact(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    key: []const u8,
    max_facts: usize,
) memory.StoreError!?[]u8 {
    try memory.validateMaxFacts(max_facts);
    if (!memory.isValidFactKey(key)) return error.InvalidMemoryKey;
    var facts = try loadFacts(allocator, io, path, max_facts);
    defer facts.deinit(allocator);

    for (facts.entries) |fact| {
        if (std.mem.eql(u8, fact.key, key)) return try allocator.dupe(u8, fact.value);
    }
    return null;
}

pub fn putFact(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    key: []const u8,
    value: []const u8,
    max_facts: usize,
) memory.StoreError!void {
    try memory.validateMaxFacts(max_facts);
    if (!memory.isValidFactKey(key)) return error.InvalidMemoryKey;
    if (!memory.isValidFactValue(value)) return error.InvalidMemoryLine;

    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);

    var latest = try loadFacts(allocator, io, path, max_facts);
    defer latest.deinit(allocator);

    var updated = try updatedFacts(allocator, latest.entries, key, value, true, max_facts);
    defer updated.deinit(allocator);
    defer deinitFactSlice(allocator, updated.items);

    const snapshot = try memory.buildFactsJsonl(allocator, updated.items);
    defer allocator.free(snapshot);
    try writeAtomic(io, path, snapshot);
}

pub fn deleteFact(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    key: []const u8,
    max_facts: usize,
) memory.StoreError!bool {
    try memory.validateMaxFacts(max_facts);
    if (!memory.isValidFactKey(key)) return error.InvalidMemoryKey;

    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);

    var latest = try loadFacts(allocator, io, path, max_facts);
    defer latest.deinit(allocator);

    var updated = try updatedFacts(allocator, latest.entries, key, "", false, max_facts);
    defer updated.deinit(allocator);
    defer deinitFactSlice(allocator, updated.items);

    const deleted = updated.items.len != latest.entries.len;
    if (!deleted) return false;

    const snapshot = try memory.buildFactsJsonl(allocator, updated.items);
    defer allocator.free(snapshot);
    try writeAtomic(io, path, snapshot);
    return deleted;
}

fn updatedFacts(
    allocator: Allocator,
    facts: []const memory.Fact,
    key: []const u8,
    value: []const u8,
    upsert: bool,
    max_facts: usize,
) memory.StoreError!std.ArrayList(memory.Fact) {
    var updated: std.ArrayList(memory.Fact) = .empty;
    errdefer {
        deinitFactSlice(allocator, updated.items);
        updated.deinit(allocator);
    }

    for (facts) |fact| {
        if (std.mem.eql(u8, fact.key, key)) {
            continue;
        } else {
            try appendFact(allocator, &updated, fact.key, fact.value);
        }
    }

    if (upsert) try appendFact(allocator, &updated, key, value);
    while (updated.items.len > max_facts) {
        const removed = updated.orderedRemove(0);
        freeFact(allocator, removed);
    }
    return updated;
}

fn appendFact(allocator: Allocator, facts: *std.ArrayList(memory.Fact), key: []const u8, value: []const u8) memory.StoreError!void {
    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);
    const owned_value = try allocator.dupe(u8, value);
    errdefer allocator.free(owned_value);
    try facts.append(allocator, .{
        .key = owned_key,
        .value = owned_value,
    });
}

fn deinitFactSlice(allocator: Allocator, facts: []memory.Fact) void {
    for (facts) |fact| freeFact(allocator, fact);
}

fn freeFact(allocator: Allocator, fact: memory.Fact) void {
    allocator.free(fact.key);
    allocator.free(fact.value);
}

fn lockPath(allocator: Allocator, io: Io, path: []const u8) memory.StoreError!Io.File {
    return state_file.lockPath(allocator, io, path) catch |err| return mapStorageError(err);
}

fn writeAtomic(io: Io, path: []const u8, snapshot: []const u8) memory.StoreError!void {
    state_file.writeAtomic(io, path, snapshot) catch |err| return mapStorageError(err);
}

fn mapReadError(err: anyerror) memory.StoreError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
        else => error.StorageFailed,
    };
}

fn mapStorageError(err: anyerror) memory.StoreError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.StorageFailed,
    };
}

test "file memory clear uses adapter storage path" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/memory.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try append(std.testing.allocator, io, path, "hello", "world", 20);
    var before = try load(std.testing.allocator, io, path, 20);
    defer before.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), before.entries.len);

    try clear(std.testing.allocator, io, path);
    var after = try load(std.testing.allocator, io, path, 20);
    defer after.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), after.entries.len);
}

test "file memory creates parent directories for configured state paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/memory.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const facts_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/facts.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(facts_path);

    try append(std.testing.allocator, io, path, "hello", "world", 20);
    var transcript = try load(std.testing.allocator, io, path, 20);
    defer transcript.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), transcript.entries.len);

    try putFact(std.testing.allocator, io, facts_path, "city", "Paris", 4);
    const fact = (try getFact(std.testing.allocator, io, facts_path, "city", 4)).?;
    defer std.testing.allocator.free(fact);
    try std.testing.expectEqualStrings("Paris", fact);
}

test "file fact store supports put get list delete and max retention" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/facts.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try putFact(std.testing.allocator, io, path, "first", "one", 2);
    try putFact(std.testing.allocator, io, path, "second", "two", 2);
    try putFact(std.testing.allocator, io, path, "first", "one again", 2);
    try putFact(std.testing.allocator, io, path, "third", "three", 2);

    const dropped = try getFact(std.testing.allocator, io, path, "second", 2);
    try std.testing.expect(dropped == null);

    const first = (try getFact(std.testing.allocator, io, path, "first", 2)).?;
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("one again", first);

    var facts = try loadFacts(std.testing.allocator, io, path, 2);
    defer facts.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), facts.entries.len);
    try std.testing.expectEqualStrings("first", facts.entries[0].key);
    try std.testing.expectEqualStrings("third", facts.entries[1].key);

    try std.testing.expect(try deleteFact(std.testing.allocator, io, path, "first", 2));
    try std.testing.expect(!try deleteFact(std.testing.allocator, io, path, "missing", 2));
    const after_delete = try getFact(std.testing.allocator, io, path, "first", 2);
    try std.testing.expect(after_delete == null);
}

test "file fact store rejects invalid keys and values" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/facts.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.expectError(error.InvalidMemoryKey, putFact(std.testing.allocator, io, path, "bad key", "value", 4));
    try std.testing.expectError(error.InvalidMemoryLine, putFact(std.testing.allocator, io, path, "good", "", 4));
    try std.testing.expectError(error.InvalidMemoryLine, putFact(std.testing.allocator, io, path, "good", "bad\x00value", 4));
    try std.testing.expectError(error.InvalidMemoryLine, putFact(std.testing.allocator, io, path, "good", "bad\nvalue", 4));
    try std.testing.expectError(error.InvalidMemoryLine, putFact(std.testing.allocator, io, path, "good", "bad\x1bvalue", 4));
    try std.testing.expectError(error.InvalidMemoryKey, getFact(std.testing.allocator, io, path, "bad key", 4));
    try std.testing.expectError(error.InvalidMemoryKey, deleteFact(std.testing.allocator, io, path, "bad key", 4));
}

test "file memory rejects invalid retention limits before storage access" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/memory.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const facts_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/facts.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(facts_path);

    try std.testing.expectError(error.InvalidMemoryLimit, load(std.testing.allocator, io, path, memory.min_max_messages - 1));
    try std.testing.expectError(error.InvalidMemoryLimit, append(std.testing.allocator, io, path, "hello", "world", memory.min_max_messages - 1));
    try std.testing.expectError(error.InvalidMemoryLimit, loadFacts(std.testing.allocator, io, facts_path, memory.min_max_facts - 1));
    try std.testing.expectError(error.InvalidMemoryLimit, putFact(std.testing.allocator, io, facts_path, "name", "nllclw", memory.min_max_facts - 1));
    try std.testing.expectError(error.InvalidMemoryLimit, getFact(std.testing.allocator, io, facts_path, "name", memory.max_max_facts + 1));
    try std.testing.expectError(error.InvalidMemoryLimit, deleteFact(std.testing.allocator, io, facts_path, "name", memory.max_max_facts + 1));
}
