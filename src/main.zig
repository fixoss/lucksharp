const std = @import("std");
const lucksharpapp = @import("lucksharpapp.zig");

pub fn main() !void {
    var app = try lucksharpapp.init();
    defer app.deinit();
    app.run() catch |err| {
        std.log.err("application exited with error: {any}", .{err});
        return;
    };
}
