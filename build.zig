const std = @import("std");

pub fn build(b: *std.Build) void {
    // The msvc ABI yields a noticeably smaller binary than Zig's default gnu
    // ABI for Windows (~60 KiB less); -Dtarget can still override it.
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .msvc,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "scratchpad4k",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // GUI application: no console window attached.
    exe.subsystem = .windows;

    const mod = exe.root_module;
    mod.linkSystemLibrary("user32", .{});
    mod.linkSystemLibrary("gdi32", .{});
    mod.linkSystemLibrary("comdlg32", .{});
    mod.linkSystemLibrary("shcore", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_window.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
