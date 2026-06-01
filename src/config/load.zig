const std = @import("std");
const app_paths = @import("../app_paths.zig");
const build_options = @import("build_options");
const config_json = @import("./json.zig");
const dotenv = @import("../dotenv.zig");
const env = @import("../env.zig");
const resolve = @import("./resolve.zig");
const source = @import("./source.zig");
const types = @import("./types.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_dotenv_bytes = 16 * 1024;
pub const max_config_json_bytes = 16 * 1024;

const LoadedDotenvSource = struct {
    source: source.Source = .{},
    contents: ?[]u8 = null,

    fn deinit(self: *LoadedDotenvSource, allocator: Allocator) void {
        if (self.contents) |contents| allocator.free(contents);
        self.* = undefined;
    }
};

const LoadedJsonSource = struct {
    source: source.Source = .{},
    contents: ?[]u8 = null,
    parsed: ?config_json.ParsedSource = null,

    fn deinit(self: *LoadedJsonSource, allocator: Allocator) void {
        if (self.parsed) |*parsed| parsed.deinit(allocator);
        if (self.contents) |contents| allocator.free(contents);
        self.* = undefined;
    }
};

pub fn ownedFromProcessEnv(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
) !resolve.Owned {
    const features: types.Features = .{ .shell_tool = build_options.shell_tool };
    try env.validateKnownKeys(env_map, features);
    const env_source = env.fromMap(env_map, features);
    var config_source = try loadConfigJsonSource(allocator, io, env_map, features);
    defer config_source.deinit(allocator);
    var dotenv_source = try loadDotenvSource(allocator, io, env_map, features);
    defer dotenv_source.deinit(allocator);
    const file_source = source.Source.overlay(config_source.source, dotenv_source.source);
    return resolve.fromSourcesOwnedWithFeatures(allocator, env_source, file_source, features);
}

fn loadConfigJsonSource(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    comptime features: types.Features,
) !LoadedJsonSource {
    const path = app_paths.configJsonPath(allocator, env_map) catch |err| switch (err) {
        error.MissingHome => return .{},
        else => return err,
    };
    defer allocator.free(path);

    const contents = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_config_json_bytes)) catch |err| return mapConfigJsonReadError(err);
    errdefer allocator.free(contents);

    var parsed = try config_json.parseWithFeatures(allocator, contents, features);
    errdefer parsed.deinit(allocator);
    return .{
        .source = parsed.source,
        .contents = contents,
        .parsed = parsed,
    };
}

fn loadDotenvSource(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    comptime features: types.Features,
) !LoadedDotenvSource {
    const path = app_paths.dotenvPath(allocator, env_map) catch |err| switch (err) {
        error.MissingHome => return .{},
        else => return err,
    };
    defer allocator.free(path);

    const contents = Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_dotenv_bytes)) catch |err| return mapDotenvReadError(err);
    errdefer allocator.free(contents);
    return .{
        .source = try dotenv.parseWithFeatures(contents, features),
        .contents = contents,
    };
}

fn mapConfigJsonReadError(err: anyerror) !LoadedJsonSource {
    return switch (err) {
        error.FileNotFound => .{},
        error.StreamTooLong => error.ConfigJsonFileTooLarge,
        else => err,
    };
}

fn mapDotenvReadError(err: anyerror) !LoadedDotenvSource {
    return switch (err) {
        error.FileNotFound => .{},
        error.StreamTooLong => error.DotenvFileTooLarge,
        else => err,
    };
}

test "missing file config returns empty source when env carries required config" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("NLLCLW_PROVIDER", "openai");
    try map.put("NLLCLW_API_KEY", "key");
    try map.put("NLLCLW_MODEL", "model");
    try map.put("NLLCLW_MEMORY_PATH", ".memory.jsonl");
    try map.put("NLLCLW_MEMORY_FACTS_PATH", ".facts.jsonl");
    try map.put("NLLCLW_USER_TOOLS_PATH", ".tools.jsonl");
    try map.put("NLLCLW_SCHEDULE_PATH", ".schedule.jsonl");

    var owned = try ownedFromProcessEnv(std.testing.allocator, std.testing.io, &map);
    defer owned.deinit(std.testing.allocator);
    try std.testing.expectEqual(.openai, owned.value.completion.provider);
}

test "owned config loads config json from user config directory" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "config", .default_dir);
    try tmp.dir.createDir(io, "config/nllclw", .default_dir);
    try tmp.dir.writeFile(io, .{
        .sub_path = "config/nllclw/config.json",
        .data =
        \\{
        \\  "provider": "openai",
        \\  "api_key": "json-key",
        \\  "model": "json-model"
        \\}
        ,
    });

    const config_root = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/config", .{tmp.sub_path});
    defer std.testing.allocator.free(config_root);
    const cwd = try std.process.currentPathAlloc(io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    const absolute_config_root = try std.fs.path.join(std.testing.allocator, &.{ cwd, config_root });
    defer std.testing.allocator.free(absolute_config_root);

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_CONFIG_HOME", absolute_config_root);

    var owned = try ownedFromProcessEnv(std.testing.allocator, io, &map);
    defer owned.deinit(std.testing.allocator);
    try std.testing.expectEqual(.openai, owned.value.completion.provider);
    try std.testing.expectEqualStrings("json-key", owned.value.completion.api_key);
    try std.testing.expectEqualStrings("json-model", owned.value.completion.model);
}

test "unknown process env keys are rejected before config resolution" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("NLLCLW_PROVIDER", "openai");
    try map.put("NLLCLW_API_KEY", "key");
    try map.put("NLLCLW_MODEL", "model");
    try map.put("NLLCLW_UNKNOWN_KEY", "value");

    try std.testing.expectError(
        error.UnknownKey,
        ownedFromProcessEnv(std.testing.allocator, std.testing.io, &map),
    );
}

test "oversized dotenv has a config-specific error" {
    try std.testing.expectError(error.DotenvFileTooLarge, mapDotenvReadError(error.StreamTooLong));
}

test "oversized config json has a config-specific error" {
    try std.testing.expectError(error.ConfigJsonFileTooLarge, mapConfigJsonReadError(error.StreamTooLong));
}

test "file config priority is config json before dotenv and after OS env" {
    const file_source = source.Source.overlay(
        .{
            .provider = "openrouter",
            .api_key = "config-key",
            .model = "config-model",
        },
        .{
            .provider = "openai",
            .api_key = "dotenv-key",
            .model = "dotenv-model",
        },
    );

    const cfg = try resolve.fromSources(
        .{ .model = "env-model" },
        file_source,
    );

    try std.testing.expectEqual(.openrouter, cfg.completion.provider);
    try std.testing.expectEqualStrings("config-key", cfg.completion.api_key);
    try std.testing.expectEqualStrings("env-model", cfg.completion.model);
}
