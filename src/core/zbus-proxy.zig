const std = @import("std");
const zbus = @import("./zbus.zig");

pub const ZBusProxy = struct {
    bus: *zbus.ZBus,
    destination: [:0]const u8,
    path: zbus.Path,
    interface: [:0]const u8,

    pub fn init(bus: *zbus.ZBus, destination: [:0]const u8, path: zbus.Path, interface: [:0]const u8) ZBusProxy {
        return ZBusProxy{
            .bus = bus,
            .destination = destination,
            .path = path,
            .interface = interface,
        };
    }

    pub fn callMethod(self: *ZBusProxy, method: [:0]const u8, types: [:0]const u8, args: anytype) !zbus.Message {
        return try self.bus.callMethod(
            self.destination,
            self.path,
            self.interface,
            method,
            types,
            args,
        );
    }

    pub fn messageNewMethodCall(self: *ZBusProxy, method: [:0]const u8) !zbus.Message {
        return try self.bus.messageNewMethodCall(self.destination, self.path, self.interface, method);
    }

    pub fn getStrProp(self: *ZBusProxy, allocator: std.mem.Allocator, prop: [:0]const u8) ![:0]const u8 {
        var m = try self.bus.getProperty(self.destination, self.path, self.interface, prop, "s");
        defer m.unref();
        var c_str: ?[*:0]const u8 = null;
        _ = try m.read("s", .{&c_str});

        return try allocator.dupeZ(u8, std.mem.sliceTo(c_str.?, 0));
    }

    pub fn getStrArrayProp(self: *ZBusProxy, allocator: std.mem.Allocator, prop: [:0]const u8) !zbus.ParsedMessage([][:0]const u8) {
        var parsed = zbus.ParsedMessage([][:0]const u8){ .arena = std.heap.ArenaAllocator.init(allocator) };
        errdefer parsed.deinit();
        parsed.value = self.getStrArrPropLeaky(prop, parsed.arena.allocator());
        return parsed;
    }

    pub fn getStrArrPropLeaky(self: *ZBusProxy, allocator: std.mem.Allocator, prop: [:0]const u8) ![][:0]const u8 {
        var m = try self.bus.getProperty(self.destination, self.path, self.interface, prop, "as");
        defer m.unref();

        var list = std.ArrayList([:0]const u8).init(allocator);
        try m.enterContainer('a', "s");

        while (true) {
            var c_str: ?[*:0]const u8 = null;
            const was_read = try m.read("s", .{&c_str});
            if (!was_read) break;

            try list.append(allocator.dupeZ(u8, std.mem.sliceTo(c_str.?, 0)));
        }

        try m.exitContainer();
        return try list.toOwnedSlice();
    }
};
