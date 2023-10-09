const vkgen = @import("vulkan_zig");

const Build = @import("std").Build;
const Compile = Build.Step.Compile;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "lucksharp",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    addGlfw(b, exe);
    addImgui(b, exe);
    addVulkan(b, exe);
    addShaders(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addGlfw(b: *Build, exe: *Compile) void {
    // add mach-glfw dependency
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = exe.target,
        .optimize = exe.optimize,
    });
    exe.addModule("glfw", glfw_dep.module("mach-glfw"));
    @import("mach_glfw").link(glfw_dep.builder, exe);
}

fn addImgui(b: *Build, exe: *Compile) void {
    const imgui_dep = b.dependency("imgui_zig", .{
        .target = exe.target,
        .optimize = exe.optimize,
        .enable_freetype = true,
        .enable_lunasvg = false,
    });

    var cimgui_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = exe.target,
        .optimize = exe.optimize,
    });

    cimgui_lib.linkLibCpp();

    // TODO: Is there a better way to get the package source paths?
    const cimgui_src_path = imgui_dep.builder.pathFromRoot(b.pathJoin(&[_][]const u8{
        "zig-imgui",
        "vendor",
        "cimgui",
        "cimgui_unity.cpp",
    }));

    cimgui_lib.addCSourceFile(.{
        .file = .{ .path = cimgui_src_path },
        .flags = &[_][]const u8{
            "-std=c++11",
            "-fno-sanitize=undefined",
            "-ffunction-sections",
            "-fvisibility=hidden",
        },
    });

    b.installArtifact(cimgui_lib);
    exe.linkLibrary(cimgui_lib);
    exe.addModule("imgui", imgui_dep.module("Zig-ImGui"));
}

fn addVulkan(b: *Build, exe: *Compile) void {
    const vulkan_gen = vkgen.VkGenerateStep.create(b, "/usr/share/vulkan/registry/vk.xml");
    exe.addModule("vulkan", vulkan_gen.getModule());
}

fn addShaders(b: *Build, exe: *Compile) void {
    // register shader resources
    const shader_compiler = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
        "-o",
    );
    shader_compiler.add("shader_frag", "resources/shaders/example.frag", .{});
    shader_compiler.add("shader_vert", "resources/shaders/example.vert", .{});
    exe.addModule("shaders", shader_compiler.getModule());
}
