const std = @import("std");
const zbus = @import("./zbus.zig");

const Manager = struct {
    bus: *zbus.ZBus,

    const destination = "org.freedesktop.systemd1";
    const path = "/org/freedesktop/systemd1";
    const interface = "org.freedesktop.systemd1.Manager";

    pub fn init(bus: *zbus.ZBus) Manager {
        return Manager{ .bus = bus };
    }

    /// may be used to get the unit object path for a unit name. It takes the unit name and returns the object path. If a unit has not been loaded yet by this name this call will fail.
    /// Caller owns returned Path and is responsible for freeing it.
    pub fn getUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8) zbus.ZbusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "GetUnit",
            "s",
            .{name},
        );
        defer m.unref();
        var unit: ?[*:0]const u8 = null;
        try m.read("o", .{&unit});

        if (unit) |not_null_unit| {
            return try allocator.dupeZ(u8, not_null_unit);
        } else {
            unreachable; // unit shouldn't be null.
        }
    }

    // pub fn getUnitByPID

    /// is similar to getUnit() but will load the unit from disk if possible.
    /// Caller owns returned Path and is responsible for freeing it.
    pub fn loadUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "LoadUnit",
            "s",
            .{name},
        );
        defer m.unref();
        var unit: ?[*:0]const u8 = null;
        try m.read("o", .{&unit});

        if (unit) |not_null_unit| {
            return try allocator.dupeZ(u8, not_null_unit);
        } else {
            unreachable; // unit shouldn't be null.
        }
    }

    /// Enqeues a start job, and possibly depending jobs. Takes the unit to activate, plus a mode string.
    /// The mode needs to be one of replace, fail, isolate, ignore-dependencies, ignore-requirements.
    /// If "replace" the call will start the unit and its dependencies, possibly replacing already queued jobs that conflict with this.
    /// If "fail" the call will start the unit and its dependencies, but will fail if this would change an already queued job.
    /// If "isolate" the call will start the unit in question and terminate all units that aren't dependencies of it.
    /// If "ignore-dependencies" it will start a unit but ignore all its dependencies.
    /// If "ignore-requirements" it will start a unit but only ignore the requirement dependencies.
    /// It is not recommended to make use of the latter two options. Returns the newly created job object.
    /// Returns path to enqueued job. Caller owns returned Path and is responsible for freeing it.
    pub fn startUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "StartUnit",
            "ss",
            .{ name, mode },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    /// StopUnit() is similar to StartUnit() but stops the specified unit rather than starting it. Note that "isolate" mode is invalid for this call.
    /// Returns path to enqueued job. Caller owns returned Path and is responsible for freeing it.
    pub fn stopUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "StopUnit",
            "ss",
            .{ name, mode },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    pub fn reloadUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "ReloadUnit",
            "ss",
            .{ name, mode },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    pub fn restartUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "RestartUnit",
            "ss",
            .{ name, mode },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    pub fn reloadOrRestartUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) zbus.ZBusError!zbus.Path {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "ReloadOrRestartUnit",
            "ss",
            .{ name, mode },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    pub fn killUnit(self: *Manager, name: [:0]const u8, who: [:0]const u8, signal: i32) zbus.ZBusError!void {
        const m = try self.bus.callMethod(
            Manager.destination,
            Manager.path,
            Manager.interface,
            "KillUnit",
            "ssi",
            .{ name, who, signal },
        );
        defer m.unref();
    }
};
