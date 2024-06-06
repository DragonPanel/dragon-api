pub const queryJournal = @import("./routes/query-journal.zig");
pub const pidEins = @import("./routes/pid-eins.zig");

const logger = std.log.scoped(.routeRegister);

pub fn registerRoutes(router: anytype, prefix: ?[]const u8, comptime RoutesStruct: type) void {
    if (comptime !isStruct(RoutesStruct)) {
        @compileError("Provided type is not a struct.");
    }

    const handlers = comptime get_handlers: {
        var handlers: []const RouteHandler = &.{};

        for (@typeInfo(RoutesStruct).Struct.decls) |d| {
            if (isRouteFunc(@TypeOf(@field(RoutesStruct, d.name)))) {
                handlers = handlers ++ .{.{ .name = d.name, .func = @field(RoutesStruct, d.name) }};
            }
        }

        break :get_handlers handlers;
    };

    var group = router.group(prefix orelse "", .{});

    const methods = .{
        .{ "GET", _get },
        .{ "POST", _post },
        .{ "PUT", _put },
        .{ "DELETE", _delete },
        .{ "PATCH", _patch },
        .{ "HEAD", _head },
        .{ "OPTIONS", _options },
    };

    for (handlers) |handler| {
        var method: []const u8 = "GET";
        var route: []const u8 = "";
        if (std.mem.startsWith(u8, handler.name, "/")) {
            // No method verb, so we will assume default GET
            _get(&group, handler.name, handler.func);
            route = handler.name;
        } else {
            var it = std.mem.splitScalar(u8, handler.name, ' ');
            const methodFromHandler = it.first();
            const path = it.next();

            if (path == null) {
                logger.warn("Function {s} has invalid name to be registered as route handler. It's name should be 'method /path' or '/path'. Skipping it.", .{handler.name});
                continue;
            }

            route = path.?;

            var methodFound = false;

            inline for (methods) |m| {
                if (std.ascii.eqlIgnoreCase(m[0], methodFromHandler)) {
                    method = m[0];
                    m[1](&group, route, handler.func);
                    methodFound = true;
                    break;
                }
            }

            if (!methodFound) {
                logger.warn("Couldn't register function {s} as route handler. Invalid method: {s}", .{ handler.name, method });
            }
        }

        logger.info("{s} {s}{s}", .{ method, prefix orelse "", route });
    }
}

const std = @import("std");
const httpz = @import("httpz");
const TypeId = std.builtin.TypeId;
const activeTag = std.meta.activeTag;

fn isStruct(comptime T: type) bool {
    return activeTag(@typeInfo(T)) == TypeId.Struct;
}

const Handler = fn (*httpz.Request, *httpz.Response) anyerror!void;
const HandlerPtr = *const Handler;

fn isRouteFunc(comptime T: type) bool {
    return T == HandlerPtr or T == Handler;
}

const RouteHandler = struct {
    name: []const u8,
    func: *const fn (*httpz.Request, *httpz.Response) anyerror!void,
};

fn _get(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.get(path, handler);
}

fn _post(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.post(path, handler);
}

fn _put(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.put(path, handler);
}

fn _delete(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.delete(path, handler);
}

fn _patch(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.patch(path, handler);
}

fn _head(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.head(path, handler);
}

fn _options(routerOrGroup: anytype, path: []const u8, handler: HandlerPtr) void {
    routerOrGroup.options(path, handler);
}
