const std = @import("std");
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;

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
