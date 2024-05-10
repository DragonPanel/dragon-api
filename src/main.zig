const std = @import("std");
const printf = std.c.printf;
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;
const routes = @import("./routes.zig");

const sdJournal = @import("sd-journal.zig");

pub fn main() !void {
    const port: u16 = 1337;
    const allocator = std.heap.c_allocator;
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
