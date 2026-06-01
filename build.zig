const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shell_tool = b.option(
        bool,
        "shell-tool",
        "Build the optional shell_exec tool adapter. Default false keeps runtime zero-dependency.",
    ) orelse false;
    const size_tuned = b.option(
        bool,
        "size-tuned",
        "Apply conservative size-oriented executable link options",
    ) orelse (optimize == .ReleaseSmall);
    const version = b.option(
        []const u8,
        "version",
        "Build version string used by release automation.",
    ) orelse "dev";

    const options = b.addOptions();
    options.addOption(bool, "shell_tool", shell_tool);
    options.addOption([]const u8, "version", version);

    const mod = b.addModule("nllclw", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = size_tuned,
        .imports = &.{
            .{ .name = "nllclw", .module = mod },
        },
    });
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "nllclw",
        .root_module = exe_mod,
    });
    if (size_tuned) {
        exe.link_function_sections = true;
        exe.link_data_sections = true;
        exe.link_gc_sections = true;
        exe.dead_strip_dylibs = true;
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run nllclw");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const all_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/all_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    all_tests_mod.addOptions("build_options", options);
    const all_tests = b.addTest(.{
        .root_module = all_tests_mod,
    });
    const run_all_tests = b.addRunArtifact(all_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_all_tests.step);
}
