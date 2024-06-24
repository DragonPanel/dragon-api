const std = @import("std");
const common = @import("../common.zig");
const httpz = @import("httpz");
const zbus = @import("../core/zbus.zig");
const systemdbus = @import("../core/systemd-dbus-interfaces.zig");

const Request = httpz.Request;
const Response = httpz.Response;

/// $Prefix: /pid1
pub const Routes = struct {
    /// $OptionalQuery-type - return only specified unit types.
    /// $OptionalQuery-onlyActive - if set to "true" or "yes" only units will active_state=active will be returned.
    pub fn @"GET /units"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager: systemdbus.Manager = systemdbus.Manager.init(&bus);

        const query = try req.query();
        var unitType = query.get("type");

        if (unitType != null and unitType.?.len == 0) {
            unitType = null;
        }

        const onlyActive = query.get("onlyActive");

        res.content_type = .JSON;

        manager.listUnitsToJson(res.writer(), unitType, common.stringToBool(onlyActive, true)) catch {
            res.conn.req_state.body_len = 0;
            return sendBusError(res, &bus);
        };
    }

    pub fn @"GET /unit/by-path/:name/path"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{ .path = path }, .{});
    }

    pub fn @"GET /unit/by-name/:name/properties"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return sendBusError(res, &bus);
        };

        try getProperties(req, res, &bus, path);
    }

    pub fn @"POST /unit/by-name/:name/start"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(StartishRequest) orelse StartishRequest{};

        const path = manager.startUnit(
            res.arena,
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.mode),
        ) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{
            .verb = "start",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/stop"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(StartishRequest) orelse StartishRequest{};

        const path = manager.stopUnit(
            res.arena,
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.mode),
        ) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{
            .verb = "stop",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/restart"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(StartishRequest) orelse StartishRequest{};

        const path = manager.restartUnit(
            res.arena,
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.mode),
        ) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{
            .verb = "restart",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/reload"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(StartishRequest) orelse StartishRequest{};

        const path = manager.reloadUnit(
            res.arena,
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.mode),
        ) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{
            .verb = "reload",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/reload-or-restart"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(StartishRequest) orelse StartishRequest{};

        const path = manager.reloadOrRestartUnit(
            res.arena,
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.mode),
        ) catch {
            return sendBusError(res, &bus);
        };

        try res.json(.{
            .verb = "reload-or-restart",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/kill"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;

        const body = try req.json(KillRequest) orelse KillRequest{};
        const validation = try body.validate(res.arena);

        if (!validation.success) {
            return try sendValidationError(res, validation);
        }

        manager.killUnit(
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.whom),
            body.signal,
        ) catch {
            return sendBusError(res, &bus);
        };
    }

    /// $Method: GET
    /// $Path: /<pideins>/unit/by-path/:path/properties
    /// $OptionalQuery-props: comma-separated list of desired properties to be returned, without any spaces. Example: Id,Names,Type
    /// $Status: 200
    /// $Returns: { [key: string]: any }
    /// $Error-400: Probably wrong unit path, note this endpoint doesn't return error 404.
    ///
    /// Returns all or selected properties of unit with specified path
    /// Route fragment `:path` must be urlencoded
    pub fn @"GET /unit/by-path/:path/properties"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();

        var pathUnescapeBuffer: [256]u8 = undefined;
        const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;

        try getProperties(req, res, &bus, path);
    }

    pub fn @"GET /unit/by-name/:name/properties/list"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return sendBusError(res, &bus);
        };

        try listProperties(res, &bus, path);
    }

    pub fn @"GET /unit/by-path/:path/properties/list"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();

        var pathUnescapeBuffer: [256]u8 = undefined;
        const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;

        try listProperties(res, &bus, path);
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
            return sendBusError(res, bus);
        };
    }

    res.content_type = .JSON;
    properties.getAllToJson(writer) catch {
        res.conn.res_state.body_len = 0;
        return sendBusError(res, bus);
    };
}

fn listProperties(res: *Response, bus: *zbus.ZBus, path: []const u8) !void {
    var properties = systemdbus.Properties.init(bus, try res.arena.dupeZ(u8, path));

    try res.json(properties.listPropertiesLeaky(res.arena) catch {
        return sendBusError(res, bus);
    }, .{});
}

pub fn sendBusError(res: *Response, bus: *zbus.ZBus) !void {
    const errno = bus.getLastErrno();
    const err = try bus.getLastCallError().copy(res.arena);

    res.status = 400;

    // -2 -> Not Found
    if (errno == -2) {
        res.status = 404;
    }

    try res.json(.{
        .status = res.status,
        .reason = "Systemd dbus error",
        .additionalData = .{
            .errno = errno,
            .@"error" = err.name,
            .message = err.message,
        },
    }, .{});
}

pub fn sendValidationError(res: *Response, validationResult: common.ValidationResult) !void {
    res.status = 400;
    try res.json(.{
        .status = res.status,
        .reason = "Validation error",
        .additionalData = validationResult,
    }, .{});
}

const StartishRequest = struct {
    mode: []const u8 = "replace",
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
