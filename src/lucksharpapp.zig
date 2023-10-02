const glfw = @import("glfw");
const std = @import("std");
const renderer_vk = @import("renderer_vulkan.zig");

const Allocator = std.mem.Allocator;
const Self = @This();

allocator: Allocator,
window: ?glfw.Window = null,
renderer: ?renderer_vk = null,

pub fn init(allocator: Allocator) !Self {
    var self = Self{ .allocator = allocator };
    try self.initGlfw();
    try self.initRenderer();
    return self;
}

pub fn deinit(self: *Self) void {
    if (self.renderer != null) {
        self.renderer.?.destroyInstance(self.allocator);
    }

    if (self.window != null) {
        self.window.?.destroy();
    }
    glfw.terminate();
}

pub fn run(self: *Self) !void {
    while (!self.window.?.shouldClose()) {
        glfw.pollEvents();
    }
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
    self.renderer = try renderer_vk.createInstance(self.allocator, self.window);
}

fn glfwErrorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}
