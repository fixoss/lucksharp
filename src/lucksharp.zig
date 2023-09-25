const glfw = @import("mach-glfw");
const std = @import("std");
const vk = @import("vulkan");

fn glfw_error_callback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

const lucksharpError = error{ GlfwInitFailed, GlfwWindowCreateFailed };

pub const lucksharpApp = struct {
    const Self = @This();

    window: ?glfw.Window = null,

    pub fn init() !Self {
        var self = Self{};
        try self.init_glfw();
        return self;
    }

    pub fn deinit(self: *Self) void {
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
            return lucksharpError.GlfwInitFailed;
        }

        self.window = glfw.Window.create(640, 480, "lucksharp", null, null, .{
            .client_api = .no_api,
            .resizable = false,
        });

        if (self.window == null) {
            return lucksharpError.GlfwWindowCreateFailed;
        }
    }

    fn init_renderer(_: *Self) !void {}

    fn mainloop(self: *Self) !void {
        while (!self.window.?.shouldClose()) {
            glfw.pollEvents();
        }
    }
};
