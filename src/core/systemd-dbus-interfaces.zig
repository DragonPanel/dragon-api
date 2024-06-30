const std = @import("std");
const common = @import("../common.zig");
const zbus = @import("./zbus.zig");
const ZBusProxy = @import("./zbus-proxy.zig").ZBusProxy;

// I need this error set because ZIG CAN'T INFER ERRORS IN RECURSIVE CALLS -____-
pub const Errors = error{ UnknownTypeFound, Errno, OutOfMemory };

pub const Manager = struct {
    proxy: ZBusProxy,

    const destination = "org.freedesktop.systemd1";
    const path = "/org/freedesktop/systemd1";
    const interface = "org.freedesktop.systemd1.Manager";

    pub fn init(bus: *zbus.ZBus) Manager {
        return Manager{ .proxy = ZBusProxy.init(bus, destination, path, interface) };
    }

    pub fn reload(self: *Manager) !void {
        var timeout = try self.proxy.bus.getMethodCallTimeoutUsec();
        if (timeout < std.math.maxInt(u64) / 2) {
            // If for some goddamn reason someone would set SYSTEMD_BUS_TIMEOUT to extremely high value
            // for which should be sent to ninth circle of hell
            // It won't overflow.
            // I am setting it to twice as normal timeout, because reload is kinda heavy operation.
            timeout *= 2;
        }
        var m = try self.proxy.messageNewMethodCall("Reload");
        defer m.unref();
        var reply = self.proxy.bus.call(m, timeout) catch |err| {
            // I have to set it manually here coz call method doesn't know which method is calling.
            self.proxy.bus.errored_method_or_property = "Reload";
            return err;
        };
        // Technically I don't have to do it as Reload replies nothing but whatever
        reply.unref();
    }

    /// may be used to get the unit object path for a unit name. It takes the unit name and returns the object path. If a unit has not been loaded yet by this name this call will fail.
    /// Caller owns returned Path and is responsible for freeing it.
    pub fn getUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "GetUnit",
            "s",
            .{name.ptr},
        );
        defer m.unref();

        var unit: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&unit});

        if (unit) |not_null_unit| {
            return try allocator.dupeZ(u8, std.mem.sliceTo(not_null_unit, 0));
        } else {
            unreachable; // unit shouldn't be null.
        }
    }

    // pub fn getUnitByPID

    /// is similar to getUnit() but will load the unit from disk if possible.
    /// Caller owns returned Path and is responsible for freeing it.
    pub fn loadUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8) zbus.ZBusError!zbus.Path {
        var m = try self.proxy.callMethod(
            "LoadUnit",
            "s",
            .{name},
        );
        defer m.unref();
        var unit: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&unit});

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
    pub fn startUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "StartUnit",
            "ss",
            .{ name.ptr, mode.ptr },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    /// StopUnit() is similar to StartUnit() but stops the specified unit rather than starting it. Note that "isolate" mode is invalid for this call.
    /// Returns path to enqueued job. Caller owns returned Path and is responsible for freeing it.
    pub fn stopUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "StopUnit",
            "ss",
            .{ name.ptr, mode.ptr },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    pub fn reloadUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "ReloadUnit",
            "ss",
            .{ name.ptr, mode.ptr },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    pub fn restartUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "RestartUnit",
            "ss",
            .{ name.ptr, mode.ptr },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    pub fn reloadOrRestartUnit(self: *Manager, allocator: std.mem.Allocator, name: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            "ReloadOrRestartUnit",
            "ss",
            .{ name.ptr, mode.ptr },
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    pub fn enableUnitFilesLeaky(self: *Manager, allocator: std.mem.Allocator, files: []const []const u8, opts: EnableUnitFilesOptions) !EnableResult {
        var m = try self.proxy.messageNewMethodCall("EnableUnitFiles");
        defer m.unref();

        // param: files
        try m.openContainer(zbus.BUS_TYPE_ARRAY, "s");
        for (files) |file| {
            const zeroTerminated = try allocator.dupeZ(u8, file);
            defer allocator.free(zeroTerminated);
            try m.append("s", .{zeroTerminated.ptr});
        }
        try m.closeContainer();
        // param: runtime
        try m.append("b", .{if (opts.runtime) @as(i32, 1) else @as(i32, 0)});
        // param: force
        try m.append("b", .{if (opts.force) @as(i32, 1) else @as(i32, 0)});

        var reply = self.proxy.bus.call(m, 0) catch |err| {
            self.proxy.bus.errored_method_or_property = "EnableUnitFiles";
            return err;
        };
        defer reply.unref();

        var carries_install_info: i32 = 0;
        var changes = std.ArrayList(EnableDisableChange).init(allocator);
        errdefer changes.deinit();

        _ = try reply.read("b", .{&carries_install_info});
        _ = try reply.enterContainer(zbus.BUS_TYPE_ARRAY, "(sss)");

        while (true) {
            var change_type: ?[*:0]const u8 = null;
            var symlink: ?[*:0]const u8 = null;
            var dest: ?[*:0]const u8 = null;

            const wasRead = try reply.read("(sss)", .{ &change_type, &symlink, &dest });
            if (!wasRead) {
                break;
            }

            try changes.append(EnableDisableChange{
                .type = try allocator.dupeZ(u8, std.mem.sliceTo(change_type.?, 0)),
                .symlink_filename = try allocator.dupeZ(u8, std.mem.sliceTo(symlink.?, 0)),
                .destination_filename = try allocator.dupeZ(u8, std.mem.sliceTo(dest.?, 0)),
            });
        }

        try reply.exitContainer();

        return EnableResult{
            .carries_install_info = carries_install_info > 0,
            .changes = try changes.toOwnedSlice(),
        };
    }

    pub fn disableUnitFilesLeaky(self: *Manager, allocator: std.mem.Allocator, files: []const []const u8, opts: DisableUnitFilesOptions) !DisableResult {
        var m = try self.proxy.messageNewMethodCall("DisableUnitFiles");
        defer m.unref();

        // param: files
        try m.openContainer(zbus.BUS_TYPE_ARRAY, "s");
        for (files) |file| {
            const zeroTerminated = try allocator.dupeZ(u8, file);
            defer allocator.free(zeroTerminated);
            try m.append("s", .{zeroTerminated.ptr});
        }
        try m.closeContainer();
        // param: runtime
        try m.append("b", .{if (opts.runtime) @as(i32, 1) else @as(i32, 0)});

        var reply = self.proxy.bus.call(m, 0) catch |err| {
            self.proxy.bus.errored_method_or_property = "DisableUnitFiles";
            return err;
        };
        defer reply.unref();

        var changes = std.ArrayList(EnableDisableChange).init(allocator);
        errdefer changes.deinit();

        _ = try reply.enterContainer(zbus.BUS_TYPE_ARRAY, "(sss)");

        while (true) {
            var change_type: ?[*:0]const u8 = null;
            var symlink: ?[*:0]const u8 = null;
            var dest: ?[*:0]const u8 = null;

            const wasRead = try reply.read("(sss)", .{ &change_type, &symlink, &dest });
            if (!wasRead) {
                break;
            }

            try changes.append(EnableDisableChange{
                .type = try allocator.dupeZ(u8, std.mem.sliceTo(change_type.?, 0)),
                .symlink_filename = try allocator.dupeZ(u8, std.mem.sliceTo(symlink.?, 0)),
                .destination_filename = try allocator.dupeZ(u8, std.mem.sliceTo(dest.?, 0)),
            });
        }

        try reply.exitContainer();

        return DisableResult{
            .changes = try changes.toOwnedSlice(),
        };
    }

    pub fn killUnit(self: *Manager, name: [:0]const u8, whom: [:0]const u8, signal: i32) zbus.ZBusError!void {
        var m = try self.proxy.callMethod(
            "KillUnit",
            "ssi",
            .{ name.ptr, whom.ptr, signal },
        );
        defer m.unref();
    }

    pub fn getJob(self: *Manager, allocator: std.mem.Allocator, id: u32) zbus.ZBusError!zbus.Path {
        var m = try self.proxy.callMethod(
            "GetJob",
            "u",
            .{id},
        );
        defer m.unref();

        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, job.?);
    }

    pub fn listUnits(self: *Manager, allocator: std.mem.Allocator) !zbus.ParsedMessage([]UnitListEntry) {
        var parsedMessage = zbus.ParsedMessage([]UnitListEntry){ .arena = std.heap.ArenaAllocator.init(allocator) };
        parsedMessage.value = try self.listUnitsLeaky(parsedMessage.arena.allocator());
        return parsedMessage;
    }

    pub fn listUnitsLeaky(self: *Manager, allocator: std.mem.Allocator) ![]UnitListEntry {
        var m = try self.proxy.callMethod(
            "ListUnits",
            "",
            .{},
        );
        defer m.unref();

        var list = std.ArrayList(UnitListEntry).init(allocator);
        errdefer list.deinit();

        _ = try m.enterContainer('a', "(ssssssouso)");

        while (true) {
            var name: ?[*:0]const u8 = null;
            var desc: ?[*:0]const u8 = null;
            var load_state: ?[*:0]const u8 = null;
            var active_state: ?[*:0]const u8 = null;
            var sub_state: ?[*:0]const u8 = null;
            var followed: ?[*:0]const u8 = null;
            var _path: ?[*:0]const u8 = null;
            var queued_job_id: u32 = 0;
            var job_type: ?[*:0]const u8 = null;
            var job_path: ?[*:0]const u8 = null;

            const wasRead = try m.read("(ssssssouso)", .{
                &name,
                &desc,
                &load_state,
                &active_state,
                &sub_state,
                &followed,
                &_path,
                &queued_job_id,
                &job_type,
                &job_path,
            });
            if (!wasRead) break;

            // Note, in case or allocation error we will have memory leak here
            // But that's okey, I am not designing this API as OOM resistant.
            try list.append(.{
                .name = try allocator.dupeZ(u8, std.mem.sliceTo(name.?, 0)),
                .description = try allocator.dupeZ(u8, std.mem.sliceTo(desc.?, 0)),
                .load_state = try allocator.dupeZ(u8, std.mem.sliceTo(load_state.?, 0)),
                .active_state = try allocator.dupeZ(u8, std.mem.sliceTo(active_state.?, 0)),
                .sub_state = try allocator.dupeZ(u8, std.mem.sliceTo(sub_state.?, 0)),
                .followed = try allocator.dupeZ(u8, std.mem.sliceTo(followed.?, 0)),
                .path = try allocator.dupeZ(u8, std.mem.sliceTo(_path.?, 0)),
                .queued_job_id = queued_job_id,
                .job_type = try allocator.dupeZ(u8, std.mem.sliceTo(job_type.?, 0)),
                .job_path = try allocator.dupeZ(u8, std.mem.sliceTo(job_path.?, 0)),
            });
        }

        try m.exitContainer();
        return try list.toOwnedSlice();
    }

    pub fn listUnitsToJson(self: *Manager, writer: anytype, service_type: ?[]const u8, only_active: bool) !void {
        var ws = std.json.writeStream(writer, .{});

        var m = try self.proxy.callMethod(
            "ListUnits",
            "",
            .{},
        );
        defer m.unref();

        _ = try m.enterContainer('a', "(ssssssouso)");

        try ws.beginArray();

        while (true) {
            var name: ?[*:0]const u8 = null;
            var desc: ?[*:0]const u8 = null;
            var load_state: ?[*:0]const u8 = null;
            var active_state: ?[*:0]const u8 = null;
            var sub_state: ?[*:0]const u8 = null;
            var followed: ?[*:0]const u8 = null;
            var _path: ?[*:0]const u8 = null;
            var queued_job_id: u32 = 0;
            var job_type: ?[*:0]const u8 = null;
            var job_path: ?[*:0]const u8 = null;

            const wasRead = try m.read("(ssssssouso)", .{
                &name,
                &desc,
                &load_state,
                &active_state,
                &sub_state,
                &followed,
                &_path,
                &queued_job_id,
                &job_type,
                &job_path,
            });
            if (!wasRead) break;

            if (service_type) |st| {
                if (!std.mem.endsWith(u8, std.mem.sliceTo(name.?, 0), st)) {
                    continue;
                }
            }

            if (only_active) {
                if (!std.mem.eql(u8, std.mem.sliceTo(active_state.?, 0), "active")) {
                    continue;
                }
            }

            try ws.beginObject();

            try ws.objectField("name");
            try ws.write(name);

            try ws.objectField("description");
            try ws.write(desc);

            try ws.objectField("load_state");
            try ws.write(load_state);

            try ws.objectField("active_state");
            try ws.write(active_state);

            try ws.objectField("sub_state");
            try ws.write(sub_state);

            try ws.objectField("followed");
            try ws.write(followed);

            try ws.objectField("path");
            try ws.write(_path);

            try ws.objectField("queued_job_id");
            try ws.write(queued_job_id);

            try ws.objectField("job_type");
            try ws.write(job_type);

            try ws.objectField("job_path");
            try ws.write(job_path);

            try ws.endObject();
        }

        try m.exitContainer();
        try ws.endArray();
    }
};

