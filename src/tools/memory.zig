const std = @import("std");
const chat = @import("../chat.zig");
const memory = @import("../memory.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;

const key_parameter = chat.ToolParameter{
    .name = "key",
    .kind = .string,
    .description = "Stable memory key using letters, digits, underscore, dash, or dot.",
};

const value_parameter = chat.ToolParameter{
    .name = "value",
    .kind = .string,
    .description = "Memory value to store.",
};

const key_value_parameters = [_]chat.ToolParameter{ key_parameter, value_parameter };
const key_parameters = [_]chat.ToolParameter{key_parameter};

pub const store_definition: chat.ToolDefinition = .{
    .name = "memory_store",
    .description = "Store or update a durable user memory by key.",
    .parameters = .{
        .properties = &key_value_parameters,
        .required = &.{ "key", "value" },
    },
};

pub const recall_definition: chat.ToolDefinition = .{
    .name = "memory_recall",
    .description = "Recall a durable user memory by key.",
    .parameters = .{
        .properties = &key_parameters,
        .required = &.{"key"},
    },
};

pub const list_definition: chat.ToolDefinition = .{
    .name = "memory_list",
    .description = "List durable user memory keys.",
    .parameters = .{
        .properties = &.{},
    },
};

pub const forget_definition: chat.ToolDefinition = .{
    .name = "memory_forget",
    .description = "Delete a durable user memory by key.",
    .parameters = .{
        .properties = &key_parameters,
        .required = &.{"key"},
    },
};

pub const Client = struct {
    store: memory.FactStore,
    max_facts: usize,
    output_max_bytes: usize,

    pub fn init(store: memory.FactStore, max_facts: usize, output_max_bytes: usize) Client {
        return .{
            .store = store,
            .max_facts = max_facts,
            .output_max_bytes = output_max_bytes,
        };
    }

    pub fn storeHandler(self: *Client) tool.Handler {
        return .{ .definition = store_definition, .ptr = self, .run_fn = runStore, .mutates_state = true };
    }

    pub fn recallHandler(self: *Client) tool.Handler {
        return .{ .definition = recall_definition, .ptr = self, .run_fn = runRecall };
    }

    pub fn listHandler(self: *Client) tool.Handler {
        return .{ .definition = list_definition, .ptr = self, .run_fn = runList };
    }

    pub fn forgetHandler(self: *Client) tool.Handler {
        return .{ .definition = forget_definition, .ptr = self, .run_fn = runForget, .mutates_state = true };
    }

    fn runStore(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var args = try parseKeyValue(allocator, call.arguments);
        defer args.deinit(allocator);

        try ensureKeyResultFits("saved: ", args.key, self.output_max_bytes);
        try ensureFactResultFits(args.key, args.value, self.output_max_bytes);
        self.store.put(allocator, args.key, args.value, self.max_facts) catch |err| return mapStoreError(err);
        return keyResult(allocator, "saved: ", args.key, self.output_max_bytes);
    }

    fn runRecall(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const key = try parseKey(allocator, call.arguments);
        defer allocator.free(key);

        const value = self.store.get(allocator, key, self.max_facts) catch |err| return mapStoreError(err);
        defer if (value) |bytes| allocator.free(bytes);

        if (value) |bytes| {
            return factResult(allocator, key, bytes, self.output_max_bytes);
        }
        return keyResult(allocator, "not found: ", key, self.output_max_bytes);
    }

    fn runList(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        try parseEmptyObject(allocator, call.arguments);

        var facts = self.store.list(allocator, self.max_facts) catch |err| return mapStoreError(err);
        defer facts.deinit(allocator);

        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        appendLimited(&out, "memories:\n", self.output_max_bytes) catch |err| return mapWriteError(err);
        for (facts.entries) |fact| {
            appendLimited(&out, "- ", self.output_max_bytes) catch |err| return mapWriteError(err);
            appendLimited(&out, fact.key, self.output_max_bytes) catch |err| return mapWriteError(err);
            appendLimited(&out, "\n", self.output_max_bytes) catch |err| return mapWriteError(err);
        }
        return out.toOwnedSlice() catch error.OutOfMemory;
    }

    fn runForget(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const key = try parseKey(allocator, call.arguments);
        defer allocator.free(key);

        try ensureKeyResultFits("not found: ", key, self.output_max_bytes);
        const deleted = self.store.delete(allocator, key, self.max_facts) catch |err| return mapStoreError(err);
        if (deleted) return keyResult(allocator, "deleted: ", key, self.output_max_bytes);
        return keyResult(allocator, "not found: ", key, self.output_max_bytes);
    }
};

const KeyArgs = struct {
    key: []const u8 = "",
};

const KeyValueArgs = struct {
    key: []const u8 = "",
    value: []const u8 = "",
};

const EmptyArgs = struct {};

const KeyValueArgsOwned = struct {
    key: []u8,
    value: []u8,

    fn deinit(self: *KeyValueArgsOwned, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
        self.* = undefined;
    }
};

fn parseKey(allocator: Allocator, arguments: []const u8) tool.RunError![]u8 {
    const parsed = try tool.parseArgs(KeyArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const key = std.mem.trim(u8, parsed.value.key, &std.ascii.whitespace);
    if (!memory.isValidFactKey(key)) return error.InvalidToolArguments;
    return try allocator.dupe(u8, key);
}

fn parseKeyValue(allocator: Allocator, arguments: []const u8) tool.RunError!KeyValueArgsOwned {
    const parsed = try tool.parseArgs(KeyValueArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const key = std.mem.trim(u8, parsed.value.key, &std.ascii.whitespace);
    if (!memory.isValidFactKey(key)) return error.InvalidToolArguments;
    if (!memory.isValidFactValue(parsed.value.value)) return error.InvalidToolArguments;

    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);
    const owned_value = try allocator.dupe(u8, parsed.value.value);
    return .{
        .key = owned_key,
        .value = owned_value,
    };
}

fn parseEmptyObject(allocator: Allocator, arguments: []const u8) tool.RunError!void {
    const parsed = try tool.parseArgs(EmptyArgs, allocator, arguments, .{});
    parsed.deinit();
}

fn mapStoreError(err: memory.StoreError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.ToolOutputTooLarge,
        error.InvalidMemoryKey,
        error.InvalidMemoryLimit,
        error.InvalidMemoryLine,
        error.InvalidMemoryRole,
        error.StorageFailed,
        => error.ToolFailed,
    };
}

fn appendLimited(out: *std.Io.Writer.Allocating, bytes: []const u8, limit: usize) (Allocator.Error || error{ToolOutputTooLarge})!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

const LimitedWriteError = Allocator.Error || error{ToolOutputTooLarge};

fn keyResult(allocator: Allocator, prefix: []const u8, key: []const u8, limit: usize) tool.RunError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    appendLimited(&out, prefix, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, key, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, "\n", limit) catch |err| return mapWriteError(err);
    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn factResult(allocator: Allocator, key: []const u8, value: []const u8, limit: usize) tool.RunError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    appendLimited(&out, key, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, ": ", limit) catch |err| return mapWriteError(err);
    appendLimited(&out, value, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, "\n", limit) catch |err| return mapWriteError(err);
    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn ensureKeyResultFits(prefix: []const u8, key: []const u8, limit: usize) error{ToolOutputTooLarge}!void {
    var len = std.math.add(usize, prefix.len, key.len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, 1) catch return error.ToolOutputTooLarge;
    if (len > limit) return error.ToolOutputTooLarge;
}

fn ensureFactResultFits(key: []const u8, value: []const u8, limit: usize) error{ToolOutputTooLarge}!void {
    var len = std.math.add(usize, key.len, ": ".len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, value.len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, 1) catch return error.ToolOutputTooLarge;
    if (len > limit) return error.ToolOutputTooLarge;
}

fn mapWriteError(err: LimitedWriteError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
    };
}

