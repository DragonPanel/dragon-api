const std = @import("std");
const c_systemd = @cImport({
    @cInclude("systemd/sd-bus.h");
});

pub const BUS_TYPE_STRUCT: u8 = c_systemd.SD_BUS_TYPE_STRUCT;
pub const BUS_TYPE_DICT_ENTRY: u8 = c_systemd.SD_BUS_TYPE_DICT_ENTRY;
pub const BUS_TYPE_ARRAY: u8 = c_systemd.SD_BUS_TYPE_ARRAY;

pub const ZBusError = error{
    Errno,
};

/// Just an alias to distinguish between path and string by looking at type.
pub const Path = [:0]const u8;

threadlocal var last_errno: i32 = 0;
pub fn getLastErrno() i32 {
    return last_errno;
}

/// This function calls `sd\_bus\_default` from libsystemd, call `deinit` on returned object to destroy reference. From libsystemd docs:
/// `sd\_bus\_default()` acquires a bus connection object to the user bus when invoked from within a user slice (any session under "user-*.slice", e.g.: "user@1000.service"),
/// or to the system bus otherwise. The connection object is associated with the calling thread.
/// Each time the function is invoked from the same thread, the same object is returned, but its reference count is increased by one, as long as at least one reference is kept.
///
/// Read more [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_default.html)
pub fn default() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = false };
    const ret = c_systemd.sd_bus_default(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

/// This function calls `sd\_bus\_default\_user` from libsystemd, call deinit on returned object to destroy reference.
/// It works almost identically to `default` function but always connects to user bus.
/// From libsystemd docs:
/// `sd\_bus\_default\_user()` returns a user bus connection object associated with the calling thread.
///
/// Read more [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_default.html)
pub fn defaultUser() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = false };
    const ret = c_systemd.sd_bus_default_user(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

/// This function calls `sd\_bus\_default\_system` from libsystemd, call deinit on returned object to destroy reference.
/// It works almost identically to `default` function but always connects to the systemd bus.
/// From libsystemd docs:
/// `sd_bus_default_system()` is similar \[to the `sd_bus_default_user()`\], but connects to the system bus.
pub fn defaultSystem() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = false };
    const ret = c_systemd.sd_bus_default_system(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

pub fn open() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = true };
    const ret = c_systemd.sd_bus_open(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

pub fn openSystem() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = true };
    const ret = c_systemd.sd_bus_open_system(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

pub fn openUser() ZBusError!ZBus {
    var zbus = ZBus{ .owned_connection = true };
    const ret = c_systemd.sd_bus_open_user(&zbus.bus);
    if (ret < 0) {
        last_errno = ret;
        return ZBusError.Errno;
    }
    return zbus;
}

/// Just a wrapper for some sd\_bus\_\* methods.
/// Note: It's not thread safe
pub const ZBus = struct {
    bus: ?*c_systemd.sd_bus = null,
    last_errno: i32 = 0,
    errored_method_or_property: ?[]const u8 = null,
    errored_libsystemd_method: ?[]const u8 = null,
    // I can't use macro SD_BUS_ERROR_NULL because zig can't translate it :(((
    last_call_error: c_systemd.sd_bus_error = .{
        .name = null,
        .message = null,
        ._need_free = 0,
    },
    owned_connection: bool = false,

    pub fn getLastErrno(self: ZBus) i32 {
        return self.last_errno;
    }

    /// Important note: error is only borrowed from ZBus. It will be destroyed
    /// when ZBus object is deinitted or next method is called. If you want to use it after ZBus is deinitted
    /// you must copy error by using `copy` method on error.
    pub fn getLastCallError(self: ZBus) SdBusError {
        const err = self.last_call_error;

        return SdBusError{
            .name = if (err.name != null) std.mem.sliceTo(err.name, 0) else null,
            .message = if (err.message != null) std.mem.sliceTo(err.message, 0) else null,
            .errno = self.last_errno,
        };
    }

    pub fn isLastMessageErrorSet(self: ZBus) bool {
        return c_systemd.sd_bus_error_is_set(&self.last_call_error) > 0;
    }

    pub fn flush(self: *ZBus) ZBusError!void {
        const r = c_systemd.sd_bus_flush(self.bus);
        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = null;
            self.errored_libsystemd_method = "sd_bus_flush";
            return ZBusError.Errno;
        }
    }

    pub fn close(self: *ZBus) void {
        c_systemd.sd_bus_close(self.bus);
    }

    /// Frees last sd\_bus\_error and urefs bus connection
    pub fn unref(self: *ZBus) void {
        c_systemd.sd_bus_error_free(&self.last_call_error);
        self.bus = c_systemd.sd_bus_unref(self.bus);
    }

    pub fn flushCloseUnref(self: *ZBus) void {
        self.bus = c_systemd.sd_bus_flush_close_unref(self.bus);
    }

    /// Deinit calls `flushCloseUnref` if DBus connection is owned by ZBus struct
    /// Otherwise it will just call `unref`
    /// Basically the rule is:
    /// - if you acquired connection with `default` function or similar then it will only unref
    /// - if you opened connection with `open` function or similar then it will do full cleanup
    pub fn deinit(self: *ZBus) void {
        if (self.owned_connection) {
            self.flushCloseUnref();
        } else {
            self.unref();
        }
    }

    pub fn callMethod(
        self: *ZBus,
        destination: [:0]const u8,
        path: [:0]const u8,
        interface: [:0]const u8,
        member: [:0]const u8,
        types: [:0]const u8,
        args: anytype,
    ) ZBusError!Message {
        // It's safe to call it on SD_BUS_ERROR_NULL. It will also reset value to SD_BUS_ERROR_NULL.
        // We need to always call that before callMethod to avoid memory leak.
        c_systemd.sd_bus_error_free(&self.last_call_error);
        var reply: ?*c_systemd.sd_bus_message = null;
        errdefer _ = c_systemd.sd_bus_message_unref(reply);

        const r = @call(.auto, c_systemd.sd_bus_call_method, .{
            self.bus,
            destination,
            path,
            interface,
            member,
            &self.last_call_error,
            &reply,
            types,
        } ++ args);

        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = member;
            self.errored_libsystemd_method = "sd_bus_call_method";
            return ZBusError.Errno;
        }

        return Message{ .m = reply };
    }

    pub fn getProperty(
        self: *ZBus,
        destination: [:0]const u8,
        path: [:0]const u8,
        interface: [:0]const u8,
        member: [:0]const u8,
        types: [:0]const u8,
    ) ZBusError!Message {
        c_systemd.sd_bus_error_free(&self.last_call_error);
        var reply: ?*c_systemd.sd_bus_message = null;
        errdefer _ = c_systemd.sd_bus_message_unref(reply);

        const r = c_systemd.sd_bus_get_property(
            self.bus,
            destination,
            path,
            interface,
            member,
            &self.last_call_error,
            &reply,
            types,
        );

        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = member;
            self.errored_libsystemd_method = "sd_bus_get_property";
            return ZBusError.Errno;
        }

        return Message{ .m = reply };
    }

    pub fn call(self: *ZBus, message: Message, usec: u64) ZBusError!Message {
        // It's safe to call it on SD_BUS_ERROR_NULL. It will also reset value to SD_BUS_ERROR_NULL.
        // We need to always call that before call to avoid memory leak.
        c_systemd.sd_bus_error_free(&self.last_call_error);
        var reply: ?*c_systemd.sd_bus_message = null;
        errdefer _ = c_systemd.sd_bus_message_unref(reply);

        const r = c_systemd.sd_bus_call(
            self.bus,
            message.m,
            usec,
            &self.last_call_error,
            &reply,
        );

        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = "Unknown";
            self.errored_libsystemd_method = "sd_bus_call";
            return ZBusError.Errno;
        }

        return Message{ .m = reply };
    }

    pub fn messageNewMethodCall(
        self: *ZBus,
        destination: [:0]const u8,
        path: [:0]const u8,
        interface: [:0]const u8,
        member: [:0]const u8,
    ) ZBusError!Message {
        var message = Message{};
        const r = c_systemd.sd_bus_message_new_method_call(
            self.bus,
            &message.m,
            destination,
            path,
            interface,
            member,
        );
        errdefer message.unref();

        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = null;
            self.errored_libsystemd_method = "sd_bus_message_new_method_call";
            return ZBusError.Errno;
        }
        return message;
    }

    pub fn getMethodCallTimeoutUsec(self: *ZBus) ZBusError!u64 {
        var xd: u64 = 0;
        const r = c_systemd.sd_bus_get_method_call_timeout(self.bus, &xd);
        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = null;
            self.errored_libsystemd_method = "sd_bus_get_method_call_timeout";
            return ZBusError.Errno;
        }

        return xd;
    }

    pub fn setMethodCallTimeoutUsec(self: *ZBus, timeout_usec: u64) ZBusError!void {
        const r = c_systemd.sd_bus_set_method_call_timeout(self.bus, timeout_usec);
        if (r < 0) {
            self.last_errno = r;
            self.errored_method_or_property = null;
            self.errored_libsystemd_method = "sd_bus_set_method_call_timeout";
            return ZBusError.Errno;
        }
    }
};