pub const Unit = struct {
    proxy: ZBusProxy,

    const destination = "org.freedesktop.systemd1";
    const interface = "org.freedesktop.systemd1.Unit";

    pub fn init(bus: *zbus.ZBus, path: [:0]const u8) Unit {
        return Unit{ .proxy = ZBusProxy.init(bus, destination, path, interface) };
    }

    pub fn start(self: *Unit, allocator: std.mem.Allocator, mode: [:0]const u8) !zbus.Path {
        return try self.startishJob(allocator, "Start", mode);
    }

    pub fn stop(self: *Unit, allocator: std.mem.Allocator, mode: [:0]const u8) !zbus.Path {
        return try self.startishJob(allocator, "Stop", mode);
    }

    pub fn reload(self: *Unit, allocator: std.mem.Allocator, mode: [:0]const u8) !zbus.Path {
        return try self.startishJob(allocator, "Reload", mode);
    }

    pub fn restart(self: *Unit, allocator: std.mem.Allocator, mode: [:0]const u8) !zbus.Path {
        return try self.startishJob(allocator, "Restart", mode);
    }

    pub fn reloadOrRestart(self: *Unit, allocator: std.mem.Allocator, mode: [:0]const u8) !zbus.Path {
        return try self.startishJob(allocator, "ReloadOrRestart", mode);
    }

    pub fn kill(self: *Unit, whom: [:0]const u8, signal: i32) !void {
        var m = try self.proxy.callMethod(
            "Kill",
            "si",
            .{ whom.ptr, signal },
        );
        defer m.unref();
    }

    fn startishJob(self: *Unit, allocator: std.mem.Allocator, method: [:0]const u8, mode: [:0]const u8) !zbus.Path {
        var m = try self.proxy.callMethod(
            method,
            "s",
            .{mode.ptr},
        );
        defer m.unref();
        var job: ?[*:0]const u8 = null;
        _ = try m.read("o", .{&job});

        return try allocator.dupeZ(u8, std.mem.sliceTo(job.?, 0));
    }

    pub fn Id(self: *Unit, allocator: std.mem.Allocator) ![:0]const u8 {
        return try self.proxy.getStrProp(allocator, "Id");
    }

    pub fn Names(self: *Unit, allocator: std.mem.Allocator) ![][:0]const u8 {
        return try self.proxy.getStrArrayProp(allocator, "Names");
    }

    pub fn NamesLeaky(self: *Unit, allocator: std.mem.Allocator) ![][:0]const u8 {
        return try self.proxy.getStrArrPropLeaky(allocator, "Names");
    }
};

