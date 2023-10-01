const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const Allocator = std.mem.Allocator;

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const enable_validation_layers: bool = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

const Self = @This();

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceLayerProperties = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .createDebugUtilsMessengerEXT = enable_validation_layers,
    .createDevice = true,
    .destroyDebugUtilsMessengerEXT = enable_validation_layers,
    .destroyInstance = true,
    .enumeratePhysicalDevices = true,
    .getDeviceProcAddr = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
});

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,

    fn isComplete(self: *const QueueFamilyIndices) bool {
        return self.graphics_family != null;
    }
};

vkb: BaseDispatch = undefined,
vki: InstanceDispatch = undefined,
vkd: DeviceDispatch = undefined,
instance: vk.Instance = .null_handle,
debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
physical_device: vk.PhysicalDevice = .null_handle,
device: vk.Device = .null_handle,
graphics_queue: vk.Queue = .null_handle,

pub fn createInstance(allocator: Allocator) !Self {
    var self = Self{};

    // TODO reduce direct dependency on glfw here? pass the function pointers around?
    const vk_proc = @as(*const fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, @ptrCast(&glfw.getInstanceProcAddress));
    self.vkb = try BaseDispatch.load(vk_proc);

    const app_info = vk.ApplicationInfo{
        .p_application_name = "Hello Triangle",
        .application_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0),
        .api_version = vk.API_VERSION_1_2,
    };

    const extensions = try getRequiredExtensions(allocator);
    defer extensions.deinit();

    const create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = @as(u32, @intCast(extensions.items.len)),
        .pp_enabled_extension_names = extensions.items.ptr,
    };

    self.instance = try self.vkb.createInstance(&create_info, null);

    self.vki = try InstanceDispatch.load(self.instance, vk_proc);

    try self.setupDebugMessenger();
    try self.createPhysicalDevice(allocator);
    try self.createLogicalDevice(allocator);

    return self;
}

pub fn destroyInstance(self: *Self) void {
    if (self.device != .null_handle) {
        self.vkd.destroyDevice(self.device, null);
    }

    if (enable_validation_layers and self.debug_messenger != .null_handle) {
        self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }

    if (self.instance != .null_handle) {
        self.vki.destroyInstance(self.instance, null);
    }
}

fn getRequiredExtensions(allocator: Allocator) !std.ArrayListAligned([*:0]const u8, null) {
    var extensions = std.ArrayList([*:0]const u8).init(allocator);
    try extensions.appendSlice(@as([]const [*:0]const u8, glfw.getRequiredInstanceExtensions().?));

    if (enable_validation_layers) {
        try extensions.append(vk.extension_info.ext_debug_utils.name);
    }

    return extensions;
}

fn checkValidationLayerSupport(self: *Self) !bool {
    var layer_count: u32 = undefined;
    _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, null);

    var available_layers = try self.allocator.alloc(vk.LayerProperties, layer_count);
    defer self.allocator.free(available_layers);
    _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, available_layers.ptr);

    for (validation_layers) |layer_name| {
        var layer_found: bool = false;

        for (available_layers) |layer_properties| {
            const available_len = std.mem.indexOfScalar(u8, &layer_properties.layer_name, 0).?;
            const available_layer_name = layer_properties.layer_name[0..available_len];
            if (std.mem.eql(u8, std.mem.span(layer_name), available_layer_name)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    return true;
}

fn setupDebugMessenger(self: *Self) !void {
    if (!enable_validation_layers) {
        return;
    }

    var create_info: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
    populateDebugMessengerCreateInfo(&create_info);

    self.debug_messenger = try self.vki.createDebugUtilsMessengerEXT(self.instance, &create_info, null);
}

fn populateDebugMessengerCreateInfo(create_info: *vk.DebugUtilsMessengerCreateInfoEXT) void {
    create_info.* = .{
        .flags = .{},
        .message_severity = .{
            .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugCallback,
        .p_user_data = null,
    };
}

fn debugCallback(_: vk.DebugUtilsMessageSeverityFlagsEXT, _: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
    if (p_callback_data != null) {
        std.log.debug("VK Validation Layer: {s}", .{p_callback_data.?.p_message});
    }

    return vk.FALSE;
}

fn createPhysicalDevice(self: *Self, allocator: Allocator) !void {
    var device_count: u32 = undefined;
    _ = try self.vki.enumeratePhysicalDevices(self.instance, &device_count, null);

    if (device_count == 0) {
        return error.NoGPUsSupportVulkan;
    }

    const devices = try allocator.alloc(vk.PhysicalDevice, device_count);
    defer allocator.free(devices);
    _ = try self.vki.enumeratePhysicalDevices(self.instance, &device_count, devices.ptr);

    for (devices) |device| {
        if (try self.isDeviceSuitable(device, allocator)) {
            self.physical_device = device;
            break;
        }
    }

    if (self.physical_device == .null_handle) {
        return error.NoSuitableDevice;
    }
}

fn createLogicalDevice(self: *Self, allocator: Allocator) !void {
    const indices = try self.findQueueFamilies(self.physical_device, allocator);
    const queue_priority = [_]f32{1};

    var queue_create_info = [_]vk.DeviceQueueCreateInfo{.{
        .flags = .{},
        .queue_family_index = indices.graphics_family.?,
        .queue_count = 1,
        .p_queue_priorities = &queue_priority,
    }};

    var create_info = vk.DeviceCreateInfo{
        .flags = .{},
        .queue_create_info_count = queue_create_info.len,
        .p_queue_create_infos = &queue_create_info,
        .enabled_extension_count = 0,
        .pp_enabled_extension_names = undefined,
        .p_enabled_features = null,
    };

    self.device = try self.vki.createDevice(self.physical_device, &create_info, null);
    self.vkd = try DeviceDispatch.load(self.device, self.vki.dispatch.vkGetDeviceProcAddr);
    self.graphics_queue = self.vkd.getDeviceQueue(self.device, indices.graphics_family.?, 0);
}

fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !bool {
    const indices = try self.findQueueFamilies(device, allocator);
    return indices.isComplete();
}

fn findQueueFamilies(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};
    var queue_family_count: u32 = 0;
    self.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);

    self.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |queue_family, i| {
        if (queue_family.queue_flags.graphics_bit) {
            indices.graphics_family = @as(u32, @intCast(i));
        }
        if (indices.isComplete()) {
            break;
        }
    }
    return indices;
}
