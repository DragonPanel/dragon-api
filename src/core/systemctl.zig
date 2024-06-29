//! Helper functions to make systemctl easier to use.
const std = @import("std");

// Maybe TODO: Implement systemctl-show.c in here, to return all needed data in single request.

pub fn enable(allocator: std.mem.Allocator, unitName: []const u8, now: bool) !u32 {
    // I won't try to do it with dbus, fuck that
    // TODO: add some timeout or something
    var child = std.ChildProcess.init(
        &.{
            "/usr/bin/systemctl",
            "enable",
            unitName,
            if (now) "--now",
        },
        allocator,
    );
    try child.spawn();
    const term = try child.wait();
    return switch (term) {
        term.Exited => |code| return code,
        term.Signal => |code| return code,
        term.Stopped => |code| return code,
        term.Unknown => |code| return code,
    };
}

pub fn disable(allocator: std.mem.Allocator, unitName: []const u8, now: bool) !u32 {
    // I won't try to do it with dbus, fuck that
    // TODO: add some timeout or something
    var child = std.ChildProcess.init(
        &.{
            "/usr/bin/systemctl",
            "disable",
            unitName,
            if (now) "--now",
        },
        allocator,
    );
    try child.spawn();
    const term = try child.wait();
    return switch (term) {
        term.Exited => |code| return code,
        term.Signal => |code| return code,
        term.Stopped => |code| return code,
        term.Unknown => |code| return code,
    };
}
