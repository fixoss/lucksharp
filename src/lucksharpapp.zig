const glfw = @import("mach-glfw");
const std = @import("std");
const renderer_vk = @import("renderer_vulkan.zig");

fn glfw_error_callback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

const Error = error{ GlfwInitFailed, GlfwWindowCreateFailed };

const Self = @This();

window: ?glfw.Window = null,
renderer: ?renderer_vk = null,

pub fn init() !Self {
    var self = Self{};
    try self.init_glfw();
    try self.init_renderer();
    return self;
}

pub fn deinit(self: *Self) void {
    if (self.renderer != null) {
        self.renderer.?.destroyInstance();
    }

    if (self.window != null) {
        self.window.?.destroy();
    }
    glfw.terminate();
}

pub fn run(self: *Self) !void {
    try self.mainloop();
}

fn init_glfw(self: *Self) !void {
    glfw.setErrorCallback(glfw_error_callback);

    if (!glfw.init(.{})) {
        return Error.GlfwInitFailed;
    }

    self.window = glfw.Window.create(640, 480, "lucksharp", null, null, .{
        .client_api = .no_api,
        .resizable = false,
    });

    if (self.window == null) {
        return Error.GlfwWindowCreateFailed;
    }
}

fn init_renderer(self: *Self) !void {
    self.renderer = try renderer_vk.createInstance(@ptrCast(&glfw.getInstanceProcAddress), glfw.getRequiredInstanceExtensions());
}

fn mainloop(self: *Self) !void {
    while (!self.window.?.shouldClose()) {
        glfw.pollEvents();
    }
}
