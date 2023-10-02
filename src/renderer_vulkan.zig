const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const shaders = @import("shaders");

const Allocator = std.mem.Allocator;

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const required_device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};

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
    .destroySurfaceKHR = true,
    .enumerateDeviceExtensionProperties = true,
    .enumeratePhysicalDevices = true,
    .getDeviceProcAddr = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .createImageView = true,
    .createShaderModule = true,
    .createSwapchainKHR = true,
    .destroyDevice = true,
    .destroyImageView = true,
    .destroyShaderModule = true,
    .destroySwapchainKHR = true,
    .getDeviceQueue = true,
    .getSwapchainImagesKHR = true,
});

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    fn isComplete(self: *const QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

const SwapchainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR = undefined,
    formats: ?[]vk.SurfaceFormatKHR = null,
    present_modes: ?[]vk.PresentModeKHR = null,

    pub fn destroy(self: SwapchainSupportDetails, allocator: Allocator) void {
        if (self.formats != null) {
            allocator.free(self.formats.?);
        }
        if (self.present_modes != null) {
            allocator.free(self.present_modes.?);
        }
    }
};

vkb: BaseDispatch = undefined,
vki: InstanceDispatch = undefined,
vkd: DeviceDispatch = undefined,
instance: vk.Instance = .null_handle,
debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
surface: vk.SurfaceKHR = .null_handle,
physical_device: vk.PhysicalDevice = .null_handle,
device: vk.Device = .null_handle,
graphics_queue: vk.Queue = .null_handle,
present_queue: vk.Queue = .null_handle,
swap_chain: vk.SwapchainKHR = .null_handle,
swap_chain_images: ?[]vk.Image = null,
swap_chain_image_format: vk.Format = .undefined,
swap_chain_extent: vk.Extent2D = .{ .width = 0, .height = 0 },
swap_chain_image_views: ?[]vk.ImageView = null,

pub fn createInstance(allocator: Allocator, glfw_window: ?glfw.Window) !Self {
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
    try self.createSurface(glfw_window);
    try self.createPhysicalDevice(allocator);
    try self.createLogicalDevice(allocator);
    try self.createSwapchain(allocator, glfw_window);
    try self.createImageViews(allocator);
    try self.createGraphicsPipeline();

    return self;
}

pub fn destroyInstance(self: *Self, allocator: Allocator) void {
    if (self.swap_chain_image_views != null) {
        for (self.swap_chain_image_views.?) |image_view| {
            self.vkd.destroyImageView(self.device, image_view, null);
        }
        allocator.free(self.swap_chain_image_views.?);
    }

    if (self.swap_chain_images != null) {
        allocator.free(self.swap_chain_images.?);
    }

    if (self.swap_chain != .null_handle) {
        self.vkd.destroySwapchainKHR(self.device, self.swap_chain, null);
    }

    if (self.device != .null_handle) {
        self.vkd.destroyDevice(self.device, null);
    }

    if (enable_validation_layers and self.debug_messenger != .null_handle) {
        self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }

    if (self.surface != .null_handle) {
        self.vki.destroySurfaceKHR(self.instance, self.surface, null);
    }

    if (self.instance != .null_handle) {
        self.vki.destroyInstance(self.instance, null);
    }
}

fn createImageViews(self: *Self, allocator: Allocator) !void {
    self.swap_chain_image_views = try allocator.alloc(vk.ImageView, self.swap_chain_images.?.len);

    for (self.swap_chain_images.?, 0..) |image, i| {
        self.swap_chain_image_views.?[i] = try self.vkd.createImageView(self.device, &.{ .flags = .{}, .image = image, .view_type = .@"2d", .format = self.swap_chain_image_format, .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity }, .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        } }, null);
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

fn createSurface(self: *Self, glfw_window: ?glfw.Window) !void {
    var result = glfw.createWindowSurface(self.instance, glfw_window.?, null, &self.surface);
    if (result != @intFromEnum(vk.Result.success)) {
        return error.SurfaceInitFailed;
    }
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

    var queue_create_info = [_]vk.DeviceQueueCreateInfo{ .{
        .flags = .{},
        .queue_family_index = indices.graphics_family.?,
        .queue_count = 1,
        .p_queue_priorities = &queue_priority,
    }, .{
        .flags = .{},
        .queue_family_index = indices.present_family.?,
        .queue_count = 1,
        .p_queue_priorities = &queue_priority,
    } };

    var create_info = vk.DeviceCreateInfo{
        .flags = .{},
        .queue_create_info_count = queue_create_info.len,
        .p_queue_create_infos = &queue_create_info,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = &required_device_extensions,
        .p_enabled_features = null,
    };

    self.device = try self.vki.createDevice(self.physical_device, &create_info, null);
    self.vkd = try DeviceDispatch.load(self.device, self.vki.dispatch.vkGetDeviceProcAddr);
    self.graphics_queue = self.vkd.getDeviceQueue(self.device, indices.graphics_family.?, 0);
    self.present_queue = self.vkd.getDeviceQueue(self.device, indices.present_family.?, 0);
}

