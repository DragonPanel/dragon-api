// Here we fuckin go
const linux = @import("std").os.linux;

pub fn getTimeUsec(clk_id: i32) u64 {
    var ts: linux.timespec = undefined;
    linux.clock_gettime(clk_id, &ts);
    return ts.tv_sec * 1_000_000 + ts.tv_nsec / 1000;
}

pub fn getRealtimeUsec() u64 {
    return getTimeUsec(linux.CLOCK.REALTIME);
}

pub fn getMonotonicUsec() u64 {
    return getTimeUsec(linux.CLOCK.MONOTONIC);
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
