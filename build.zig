const std = @import("std");
const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "lucksharp",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // add mach-glfw dependency
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = exe.target,
        .optimize = exe.optimize,
    });
    exe.addModule("glfw", glfw_dep.module("mach-glfw"));
    @import("mach_glfw").link(glfw_dep.builder, exe);

    // add vulkan-zig dependency
    const vulkan_gen = vkgen.VkGenerateStep.create(b, "/usr/share/vulkan/registry/vk.xml");
    exe.addModule("vulkan", vulkan_gen.getModule());

    // register shader resources
    const shader_compiler = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
        "-o",
    );
    shader_compiler.add("shader_frag", "resources/shaders/example.frag", .{});
    shader_compiler.add("shader_vert", "resources/shaders/example.vert", .{});
    exe.addModule("shaders", shader_compiler.getModule());

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addModule("glfw", glfw_dep.module("mach-glfw"));
    unit_tests.addModule("vulkan", vulkan_gen.getModule());

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