pub const SdBusError = struct {
    name: ?[:0]const u8,
    message: ?[:0]const u8,
    errno: i32,

    /// Copies SdBusError contents allocating memory.
    /// Note: you must deinit copied message when it's no longer needed or use ArenaAllocator.
    pub fn copy(self: SdBusError, allocator: std.mem.Allocator) !SdBusErrorCopied {
        return SdBusErrorCopied{
            .allocator = allocator,
            .name = if (self.name) |name| try allocator.dupeZ(u8, name) else null,
            .message = if (self.message) |message| try allocator.dupeZ(u8, message) else null,
            .errno = self.errno,
        };
    }
};

pub const SdBusErrorCopied = struct {
    name: ?[:0]const u8,
    message: ?[:0]const u8,
    errno: i32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *SdBusErrorCopied) void {
        if (self.name != null) {
            self.allocator.free(self.name);
        }
        if (self.message != null) {
            self.allocator.free(self.message);
        }
    }
};

pub const Message = struct {
    m: ?*c_systemd.sd_bus_message = null,
    last_errno: i32 = 0,

    pub fn getLastErrno(self: Message) i32 {
        return self.last_errno;
    }

    pub fn unref(self: *Message) void {
        _ = c_systemd.sd_bus_message_unref(self.m);
        self.m = null;
    }

    /// Calls sd\_bus\_message\_append from libsystemd.
    /// Important note: string arguments **MUST BE** null terminated sentinel slices. Or bad stuff will happen.
    /// For more information go [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_message_append.html)
    pub fn append(self: *Message, types: [:0]const u8, args: anytype) ZBusError!void {
        // I could force "types" to be compile time and validate args for correct types
        // but I am too lazy for that shit.
        const r = @call(.auto, c_systemd.sd_bus_message_append, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_open\_container from libsystemd.
    pub fn openContainer(self: *Message, containerType: u8, contents: [:0]const u8) ZBusError!void {
        const r = c_systemd.sd_bus_message_open_container(self.m, containerType, contents);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_close\_container from libsystemd.
    pub fn closeContainer(self: *Message) ZBusError!void {
        const r = c_systemd.sd_bus_message_close_container(self.m);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// Calls sd\_bus\_message\_read from libsystemd.
    /// Important note: strings are borrowed from message objects and **must be** copied if one wants to use them after message is freed.
    /// The same rule applies to UNIX file descriptors.
    /// For more information go [here](https://www.freedesktop.org/software/systemd/man/latest/sd_bus_message_read.html)
    pub fn read(self: *Message, types: [:0]const u8, args: anytype) ZBusError!bool {
        const r = @call(.auto, c_systemd.sd_bus_message_read, .{ self.m, types } ++ args);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
        return r > 0;
    }

    pub fn skip(self: *Message, types: ?[*:0]const u8) ZBusError!void {
        const r = c_systemd.sd_bus_message_skip(self.m, types);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }

    /// PeekResult.contents are only borrowed.
    pub fn peekType(self: *Message) ZBusError!PeekResult {
        var ret = PeekResult{};
        const r = c_systemd.sd_bus_message_peek_type(self.m, &ret.type, &ret.contents);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }

        return ret;
    }

    /// Calls sd\_bus\_message\_enter\_container from libsystemd.
    pub fn enterContainer(self: *Message, containerType: u8, contents: [*:0]const u8) ZBusError!bool {
        const r = c_systemd.sd_bus_message_enter_container(self.m, containerType, contents);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
        return r > 0;
    }

    /// Calls sd\_bus\_message\_exit\_container from libsystemd.
    pub fn exitContainer(self: *Message) ZBusError!void {
        const r = c_systemd.sd_bus_message_exit_container(self.m);
        if (r < 0) {
            self.last_errno = r;
            return ZBusError.Errno;
        }
    }
};

pub const PeekResult = struct {
    type: u8 = 0,
    contents: ?[*:0]const u8 = null,
};

pub fn ParsedMessage(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            self.arena.deinit();
        }
    };
}