const FakeStore = struct {
    key: ?[]u8 = null,
    value: ?[]u8 = null,

    fn deinit(self: *FakeStore, allocator: Allocator) void {
        if (self.key) |key| allocator.free(key);
        if (self.value) |value| allocator.free(value);
        self.* = undefined;
    }

    fn port(self: *FakeStore) memory.FactStore {
        return .{
            .ptr = self,
            .put_fn = put,
            .get_fn = get,
            .list_fn = list,
            .delete_fn = delete,
        };
    }

    fn put(ptr: *anyopaque, allocator: Allocator, key: []const u8, value: []const u8, _: usize) memory.StoreError!void {
        const self: *FakeStore = @ptrCast(@alignCast(ptr));
        const next_key = try allocator.dupe(u8, key);
        errdefer allocator.free(next_key);
        const next_value = try allocator.dupe(u8, value);
        errdefer allocator.free(next_value);

        if (self.key) |old| allocator.free(old);
        if (self.value) |old| allocator.free(old);
        self.key = next_key;
        self.value = next_value;
    }

    fn get(ptr: *anyopaque, allocator: Allocator, key: []const u8, _: usize) memory.StoreError!?[]u8 {
        const self: *FakeStore = @ptrCast(@alignCast(ptr));
        if (self.key) |stored_key| {
            if (std.mem.eql(u8, stored_key, key)) return try allocator.dupe(u8, self.value.?);
        }
        return null;
    }

    fn list(ptr: *anyopaque, allocator: Allocator, _: usize) memory.StoreError!memory.Facts {
        const self: *FakeStore = @ptrCast(@alignCast(ptr));
        if (self.key == null) return .{};
        const entries = try allocator.alloc(memory.Fact, 1);
        errdefer allocator.free(entries);
        const key = try allocator.dupe(u8, self.key.?);
        errdefer allocator.free(key);
        const value = try allocator.dupe(u8, self.value.?);
        errdefer allocator.free(value);
        entries[0] = .{
            .key = key,
            .value = value,
        };
        return .{ .entries = entries };
    }

    fn delete(ptr: *anyopaque, allocator: Allocator, key: []const u8, _: usize) memory.StoreError!bool {
        const self: *FakeStore = @ptrCast(@alignCast(ptr));
        if (self.key) |stored_key| {
            if (std.mem.eql(u8, stored_key, key)) {
                allocator.free(stored_key);
                allocator.free(self.value.?);
                self.key = null;
                self.value = null;
                return true;
            }
        }
        return false;
    }
};

