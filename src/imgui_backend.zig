const imgui = @import("imgui");

pub fn init() !void {
    _ = imgui.GetIO();
}

pub fn newFrame() !void {}

pub fn render() !void {}

pub fn deinit() !void {}
