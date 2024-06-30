const std = @import("std");
const httpz = @import("httpz");
const common = @import("../../common.zig");
const zbus = @import("../../core/zbus.zig");

const Request = httpz.Request;
const Response = httpz.Response;

pub const VALIDATION_ERROR_TYPE = "/v1/errors/validation-error";
pub const DBUS_ERROR_TYPE = "/v1/errors/dbus-error";
pub const INTERNAL_SERVER_ERROR_TYPE = "https://datatracker.ietf.org/doc/html/rfc7231#section-6.6.1";

pub const ErrorInit = struct {
    type: []const u8,
    status: u16,
    title: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    instance: ?[]const u8 = null,
};

pub const DBusErrorDetail = struct {
    errno: i32,
    name: ?[]const u8,
    message: ?[]const u8,
    method_or_property: ?[]const u8,
    libsystemd_method: ?[]const u8,
};

pub const ValidationSingleErrorDetail = struct {
    property: []const u8,
    value: []const u8,
    message: []const u8,
};

pub const ValidationErrorDetail = struct {
    errors: []const ValidationSingleErrorDetail,
};

pub fn ApiError(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Void => struct {
            type: []const u8,
            status: u16,
            title: ?[]const u8 = null,
            detail: ?[]const u8 = null,
            instance: ?[]const u8 = null,
            has_error_data: bool = false,
            error_data_type: ?[]const u8 = null,
            error_data: ?noreturn = null,
        },
        else => struct {
            type: []const u8,
            status: u16,
            title: ?[]const u8 = null,
            detail: ?[]const u8 = null,
            instance: ?[]const u8 = null,
            has_error_data: bool = true,
            error_data_type: []const u8 = @typeName(T),
            error_data: T,
        },
    };
}

pub fn sendValidationError(res: *Response, errors: []const common.ValidationError) !void {
    res.clearWriter();
    var validation_errors = try res.arena.alloc(ValidationSingleErrorDetail, errors.len);

    for (errors, 0..) |err, i| {
        validation_errors[i] = ValidationSingleErrorDetail{
            .value = err.value,
            .message = err.message,
            .property = err.property,
        };
    }

    res.status = 400;

    try res.json(ApiError(ValidationErrorDetail){
        .type = VALIDATION_ERROR_TYPE,
        .status = 400,
        .title = "Validation error.",
        .detail = "Query or body has invalid properties, see error_data for details.",
        .error_data = ValidationErrorDetail{
            .errors = validation_errors,
        },
    }, .{});
}

pub fn sendBusError(res: *Response, bus: *zbus.ZBus) !void {
    res.clearWriter();

    const errno = -bus.getLastErrno(); // libsystemd is returning negative errno
    const err = bus.getLastCallError();

    var name: ?[]const u8 = err.name;
    var description: ?[]const u8 = err.message;

    if (name == null and errno > 0) {
        const details = common.translateErrno(errno);
        name = details.name;
        description = details.description;
    }

    res.status = 400;

    // 2 -> Not Found
    if (errno == 2) {
        res.status = 404;
    }

    try res.json(ApiError(DBusErrorDetail){
        .type = DBUS_ERROR_TYPE,
        .status = res.status,
        .title = "Dbus error.",
        .detail = try std.fmt.allocPrint(res.arena, "{s}: {s}", .{
            name orelse "UNKNOWN",
            description orelse "Unknown error.",
        }),
        .error_data = DBusErrorDetail{
            .name = name,
            .message = description,
            .errno = errno,
            .libsystemd_method = bus.errored_libsystemd_method,
            .method_or_property = bus.errored_method_or_property,
        },
    }, .{});
}

pub fn sendInternalServerError(res: *Response) !void {
    res.clearWriter();

    res.status = 500;

    try res.json(ApiError(void){
        .type = INTERNAL_SERVER_ERROR_TYPE,
        .status = res.status,
        .title = "Internal server error.",
        .detail = "An internal server error has occured. Deal with it.",
    }, .{});
}

pub const ErrorDescription = struct {
    type: []const u8,
    description: []const u8,
    detail_type_name: []const u8,
    detail_type_definition: []const u8,
};

pub const ErrorDescriptionRoutes = struct {
    pub fn @"GET /validation-error"(_: *Request, res: *Response) anyerror!void {
        const detail_type_definition =
            "{\n" ++
            "\terrors: {\n" ++
            "\t\tproperty: string,\n" ++
            "\t\tvalue: string,\n" ++
            "\t\tmessage: string\n" ++
            "\t}[]\n" ++
            "}[]";

        try res.json(ErrorDescription{
            .type = "/v1/errors/validation-error",
            .description = "Invalid contents of body or query parameters. Error list will contain failed properties.",
            .detail_type_name = @typeName(ValidationErrorDetail),
            .detail_type_definition = detail_type_definition,
        }, .{});
    }

    pub fn @"GET /dbus-error"(_: *Request, res: *Response) anyerror!void {
        const detail_type_definition =
            "{\n" ++
            "\terrno: number,\n" ++
            "\tname?: string,\n" ++
            "\tmessage?: string,\n" ++
            "\tmethod_or_property?: string,\n" ++
            "\tlibsystemd_method?: string\n" ++
            "}";

        try res.json(ErrorDescription{
            .type = "/v1/errors/dbus-error",
            .description = "Error has been returned from DBus.",
            .detail_type_name = @typeName(DBusErrorDetail),
            .detail_type_definition = detail_type_definition,
        }, .{});
    }
};