pub const Properties = struct {
    proxy: ZBusProxy,

    const destination = "org.freedesktop.systemd1";
    const interface = "org.freedesktop.DBus.Properties";

    pub fn init(bus: *zbus.ZBus, path: [:0]const u8) Properties {
        return Properties{ .proxy = ZBusProxy.init(bus, destination, path, interface) };
    }

    pub fn listPropertiesLeaky(self: *Properties, allocator: std.mem.Allocator) ![][:0]const u8 {
        // Return type is a{sv}
        var m = try self.proxy.callMethod("GetAll", "s", .{""});
        defer m.unref();

        var list = std.ArrayList([:0]const u8).init(allocator);
        errdefer list.deinit();

        _ = try m.enterContainer('a', "{sv}");

        while (true) {
            const read = try m.enterContainer('e', "sv");
            if (!read) break;

            var prop: ?[*:0]const u8 = null;
            _ = try m.read("s", .{&prop});
            try list.append(try allocator.dupeZ(u8, std.mem.sliceTo(prop.?, 0)));

            // We need to skip next variant coz otherwise libsystemd will be unhappy
            // and won't let us exit the container umu
            try m.skip(null);

            try m.exitContainer();
        }

        try m.exitContainer();

        return try list.toOwnedSlice();
    }

    pub fn getAllToJson(self: *Properties, writer: anytype) !void {
        // Return type is a{sv}
        var m = try self.proxy.callMethod("GetAll", "s", .{""});
        defer m.unref();

        var ws = std.json.writeStream(writer, .{});

        _ = try m.enterContainer(zbus.BUS_TYPE_ARRAY, "{sv}");
        try ws.beginObject();

        while (true) {
            const read = try m.enterContainer(zbus.BUS_TYPE_DICT_ENTRY, "sv");
            if (!read) break;

            var prop: ?[*:0]const u8 = null;
            _ = try m.read("s", .{&prop});

            try ws.objectField(std.mem.sliceTo(prop.?, 0));
            const variantContents = (try m.peekType()).contents;
            try readVariant(&m, &ws, variantContents.?);

            try m.exitContainer();
        }

        try ws.endObject();
        try m.exitContainer();
    }

    pub fn getSelectedToJson(self: *Properties, writer: anytype, selected: []const []const u8) !void {
        // Return type is a{sv}
        var m = try self.proxy.callMethod("GetAll", "s", .{""});
        defer m.unref();

        var ws = std.json.writeStream(writer, .{});

        _ = try m.enterContainer(zbus.BUS_TYPE_ARRAY, "{sv}");
        try ws.beginObject();

        while (true) {
            const read = try m.enterContainer(zbus.BUS_TYPE_DICT_ENTRY, "sv");
            if (!read) break;

            var prop: ?[*:0]const u8 = null;
            _ = try m.read("s", .{&prop});

            if (common.containsString(selected, std.mem.sliceTo(prop.?, 0))) {
                try ws.objectField(std.mem.sliceTo(prop.?, 0));
                const variantContents = (try m.peekType()).contents;
                try readVariant(&m, &ws, variantContents.?);
            } else {
                try m.skip(null);
            }

            try m.exitContainer();
        }

        try ws.endObject();
        try m.exitContainer();
    }

    fn readNext(m: *zbus.Message, jsonWriteStream: anytype) Errors!bool {
        const t = try m.peekType();
        if (t.type == 0) {
            return false;
        }

        try switch (t.type) {
            'v' => readVariant(m, jsonWriteStream, t.contents.?),
            zbus.BUS_TYPE_STRUCT => readStruct(m, jsonWriteStream, t.contents.?),
            zbus.BUS_TYPE_ARRAY => readArray(m, jsonWriteStream, t.contents.?),
            zbus.BUS_TYPE_DICT_ENTRY => readDictEntry(m, jsonWriteStream, t.contents.?),

            // basic types
            'y' => {
                var v: u8 = 0;
                _ = try m.read("y", .{&v});
                try jsonWriteStream.write(v);
            },
            'b' => {
                var v: c_int = 0;
                _ = try m.read("b", .{&v});
                try jsonWriteStream.write(v > 0);
            },
            'n' => {
                var v: i16 = 0;
                _ = try m.read("n", .{&v});
                try jsonWriteStream.write(v);
            },
            'q' => {
                var v: u16 = 0;
                _ = try m.read("q", .{&v});
                try jsonWriteStream.write(v);
            },
            'i' => {
                var v: i32 = 0;
                _ = try m.read("i", .{&v});
                try jsonWriteStream.write(v);
            },
            'u' => {
                var v: u32 = 0;
                _ = try m.read("u", .{&v});
                try jsonWriteStream.write(v);
            },
            'x' => {
                var v: i64 = 0;
                _ = try m.read("x", .{&v});
                try jsonWriteStream.write(v);
            },
            't' => {
                var v: u64 = 0;
                _ = try m.read("t", .{&v});
                try jsonWriteStream.write(v);
            },
            'd' => {
                var v: f64 = 0;
                _ = try m.read("d", .{&v});
                try jsonWriteStream.write(v);
            },
            's', 'o', 'g' => {
                var v: ?[*:0]const u8 = null;
                const strT = switch (t.type) {
                    's' => "s",
                    'o' => "o",
                    'g' => "g",
                    else => unreachable,
                };
                _ = try m.read(strT, .{&v});
                try jsonWriteStream.write(std.mem.sliceTo(v.?, 0));
            },
            'h' => {
                var v: c_int = 0;
                _ = try m.read("h", .{&v});
            },
            else => {
                std.log.err("Unknown systemd dbus type found: {c}", .{t.type});
                return Errors.UnknownTypeFound;
            },
        };

        return true;
    }

    fn readVariant(m: *zbus.Message, jsonWriteStream: anytype, contents: [*:0]const u8) !void {
        _ = try m.enterContainer('v', contents);
        _ = try readNext(m, jsonWriteStream);
        try m.exitContainer();
    }

    fn readStruct(m: *zbus.Message, jsonWriteStream: anytype, contents: [*:0]const u8) !void {
        _ = try m.enterContainer(zbus.BUS_TYPE_STRUCT, contents);
        // since zbus struct are like tuples I have to use array here, which makes me really sad.
        try jsonWriteStream.beginArray();

        while (true) {
            const read = try readNext(m, jsonWriteStream);
            if (!read) break;
        }

        try jsonWriteStream.endArray();
        try m.exitContainer();
    }

    fn readArray(m: *zbus.Message, jsonWriteStream: anytype, contents: [*:0]const u8) !void {
        _ = try m.enterContainer(zbus.BUS_TYPE_ARRAY, contents);

        try jsonWriteStream.beginArray();

        while (true) {
            const read = try readNext(m, jsonWriteStream);
            if (!read) break;
        }

        try jsonWriteStream.endArray();

        try m.exitContainer();
    }

    fn readDictEntry(m: *zbus.Message, jsonWriteStream: anytype, contents: [*:0]const u8) !void {
        // Dictionaries will be read into array of objects, containing two properties: key and value.
        // I couldn't find anywhere information whether dictionary keys are unique or not AND I WON'T TRUST CHAT GPT who told me they are.
        // And since it's signature is just an array of dict entries, I am gonna assume that they don't have to be unique.
        // Besides it will be easier to read dict data by client consuming the data, I guess?
        // Also keys are basic type but it doesn't mean that they can't be a number.
        _ = try m.enterContainer(zbus.BUS_TYPE_DICT_ENTRY, contents);

        try jsonWriteStream.beginObject();
        try jsonWriteStream.objectField("key");
        _ = try readNext(m, jsonWriteStream);
        try jsonWriteStream.objectField("value");
        _ = try readNext(m, jsonWriteStream);
        try jsonWriteStream.endObject();

        try m.exitContainer();
    }
};

pub const UnitListEntry = struct {
    name: [:0]const u8,
    description: [:0]const u8,
    load_state: [:0]const u8,
    active_state: [:0]const u8,
    sub_state: [:0]const u8,
    followed: [:0]const u8,
    path: zbus.Path,
    queued_job_id: u32,
    job_type: [:0]const u8,
    job_path: zbus.Path,
};

pub const EnableUnitFilesOptions = struct {
    /// Controls whether the unit shall be enabled for runtime only (true, /run/), or persistently (false, /etc/).
    runtime: bool = false,
    /// Controls whether symlinks pointing to other units shall be replaced if necessary.
    force: bool = false,
};

pub const DisableUnitFilesOptions = struct {
    /// Controls whether the unit shall be disabled for runtime only (true, /run/), or persistently (false, /etc/).
    runtime: bool = false,
};

pub const EnableResult = struct {
    carries_install_info: bool,
    changes: []const EnableDisableChange,
};

pub const DisableResult = struct {
    changes: []const EnableDisableChange,
};

pub const EnableDisableChange = struct {
    /// symlink/unlink
    type: [:0]const u8,
    symlink_filename: [:0]const u8,
    destination_filename: [:0]const u8,
};
