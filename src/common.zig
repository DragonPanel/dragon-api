const libc = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("string.h");
});
const std = @import("std");
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;

threadlocal var lastErrno: i32 = 0;

pub fn setLastErrno(errno: i32) void {
    lastErrno = errno;
}

pub fn getLastErrno() i32 {
    return lastErrno;
}

/// Translates given errno value to `ErrnoError` struct, containing
/// - numeric errno
/// - error name or null if errno is invalid
/// - description or null if errno is invalid
pub fn translateErrno(errno: i32) ErrnoError {
    return .{
        .errno = errno,
        // According to GNU: The returned string does not change for the remaining execution of the program.
        // So I can safely just assign them here.
        // ref: https://www.gnu.org/software/libc/manual/html_node/Error-Messages.html#index-strerrorname_005fnp
        .name = libc.strerrorname_np(errno),
        .description = libc.strerrordesc_np(errno),
    };
}

pub fn sendBadRequest(res: *Response, reason: []const u8, additionalData: anytype) !void {
    res.status = 400;
    try res.json(.{
        .status = 400,
        .statusText = "Bad Request",
        .reason = reason,
        .additionalData = additionalData,
    }, .{});
}

/// Shamelessly stolen from https://github.com/nektro/zig-extras/blob/master/src/containsString.zig
pub fn containsString(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) {
            return true;
        }
    }
    return false;
}

pub const ErrnoError = struct {
    name: ?[:0]const u8,
    description: ?[:0]const u8,
    errno: i32,
};
