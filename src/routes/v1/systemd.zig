const std = @import("std");
const common = @import("../../common.zig");
const errors = @import("./errors.zig");
const httpz = @import("httpz");
const zbus = @import("../../core/zbus.zig");
const systemdbus = @import("../../core/systemd-dbus-interfaces.zig");

const Request = httpz.Request;
const Response = httpz.Response;

// ---------------------------
// -- Data Transfer Objects --
// ---------------------------

const EnableUnitsRequest = struct {
    units: []const [:0]const u8,
    no_reload: bool = false,
    runtime: bool = false,
    force: bool = false,
};

const DisableUnitsRequest = struct {
    units: []const [:0]const u8,
    no_reload: bool = false,
    runtime: bool = false,
};

const KillRequest = struct {
    whom: []const u8 = "all",
    signal: i32 = std.os.linux.SIG.TERM,

    pub fn validate(self: KillRequest, allocator: std.mem.Allocator) !common.ValidationResult {
        var builder = common.ValidationResultBuilder.new(allocator);

        if (!common.containsString(&.{ "main", "control", "all" }, self.whom)) {
            _ = try builder.addError(.{
                .value = self.whom,
                .property = "whom",
                .message = "Invalid value, allowed values are: main, control and all.",
            });
        }

        return try builder.build();
    }
};

// ------------
// -- Routes --
// ------------

/// Prefix: /v1/systemd/manager
pub const ManagerRoutes = struct {

    // ----------------------------
    // -- GENERAL MANAGER ROUTES --
    // ----------------------------

    pub fn @"POST /reload"(_: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);

        res.status = 204;
        res.content_type = .JSON;

        manager.reload() catch {
            return errors.sendBusError(res, &bus);
        };
    }

    pub fn @"GET /units"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);

        const query = try req.query();
        var unit_type = query.get("type");

        if (unit_type != null and unit_type.?.len == 0) {
            unit_type = null;
        }

        const only_active = common.stringToBool(query.get("onlyActive"), true);

        res.content_type = .JSON;

        manager.listUnitsToJson(res.writer(), unit_type, only_active) catch {
            return errors.sendBusError(res, &bus);
        };
    }

    pub fn @"POST /enable-units"(req: *Request, res: *Response) anyerror!void {
        _ = req;
        _ = res;
        // TODO
    }

    pub fn @"POST /disable-units"(req: *Request, res: *Response) anyerror!void {
        _ = req;
        _ = res;
        // TODO;
    }

    // -------------------------
    // -- UNIT BY NAME ROUTES --
    // -------------------------

    pub fn @"GET /unit/by-name/:name/path"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return errors.sendBusError(res, &bus);
        };

        try res.json(.{ .path = path }, .{});
    }

    pub fn @"GET /unit/by-name/:name/properties"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return errors.sendBusError(res, &bus);
        };

        try getProperties(req, res, &bus, path);
    }
};

fn getProperties(req: *Request, res: *Response, bus: *zbus.ZBus, path: []const u8) !void {
    var properties = systemdbus.Properties.init(bus, try res.arena.dupeZ(u8, path));
    const writer = res.writer();

    const query = try req.query();
    const propsOpt = query.get("props");

    if (propsOpt) |props| {
        var pList = std.ArrayList([]const u8).init(res.arena);
        var iter = std.mem.splitScalar(u8, props, ',');

        while (iter.next()) |prop| {
            try pList.append(prop);
        }

        const pSlice = try pList.toOwnedSlice();

        return properties.getSelectedToJson(writer, pSlice) catch {
            return errors.sendBusError(res, bus);
        };
    }

    res.content_type = .JSON;
    properties.getAllToJson(writer) catch {
        res.conn.res_state.body_len = 0;
        return errors.sendBusError(res, bus);
    };
}

fn listProperties(res: *Response, bus: *zbus.ZBus, path: []const u8) !void {
    var properties = systemdbus.Properties.init(bus, try res.arena.dupeZ(u8, path));

    try res.json(properties.listPropertiesLeaky(res.arena) catch {
        return errors.sendBusError(res, bus);
    }, .{});
}
