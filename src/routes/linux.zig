const std = @import("std");
const httpz = @import("httpz");
const linux = @import("../core/linux.zig");
const common = @import("../common.zig");

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

    pub fn @"GET /users"(_: *Request, res: *Response) anyerror!void {
        const users = linux.listUsersLeaky(res.arena) catch |err| {
            if (err == linux.UserErrors.Errno) {
                res.status = 500;
                const trans_err = common.translateErrno(common.getLastErrno());

                try res.json(.{
                    .@"error" = trans_err.name,
                    .description = trans_err.description,
                }, .{});

                return;
            }

            return err;
        };

        return try res.json(users, .{});
    }
};
