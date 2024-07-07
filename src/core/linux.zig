// Here we fuckin go
const std = @import("std");
const common = @import("../common.zig");
const linux = std.os.linux;
const libc = @cImport({
    @cInclude("pwd.h");
});

pub const TimeErrors = error{ClockGetTimeError};
pub const UserErrors = error{Errno};

var pw_mutex = std.Thread.Mutex{};

// Time
pub fn getTimeUsec(clk_id: i32) TimeErrors!u64 {
    var ts: linux.timespec = undefined;
    const ret = linux.clock_gettime(clk_id, &ts);
    if (ret < 0) {
        return TimeErrors.ClockGetTimeError;
    }

    const sec: u64 = @intCast(ts.tv_sec);
    const usec: u64 = @intCast(@divTrunc(ts.tv_nsec, 1000));

    return sec * 1_000_000 + usec;
}

pub fn getRealtimeUsec() u64 {
    return getTimeUsec(linux.CLOCK.REALTIME) catch {
        // We should never get error here as CLOCK_REALTIME is supported in Linux.
        unreachable;
    };
}

pub fn getMonotonicUsec() u64 {
    return getTimeUsec(linux.CLOCK.MONOTONIC) catch {
        // We should never get error here as CLOCK_MONOTONIC is supported in Linux.
        unreachable;
    };
}

pub fn getDualTime() DualTime {
    return .{
        .realtime = getRealtimeUsec(),
        .monotonic = getMonotonicUsec(),
    };
}

pub const DualTime = struct {
    realtime: u64,
    monotonic: u64,
};
// End Time

// Proc

/// Gets process name by pid. output_buffer **must have** len of at least 16 bytes.
pub fn getCommByPid(pid: linux.pid_t, output_buffer: []u8) anyerror![]u8 {
    std.debug.assert(output_buffer.len >= 16);

    var buffer: [64]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buffer, "/proc/{d}/comm", .{pid});

    const file = try std.fs.openFileAbsoluteZ(path, .{});
    defer file.close();
    const read = try file.readAll(output_buffer);
    return output_buffer[0 .. read - 1]; // Last character is new line
}

// End Proc

// Users

/// Will list all users. Use only with arena allocator. This function leaks even on error.
pub fn listUsersLeaky(allocator: std.mem.Allocator) ![]const LinuxUser {
    // Yeah, fgetpwent_r exists but fuck it, enumerating passwd should be fast enough to just allow it for one thread.
    pw_mutex.lock();
    defer pw_mutex.unlock();
    defer libc.endpwent();

    const errno_ptr = std.c._errno();
    errno_ptr.* = 0;

    var list = std.ArrayList(LinuxUser).init(allocator);
    errdefer list.deinit();

    while (true) {
        var pw: ?*libc.passwd = null;
        pw = libc.getpwent();

        if (pw == null) {
            break;
        }

        try list.append(LinuxUser{
            .name = try allocator.dupeZ(u8, std.mem.sliceTo(pw.?.pw_name, 0)),
            .uid = pw.?.pw_uid,
            .gid = pw.?.pw_gid,
            .home = try allocator.dupeZ(u8, std.mem.sliceTo(pw.?.pw_dir, 0)),
            .info = try allocator.dupeZ(u8, std.mem.sliceTo(pw.?.pw_gecos, 0)),
            .shell = try allocator.dupeZ(u8, std.mem.sliceTo(pw.?.pw_shell, 0)),
        });
    }

    if (errno_ptr.* > 0) {
        common.setLastErrno(errno_ptr.*);
        return UserErrors.Errno;
    }

    return try list.toOwnedSlice();
}

pub const LinuxUser = struct {
    name: [:0]const u8,
    uid: linux.uid_t,
    gid: linux.gid_t,
    home: [:0]const u8,
    info: [:0]const u8,
    shell: [:0]const u8,
};
// End Users
