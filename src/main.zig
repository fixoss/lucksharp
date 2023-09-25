const std = @import("std");
const lucksharpApp = @import("lucksharp.zig").lucksharpApp;

pub fn main() !void {
    var app = try lucksharpApp.init();
    defer app.deinit();
    app.run() catch |err| {
        std.log.err("application exited with error: {any}", .{err});
        return;
    };
}
