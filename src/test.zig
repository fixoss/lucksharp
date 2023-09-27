const std = @import("std");
const lucksharpapp = @import("lucksharpapp.zig");

fn run(app: lucksharpapp) !void {
    try app.run();
}

test "threading" {
    var app = try lucksharpapp.init();
    defer app.deinit();

    var thread = try std.Thread.spawn(.{}, run, .{@as(lucksharpapp, app)});
    _ = thread;

    std.time.sleep(3 * std.time.ns_per_s);
}
