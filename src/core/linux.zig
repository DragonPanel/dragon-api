// Here we fuckin go
const std = @import("std");
const linux = std.os.linux;

const Errors = error{ClockGetTimeError};

// Time
pub fn getTimeUsec(clk_id: i32) Errors!u64 {
    var ts: linux.timespec = undefined;
    const ret = linux.clock_gettime(clk_id, &ts);
    if (ret < 0) {
        return Errors.ClockGetTimeError;
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