fn createSwapchain(self: *Self, allocator: Allocator, glfw_window: ?glfw.Window) !void {
    const swap_chain_support = try self.querySwapchainSupport(self.physical_device, allocator);
    defer swap_chain_support.destroy(allocator);

    const surface_format: vk.SurfaceFormatKHR = chooseSwapSurfaceFormat(swap_chain_support.formats.?);
    const present_mode: vk.PresentModeKHR = chooseSwapPresentMode(swap_chain_support.present_modes.?);
    const extent: vk.Extent2D = try chooseSwapExtent(glfw_window, swap_chain_support.capabilities);

    var image_count = swap_chain_support.capabilities.min_image_count + 1;
    if (swap_chain_support.capabilities.max_image_count > 0) {
        image_count = @min(image_count, swap_chain_support.capabilities.max_image_count);
    }

    const indices = try self.findQueueFamilies(self.physical_device, allocator);
    const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };
    const sharing_mode: vk.SharingMode = if (indices.graphics_family.? != indices.present_family.?) .concurrent else .exclusive;

    self.swap_chain = try self.vkd.createSwapchainKHR(self.device, &.{
        .flags = .{},
        .surface = self.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = queue_family_indices.len,
        .p_queue_family_indices = &queue_family_indices,
        .pre_transform = swap_chain_support.capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = vk.TRUE,
        .old_swapchain = .null_handle,
    }, null);

    _ = try self.vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null);
    self.swap_chain_images = try allocator.alloc(vk.Image, image_count);
    _ = try self.vkd.getSwapchainImagesKHR(self.device, self.swap_chain, &image_count, self.swap_chain_images.?.ptr);

    self.swap_chain_image_format = surface_format.format;
    self.swap_chain_extent = extent;
}

fn querySwapchainSupport(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !SwapchainSupportDetails {
    var details = SwapchainSupportDetails{};
    details.capabilities = try self.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface);

    var format_count: u32 = undefined;
    _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, null);

    if (format_count != 0) {
        details.formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
        _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, details.formats.?.ptr);
    }

    var present_mode_count: u32 = undefined;
    _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, null);

    if (present_mode_count != 0) {
        details.present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);
        _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, details.present_modes.?.ptr);
    }

    return details;
}

fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !bool {
    const indices = try self.findQueueFamilies(device, allocator);

    const extensions_supported = try self.checkDeviceExtensionSupport(device, allocator);
    var swap_chain_adequate = false;
    if (extensions_supported) {
        const swap_chain_support = try self.querySwapchainSupport(device, allocator);
        defer swap_chain_support.destroy(allocator);

        swap_chain_adequate = swap_chain_support.formats != null and swap_chain_support.present_modes != null;
    }
    return indices.isComplete() and extensions_supported and swap_chain_adequate;
}

fn checkDeviceExtensionSupport(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !bool {
    var extension_count: u32 = undefined;
    _ = try self.vki.enumerateDeviceExtensionProperties(device, null, &extension_count, null);

    var available_extensions = try allocator.alloc(vk.ExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    _ = try self.vki.enumerateDeviceExtensionProperties(device, null, &extension_count, available_extensions.ptr);

    for (required_device_extensions) |required_extension| {
        for (available_extensions) |available_extension| {
            if (std.mem.eql(u8, std.mem.span(required_extension), std.mem.sliceTo(&available_extension.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

fn findQueueFamilies(self: *Self, device: vk.PhysicalDevice, allocator: Allocator) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};

    var queue_family_count: u32 = 0;
    self.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(vk.QueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    self.vki.getPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    for (queue_families, 0..) |queue_family, i| {
        if (indices.graphics_family == null and queue_family.queue_flags.graphics_bit) {
            indices.graphics_family = @as(u32, @intCast(i));
        }

        if (indices.present_family == null) {
            const supports_surface = (try self.vki.getPhysicalDeviceSurfaceSupportKHR(device, @as(u32, @intCast(i)), self.surface) == vk.TRUE);
            if (supports_surface) {
                indices.present_family = @as(u32, @intCast(i));
            }
        }

        if (indices.isComplete()) {
            break;
        }
    }

    return indices;
}

fn createGraphicsPipeline(self: *Self) !void {
    const vert_shader_module: vk.ShaderModule = try self.createShaderModule(&shaders.shader_vert);
    defer self.vkd.destroyShaderModule(self.device, vert_shader_module, null);

    const frag_shader_module: vk.ShaderModule = try self.createShaderModule(&shaders.shader_frag);
    defer self.vkd.destroyShaderModule(self.device, frag_shader_module, null);

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ .{
        .flags = .{},
        .stage = .{ .vertex_bit = true },
        .module = vert_shader_module,
        .p_name = "main",
        .p_specialization_info = null,
    }, .{
        .flags = .{},
        .stage = .{ .fragment_bit = true },
        .module = frag_shader_module,
        .p_name = "main",
        .p_specialization_info = null,
    } };
    std.log.debug("temp hold for compiler error on unused const for shader_stages: {}", .{shader_stages.len});
}

fn createShaderModule(self: *Self, code: []const u8) !vk.ShaderModule {
    return try self.vkd.createShaderModule(self.device, &.{
        .flags = .{},
        .code_size = code.len,
        .p_code = @as([*]const u32, @ptrCast(@alignCast(code))),
    }, null);
}

fn chooseSwapSurfaceFormat(available_formats: []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    for (available_formats) |available_format| {
        if (available_format.format == .b8g8r8a8_srgb and available_format.color_space == .srgb_nonlinear_khr) {
            return available_format;
        }
    }
    return available_formats[0];
}

fn chooseSwapPresentMode(available_present_modes: []vk.PresentModeKHR) vk.PresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == .mailbox_khr) {
            return available_present_mode;
        }
    }
    return .fifo_khr;
}

fn chooseSwapExtent(glfw_window: ?glfw.Window, capabilities: vk.SurfaceCapabilitiesKHR) !vk.Extent2D {
    if (capabilities.current_extent.width != 0xFFFF_FFFF) {
        return capabilities.current_extent;
    } else {
        const window_size = glfw_window.?.getFramebufferSize();

        return vk.Extent2D{
            .width = std.math.clamp(window_size.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
            .height = std.math.clamp(window_size.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
        };
    }
}
