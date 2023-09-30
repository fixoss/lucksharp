const glfw = @import("glfw");
const std = @import("std");

test "testing" {
    std.debug.print("{s}", .{@typeInfo(glfw)});
}
