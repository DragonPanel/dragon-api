const libc = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("string.h");
});
const std = @import("std");
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;

pub const StringToBoolErrors = error{
    InvalidString,
};

threadlocal var last_errno: i32 = 0;

pub fn setLastErrno(errno: i32) void {
    last_errno = errno;
}

pub fn getLastErrno() i32 {
    return last_errno;
}

/// Translates given errno value to `ErrnoError` struct, containing
/// - numeric errno
/// - error name or null if errno is invalid
/// - description or null if errno is invalid
pub fn translateErrno(errno: i32) ErrnoError {
    const libc_err_name = libc.strerrorname_np(errno);
    const libc_err_desc = libc.strerrordesc_np(errno);

    return .{
        .errno = errno,
        // According to GNU: The returned string does not change for the remaining execution of the program.
        // So I can safely just assign them here.
        // ref: https://www.gnu.org/software/libc/manual/html_node/Error-Messages.html#index-strerrorname_005fnp
        .name = if (libc_err_name != null) std.mem.sliceTo(libc_err_name, 0) else null,
        .description = if (libc_err_desc != null) std.mem.sliceTo(libc_err_desc, 0) else null,
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

pub fn stringToBool(str: ?[]const u8, allowNoYes: bool) bool {
    if (str == null) {
        return false;
    }

    if (std.ascii.eqlIgnoreCase(str.?, "true")) {
        return true;
    }

    if (allowNoYes and std.ascii.eqlIgnoreCase(str.?, "yes")) {
        return true;
    }

    return false;
}

/// Works almost the same way as `stringToBool` but
/// return an error instead of false if string if invalid.
pub fn stringToBoolStrict(str: ?[]const u8, allowNoYes: bool) StringToBoolErrors!bool {
    if (str == null) {
        return StringToBoolErrors.InvalidString;
    }

    if (std.ascii.eqlIgnoreCase(str.?, "true")) {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(str.?, "false")) {
        return false;
    }

    if (allowNoYes and std.ascii.eqlIgnoreCase(str.?, "yes")) {
        return true;
    }

    if (allowNoYes and std.ascii.eqlIgnoreCase(str.?, "no")) {
        return false;
    }

    return StringToBoolErrors.InvalidString;
}

pub const ErrnoError = struct {
    name: ?[:0]const u8,
    description: ?[:0]const u8,
    errno: i32,
};

pub const ValidationResultBuilder = struct {
    _res: ValidationResult = .{},
    _errors: std.ArrayList(ValidationError),
    _allocator: std.mem.Allocator,

    /// Allocator should be arena allocator to free resources when no longer needed
    pub fn new(allocator: std.mem.Allocator) ValidationResultBuilder {
        return .{
            ._allocator = allocator,
            ._errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn addError(self: *ValidationResultBuilder, err: ValidationError) !*ValidationResultBuilder {
        self._res.success = false;
        try self._errors.append(err);
        return self;
    }

    pub fn build(self: *ValidationResultBuilder) !ValidationResult {
        self._res.errors = try self._errors.toOwnedSlice();
        return self._res;
    }
};

pub const ValidationError = struct {
    property: []const u8,
    value: []const u8,
    message: []const u8,
};

pub const ValidationResult = struct {
    success: bool = true,
    errors: []const ValidationError = &.{},
};
