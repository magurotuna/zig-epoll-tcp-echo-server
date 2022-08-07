const std = @import("std");
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target_linux = try CrossTarget.parse(.{ .arch_os_abi = "aarch64-linux-gnu" });
    const target_mac = try CrossTarget.parse(.{ .arch_os_abi = "aarch64-macos-none" });
    const target_local = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const linux_exe = b.addExecutable("myecho-linux", "src/main.zig");
    linux_exe.setTarget(target_linux);
    linux_exe.setBuildMode(mode);
    linux_exe.linkLibC();
    linux_exe.install();

    const mac_exe = b.addExecutable("myecho-mac", "src/main.zig");
    mac_exe.setTarget(target_mac);
    mac_exe.setBuildMode(mode);
    mac_exe.linkLibC();
    mac_exe.install();

    const local_exe = b.addExecutable("myecho", "src/main.zig");
    local_exe.setTarget(target_local);
    local_exe.setBuildMode(mode);
    local_exe.linkLibC();
    local_exe.install();

    const linux_step = b.step("linux", "Build for aarch64 linux");
    linux_step.dependOn(&linux_exe.step);

    const mac_step = b.step("mac", "Build for aarch64 mac");
    mac_step.dependOn(&mac_exe.step);

    const local_step = b.step("local", "Build for local machine");
    local_step.dependOn(&local_exe.step);

    const run = local_exe.run();
    if (b.args) |args| {
        run.addArgs(args);
    }
    const run_step = b.step("run", "Run locally");
    run_step.dependOn(&run.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target_local);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