test "memory tool handlers store recall list and forget facts" {
    var fake: FakeStore = .{};
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.port(), 16, 4096);

    const stored = try client.storeHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "memory_store",
        .arguments = "{\"key\":\"project\",\"value\":\"nllclw\"}",
    });
    defer std.testing.allocator.free(stored);
    try std.testing.expectEqualStrings("saved: project\n", stored);

    const recalled = try client.recallHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "memory_recall",
        .arguments = "{\"key\":\"project\"}",
    });
    defer std.testing.allocator.free(recalled);
    try std.testing.expectEqualStrings("project: nllclw\n", recalled);

    const listed = try client.listHandler().run(std.testing.allocator, .{
        .id = "call_3",
        .name = "memory_list",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "- project\n") != null);

    const forgotten = try client.forgetHandler().run(std.testing.allocator, .{
        .id = "call_4",
        .name = "memory_forget",
        .arguments = "{\"key\":\"project\"}",
    });
    defer std.testing.allocator.free(forgotten);
    try std.testing.expectEqualStrings("deleted: project\n", forgotten);
}

test "memory tool enforces recall output cap before storing" {
    var fake: FakeStore = .{};
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.port(), 16, "project: nllclw".len);

    try std.testing.expectError(error.ToolOutputTooLarge, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "memory_store",
        .arguments = "{\"key\":\"project\",\"value\":\"nllclw\"}",
    }));
    try std.testing.expect(fake.key == null);

    try fake.port().put(std.testing.allocator, "project", "nllclw", 16);
    try std.testing.expectError(error.ToolOutputTooLarge, client.recallHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "memory_recall",
        .arguments = "{\"key\":\"project\"}",
    }));
}

test "memory tool rejects unsafe keys and empty values" {
    var fake: FakeStore = .{};
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.port(), 16, 4096);

    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "memory_store",
        .arguments = "{\"key\":\"../secret\",\"value\":\"x\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "memory_store",
        .arguments = "{\"key\":\"ok\",\"value\":\"\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_3",
        .name = "memory_store",
        .arguments = "{\"key\":\"ok\",\"value\":\"   \"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_4",
        .name = "memory_store",
        .arguments = "{\"key\":\"ok\",\"value\":\"bad\\u0000value\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_5",
        .name = "memory_store",
        .arguments = "{\"key\":\"ok\",\"value\":\"bad\\u001bvalue\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.listHandler().run(std.testing.allocator, .{
        .id = "call_6",
        .name = "memory_list",
        .arguments = "not-json",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.storeHandler().run(std.testing.allocator, .{
        .id = "call_7",
        .name = "memory_store",
        .arguments = "{\"key\":\"ok\",\"value\":\"value\",\"unknown\":true}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, client.recallHandler().run(std.testing.allocator, .{
        .id = "call_8",
        .name = "memory_recall",
        .arguments = "{\"key\":\"ok\",\"unknown\":true}",
    }));
}
