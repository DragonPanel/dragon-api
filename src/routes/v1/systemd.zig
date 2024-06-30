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
    units: []const [:0]const u8 = &.{},
    no_reload: bool = false,
    runtime: bool = false,
    force: bool = false,
};

const ReloadError = struct {
    errno: i32,
    @"error": ?[:0]const u8,
    message: ?[:0]const u8,
};

const EnableUnitsResponse = struct {
    verb: []const u8,
    daemon_reloaded: bool,
    reload_failed: bool,
    reload_error: ?ReloadError,
    result: systemdbus.EnableResult,
};

const DisableUnitsRequest = struct {
    units: []const [:0]const u8 = &.{},
    no_reload: bool = false,
    runtime: bool = false,
};

const DisableUnitsRespone = struct {
    verb: []const u8,
    daemon_reloaded: bool,
    reload_failed: bool,
    reload_error: ?ReloadError,
    result: systemdbus.DisableResult,
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

const KillResponse = struct {
    verb: []const u8,
    whom: []const u8,
    signal: i32,
};

const StartishRequest = struct {
    mode: []const u8 = "replace",
};

const StartishResponse = struct {
    verb: []const u8,
    mode: []const u8,
    job_path: zbus.Path,
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
        const body = try req.json(EnableUnitsRequest) orelse EnableUnitsRequest{};

        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);

        const result = manager.enableUnitFilesLeaky(res.arena, body.units, .{
            .runtime = body.runtime,
            .force = body.force,
        }) catch {
            return errors.sendBusError(res, &bus);
        };

        var daemon_reloaded: bool = false;
        var reload_failed: bool = false;

        if (!body.no_reload) {
            manager.reload() catch {
                reload_failed = true;
            };
            daemon_reloaded = !reload_failed;
        }

        const reload_error = bus.getLastCallError();
        const reload_error_formatted = ReloadError{
            .errno = reload_error.errno,
            .@"error" = reload_error.name,
            .message = reload_error.message,
        };

        try res.json(EnableUnitsResponse{
            .verb = "enable",
            .daemon_reloaded = daemon_reloaded,
            .reload_failed = reload_failed,
            .reload_error = if (reload_failed) reload_error_formatted else null,
            .result = result,
        }, .{});
    }

    pub fn @"POST /disable-units"(req: *Request, res: *Response) anyerror!void {
        const body = try req.json(DisableUnitsRequest) orelse DisableUnitsRequest{};

        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);

        const result = manager.disableUnitFilesLeaky(res.arena, body.units, .{
            .runtime = body.runtime,
        }) catch {
            return errors.sendBusError(res, &bus);
        };

        var daemon_reloaded: bool = false;
        var reload_failed: bool = false;

        if (!body.no_reload) {
            manager.reload() catch {
                reload_failed = true;
            };
            daemon_reloaded = !reload_failed;
        }

        const reload_error = bus.getLastCallError();
        const reload_error_formatted = ReloadError{
            .errno = reload_error.errno,
            .@"error" = reload_error.name,
            .message = reload_error.message,
        };

        try res.json(DisableUnitsRespone{
            .verb = "enable",
            .daemon_reloaded = daemon_reloaded,
            .reload_failed = reload_failed,
            .reload_error = if (reload_failed) reload_error_formatted else null,
            .result = result,
        }, .{});
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

    pub fn @"GET /unit/by-name/:name/properties/list"(req: *Request, res: *Response) anyerror!void {
        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);
        const name = req.param("name").?;
        const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
            return errors.sendBusError(res, &bus);
        };

        try listProperties(res, &bus, path);
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
            return errors.sendBusError(res, &bus);
        };

        try res.json(StartishResponse{
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
            return errors.sendBusError(res, &bus);
        };

        try res.json(StartishResponse{
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
            return errors.sendBusError(res, &bus);
        };

        try res.json(StartishResponse{
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
            return errors.sendBusError(res, &bus);
        };

        try res.json(StartishResponse{
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
            return errors.sendBusError(res, &bus);
        };

        try res.json(StartishResponse{
            .verb = "reload-or-restart",
            .mode = body.mode,
            .job_path = path,
        }, .{});
    }

    pub fn @"POST /unit/by-name/:name/kill"(req: *Request, res: *Response) anyerror!void {
        const name = req.param("name").?;

        const body = try req.json(KillRequest) orelse KillRequest{};
        const validation = try body.validate(res.arena);

        if (!validation.success) {
            return try errors.sendValidationError(res, validation.errors);
        }

        var bus = try zbus.openSystem();
        defer bus.deinit();
        var manager = systemdbus.Manager.init(&bus);

        manager.killUnit(
            try res.arena.dupeZ(u8, name),
            try res.arena.dupeZ(u8, body.whom),
            body.signal,
        ) catch {
            return errors.sendBusError(res, &bus);
        };

        try res.json(KillResponse{
            .verb = "kill",
            .whom = body.whom,
            .signal = body.signal,
        }, .{});
    }

    // -------------------------
    // -- UNIT BY PATH ROUTES --
    // -------------------------

    pub fn @"GET /unit/by-path/:path/properties"(req: *Request, res: *Response) anyerror!void {
        var pathUnescapeBuffer: [256]u8 = undefined;
        const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;

        var bus = try zbus.openSystem();
        defer bus.deinit();

        try getProperties(req, res, &bus, path);
    }

    pub fn @"GET /unit/by-path/:path/properties/list"(req: *Request, res: *Response) anyerror!void {
        var pathUnescapeBuffer: [256]u8 = undefined;
        const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;

        var bus = try zbus.openSystem();
        defer bus.deinit();

        try listProperties(res, &bus, path);
    }

    pub fn @"POST /unit/by-path/:path/start"(req: *Request, res: *Response) anyerror!void {
        try unitPathStartishFn(req, res, "start", systemdbus.Unit.start);
    }

    pub fn @"POST /unit/by-path/:path/stop"(req: *Request, res: *Response) anyerror!void {
        try unitPathStartishFn(req, res, "stop", systemdbus.Unit.stop);
    }

    pub fn @"POST /unit/by-path/:path/reload"(req: *Request, res: *Response) anyerror!void {
        try unitPathStartishFn(req, res, "reload", systemdbus.Unit.reload);
    }

    pub fn @"POST /unit/by-path/:path/restart"(req: *Request, res: *Response) anyerror!void {
        try unitPathStartishFn(req, res, "restart", systemdbus.Unit.restart);
    }

    pub fn @"POST /unit/by-path/:path/reload-or-restart"(req: *Request, res: *Response) anyerror!void {
        try unitPathStartishFn(req, res, "reload-or-restart", systemdbus.Unit.reloadOrRestart);
    }

    pub fn @"POST /unit/by-path/:path/kill"(req: *Request, res: *Response) anyerror!void {
        var pathUnescapeBuffer: [256]u8 = undefined;
        const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;
        const body = try req.json(KillRequest) orelse KillRequest{};

        const validation = try body.validate(res.arena);

        if (!validation.success) {
            return try errors.sendValidationError(res, validation.errors);
        }

        var bus = try zbus.openSystem();
        defer bus.deinit();
        var unit = systemdbus.Unit.init(&bus, try res.arena.dupeZ(u8, path));

        unit.kill(
            try res.arena.dupeZ(u8, body.whom),
            body.signal,
        ) catch {
            return errors.sendBusError(res, &bus);
        };

        try res.json(KillResponse{
            .verb = "kill",
            .whom = body.whom,
            .signal = body.signal,
        }, .{});
    }
};

fn unitPathStartishFn(req: *Request, res: *Response, verb: []const u8, method: anytype) !void {
    var pathUnescapeBuffer: [256]u8 = undefined;
    const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;
    const body = try req.json(StartishRequest) orelse StartishRequest{};

    var bus = try zbus.openSystem();
    defer bus.deinit();
    var unit = systemdbus.Unit.init(&bus, try res.arena.dupeZ(u8, path));

    const job_path = method(
        &unit,
        res.arena,
        try res.arena.dupeZ(u8, body.mode),
    ) catch {
        return errors.sendBusError(res, &bus);
    };

    try res.json(StartishResponse{
        .verb = verb,
        .mode = body.mode,
        .job_path = job_path,
    }, .{});
}

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
