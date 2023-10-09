const glfw = @import("glfw");
const imgui_backend = @import("imgui_backend.zig");
const renderer_vk = @import("renderer_vulkan.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Self = @This();

allocator: Allocator,
window: ?glfw.Window = null,
renderer: ?renderer_vk = null,

pub fn init(allocator: Allocator) !Self {
    var self = Self{ .allocator = allocator };
    try self.initGlfw();
    try self.initRenderer();
    try imgui_backend.init();
    return self;
}

pub fn run(self: *Self) !void {
    while (!self.window.?.shouldClose()) {
        glfw.pollEvents();
        try self.renderer.?.renderFrame();
    }
    try self.renderer.?.waitForIdle();
}

pub fn deinit(self: *Self) void {
    if (self.renderer != null) {
        self.renderer.?.deinit(self.allocator);
    }

    if (self.window != null) {
        self.window.?.destroy();
    }
    glfw.terminate();
}

fn initGlfw(self: *Self) !void {
    glfw.setErrorCallback(glfwErrorCallback);

    if (!glfw.init(.{})) {
        return error.GlfwInitFailed;
    }

    self.window = glfw.Window.create(640, 480, "lucksharp", null, null, .{
        .client_api = .no_api,
        .resizable = false,
    });

    if (self.window == null) {
        return error.GlfwWindowCreateFailed;
    }
}

fn initRenderer(self: *Self) !void {
    self.renderer = try renderer_vk.init(self.allocator, self.window);
}

fn glfwErrorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}
