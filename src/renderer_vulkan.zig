const vk = @import("vulkan");

const Self = @This();

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
});

vkb: BaseDispatch = undefined,
vki: InstanceDispatch = undefined,
instance: vk.Instance = .null_handle,

pub fn createInstance(glfwGetInstanceAddrFunc: *const fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) ?*const fn () callconv(.C) void, glfwExtensions: ?[][*:0]const u8) !Self {
    var self = Self{};

    const vk_proc = @as(*const fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfwGetInstanceAddrFunc);
    self.vkb = try BaseDispatch.load(vk_proc);

    const app_info = vk.ApplicationInfo{
        .p_application_name = "Hello Triangle",
        .application_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0),
        .api_version = vk.API_VERSION_1_2,
    };

    const create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = @as(u32, @intCast(glfwExtensions.?.len)),
        .pp_enabled_extension_names = glfwExtensions.?.ptr,
    };

    self.instance = try self.vkb.createInstance(&create_info, null);

    self.vki = try InstanceDispatch.load(self.instance, vk_proc);

    return self;
}

pub fn destroyInstance(self: *Self) void {
    if (self.instance != .null_handle) {
        self.vki.destroyInstance(self.instance, null);
    }
}
