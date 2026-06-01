const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{ MissingHome, InvalidAppPathRoot };

pub fn configDir(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    if (try envRoot(env_map, "XDG_CONFIG_HOME")) |root| return join(allocator, &.{ root, "nllclw" });
    if (builtin.os.tag == .windows) {
        if (try envRoot(env_map, "APPDATA")) |root| return join(allocator, &.{ root, "nllclw" });
    }
    const home = try envRoot(env_map, "HOME") orelse return error.MissingHome;
    return join(allocator, &.{ home, ".config", "nllclw" });
}

pub fn stateDir(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    if (try envRoot(env_map, "XDG_STATE_HOME")) |root| return join(allocator, &.{ root, "nllclw" });
    if (builtin.os.tag == .windows) {
        if (try envRoot(env_map, "LOCALAPPDATA")) |root| return join(allocator, &.{ root, "nllclw" });
    }
    const home = try envRoot(env_map, "HOME") orelse return error.MissingHome;
    return join(allocator, &.{ home, ".local", "state", "nllclw" });
}

pub fn configJsonPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    const dir = try configDir(allocator, env_map);
    defer allocator.free(dir);
    return pathInDir(allocator, dir, "config.json");
}

pub fn dotenvPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    const dir = try configDir(allocator, env_map);
    defer allocator.free(dir);
    return pathInDir(allocator, dir, ".env");
}

pub fn memoryPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "memory.jsonl");
}

pub fn factsPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "facts.jsonl");
}

pub fn userToolsPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "user-tools.jsonl");
}

pub fn schedulePath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "schedule.jsonl");
}

pub fn telegramOffsetPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "telegram-offset");
}

pub fn telegramPollerPath(allocator: Allocator, env_map: *const std.process.Environ.Map) Error![]u8 {
    return statePath(allocator, env_map, "telegram-poller");
}

pub fn statePath(allocator: Allocator, env_map: *const std.process.Environ.Map, filename: []const u8) Error![]u8 {
    const dir = try stateDir(allocator, env_map);
    defer allocator.free(dir);
    return pathInDir(allocator, dir, filename);
}

pub fn pathInDir(allocator: Allocator, dir: []const u8, filename: []const u8) Allocator.Error![]u8 {
    return join(allocator, &.{ dir, filename });
}

fn join(allocator: Allocator, parts: []const []const u8) Allocator.Error![]u8 {
    return std.fs.path.join(allocator, parts);
}

fn envValue(env_map: *const std.process.Environ.Map, key: []const u8) ?[]const u8 {
    const raw = env_map.get(key) orelse return null;
    return if (raw.len == 0) null else raw;
}

fn envRoot(env_map: *const std.process.Environ.Map, key: []const u8) error{InvalidAppPathRoot}!?[]const u8 {
    const raw = envValue(env_map, key) orelse return null;
    if (!std.fs.path.isAbsolute(raw)) return error.InvalidAppPathRoot;
    return raw;
}

test "app paths use xdg config and state roots" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_CONFIG_HOME", "/tmp/config-root");
    try map.put("XDG_STATE_HOME", "/tmp/state-root");
    try map.put("HOME", "/tmp/home");

    const config_path = try configJsonPath(std.testing.allocator, &map);
    defer std.testing.allocator.free(config_path);
    try expectJoinedPath(&.{ "/tmp/config-root", "nllclw", "config.json" }, config_path);

    const memory_path = try memoryPath(std.testing.allocator, &map);
    defer std.testing.allocator.free(memory_path);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "memory.jsonl" }, memory_path);

    const telegram_poller_path = try telegramPollerPath(std.testing.allocator, &map);
    defer std.testing.allocator.free(telegram_poller_path);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "telegram-poller" }, telegram_poller_path);
}

test "app paths fall back to home without using cwd" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("HOME", "/tmp/home");

    const config_path = try configJsonPath(std.testing.allocator, &map);
    defer std.testing.allocator.free(config_path);
    try expectJoinedPath(&.{ "/tmp/home", ".config", "nllclw", "config.json" }, config_path);

    const schedule_path = try schedulePath(std.testing.allocator, &map);
    defer std.testing.allocator.free(schedule_path);
    try expectJoinedPath(&.{ "/tmp/home", ".local", "state", "nllclw", "schedule.jsonl" }, schedule_path);
}

test "app paths reject relative roots" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_CONFIG_HOME", "relative-config");

    try std.testing.expectError(error.InvalidAppPathRoot, configJsonPath(std.testing.allocator, &map));
}

fn expectJoinedPath(parts: []const []const u8, actual: []const u8) !void {
    const expected = try std.fs.path.join(std.testing.allocator, parts);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}
