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
