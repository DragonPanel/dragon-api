const std = @import("std");
const httpz = @import("httpz");
const zbus = @import("../core/zbus.zig");
const systemdbus = @import("../core/systemd-dbus-interfaces.zig");

const Request = httpz.Request;
const Response = httpz.Response;

pub fn registerRoutes(group: anytype) void {
    group.get("/units", listUnits);
    group.get("/unit/by-name/:name/path", getUnitPathByName);
    group.get("/unit/by-path/:path/properties/list", listProperties);
}

pub fn getUnitPathByName(req: *Request, res: *Response) !void {
    var bus = try zbus.openSystem();
    defer bus.deinit();
    var manager: systemdbus.Manager = systemdbus.Manager.init(&bus);
    const name = req.param("name").?;
    const path = manager.getUnit(res.arena, try res.arena.dupeZ(u8, name)) catch {
        return sendError(res, &bus);
    };
    try res.json(.{ .path = path }, .{});
}

pub fn listProperties(req: *Request, res: *Response) !void {
    var bus = try zbus.openSystem();
    defer bus.deinit();

    var pathUnescapeBuffer: [128]u8 = undefined;
    const path = (try httpz.Url.unescape(req.arena, &pathUnescapeBuffer, req.param("path").?)).value;

    var properties = systemdbus.Properties.init(&bus, try res.arena.dupeZ(u8, path));

    try res.json(properties.listPropertiesLeaky(res.arena) catch {
        return sendError(res, &bus);
    }, .{});
}

// TODO: add some filtering maybe uwu
pub fn listUnits(_: *Request, res: *Response) !void {
    var bus = try zbus.openSystem();
    defer bus.deinit();
    var manager: systemdbus.Manager = systemdbus.Manager.init(&bus);
    const list = manager.listUnitsLeaky(res.arena) catch {
        return sendError(res, &bus);
    };
    try res.json(list, .{});
}

pub fn sendError(res: *Response, bus: *zbus.ZBus) !void {
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
