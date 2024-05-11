const std = @import("std");
const printf = std.c.printf;
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;
const routes = @import("./routes.zig");

pub fn main() !void {
    const port: u16 = 1337;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var server = try httpz.Server().init(allocator, .{ .port = port });

    var router = server.router();

    router.get("/hello", getHello);
    router.get("/query-journal", routes.queryJournal.queryJournal);

    _ = printf("Serva will now listen on port %d\n", port);
    try server.listen();
}

fn getHello(_: *Request, res: *Response) !void {
    try res.json(.{ .hello = "world" }, .{});
}

comptime {
    _ = @import("./routes/query-journal.test.zig");
}

test "yolo" {
    try std.testing.expect(true);
}
