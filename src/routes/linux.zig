const std = @import("std");
const httpz = @import("httpz");
const linux = @import("../core/linux.zig");

const Request = httpz.Request;
const Response = httpz.Response;

/// $Prefix: /linux
pub const Routes = struct {
    pub fn @"GET /time/real"(_: *Request, res: *Response) anyerror!void {
        const time = linux.getRealtimeUsec();
        try res.json(.{ .realtime = time }, .{});
    }

    pub fn @"GET /time/monotonic"(_: *Request, res: *Response) anyerror!void {
        const time = linux.getMonotonicUsec();
        try res.json(.{ .monotonic = time }, .{});
    }

    pub fn @"GET /time/dual"(_: *Request, res: *Response) anyerror!void {
        const time = linux.getDualTime();
        try res.json(time, .{});
    }

    pub fn @"GET /proc/:pid/comm"(req: *Request, res: *Response) anyerror!void {
        const pid_str = req.param("pid").?;
        const pid = std.fmt.parseInt(std.os.linux.pid_t, pid_str, 10) catch {
            res.status = 400;
            try res.json(.{
                .@"error" = "Invalid :pid route param.",
                .param = pid_str,
            }, .{});
            return;
        };

        var comm_buffer: [16]u8 = undefined;
        const comm = try linux.getCommByPid(pid, &comm_buffer);

        try res.json(.{ .pid = pid, .comm = comm }, .{});
    }
};
