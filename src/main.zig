const std = @import("std");
const lucksharpapp = @import("lucksharpapp.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("MemLeak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app = try lucksharpapp.init(allocator);
    defer app.deinit();
    app.run() catch |err| {
        std.log.err("application exited with error: {any}", .{err});
        return;
    };
}
