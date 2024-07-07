const std = @import("std");
const common = @import("../../common.zig");
const config_module = @import("../../config.zig");
const errors = @import("./errors.zig");
const httpz = @import("httpz");
const zbus = @import("../../core/zbus.zig");
const systemdbus = @import("../../core/systemd-dbus-interfaces.zig");
const JournalReader = @import("../../core/journal-reader.zig").JournalReader;

const Request = httpz.Request;
const Response = httpz.Response;

const JournalQuery = struct {
    /// How many lines should be retuned
    limit: u32 = 100,

    /// Cursor of journal entry from which lines shall be returned
    cursor: ?[]const u8 = null,

    /// Direction can be only one of two: ASC -> from oldest to newest, DESC -> from newest to oldest
    direction: []const u8 = "ASC",

    /// Comma-separated fields to return, set null to return all the fields.
    /// Only UPPERCASE letters, numbers and underscores are allowed. Field name cannot start with 2 underscores.
    /// /query-journal endpoint will return metadata fields anyway, so there's no need to query for them.
    fields: ?[]const u8 = null,

    /// Unit name. If no unit is specified then all units are includes.
    unit: ?[]const u8 = null,
};

pub const Routes = struct {
    pub fn @"GET /simple-query"(req: *Request, res: *Response) anyerror!void {
        const query_parse_result = try parseQuery(res.arena, req);

        if (!query_parse_result.validation_result.success) {
            return try errors.sendValidationError(res, query_parse_result.validation_result.errors);
        }

        var parsed_query = query_parse_result.data.?;
        const config = try config_module.getConfig();

        if (parsed_query.limit > config.maxJournalLines) {
            std.log.warn("Requested {d} lines of journal, but maxJournalLines in config is set to {d}.", .{ parsed_query.limit, config.maxJournalLines });
            parsed_query.limit = config.maxJournalLines;
        }

        const allocator = res.arena;
        var fields: ?[][]const u8 = null;

        if (parsed_query.fields) |f| {
            var fieldsList = std.ArrayList([]const u8).init(allocator);
            var it = std.mem.splitSequence(u8, f, ",");

            while (it.next()) |x| {
                try fieldsList.append(x);
            }

            fields = try fieldsList.toOwnedSlice();
        }

        var reader = try JournalReader.init(allocator, .{
            .unit = parsed_query.unit,
            .lines = parsed_query.limit,
            .fields = fields,
            .cursor = parsed_query.cursor,
            .direction = if (std.mem.eql(u8, parsed_query.direction, "DESC")) .DESCENDING else .ASCENDING,
        });
        defer reader.deinit();

        res.content_type = .JSON;
        reader.writeToJson(res.writer()) catch |err| {
            // TODO: send nice error message maybe???
            // This makes httpz to ingore partially written json in case of an error.
            res.conn.req_state.body_len = 0;
            return err;
        };
    }
};

const QueryParseResult = struct {
    validation_result: common.ValidationResult,
    data: ?JournalQuery,
};

/// Parses get query
fn parseQuery(allocator: std.mem.Allocator, req: *Request) !QueryParseResult {
    var parsedQuery = JournalQuery{};
    const query = try req.query();
    var validation_builder = common.ValidationResultBuilder.new(allocator);

    if (query.get("limit")) |limit| {
        parsedQuery.limit = std.fmt.parseInt(u32, limit, 0) catch blk: {
            try validation_builder.addError(.{ .value = limit, .property = "limit", .message = "Limit must be valid non-negative integer." });

            break :blk parsedQuery.limit;
        };
    }

    if (query.get("cursor")) |cursor| {
        parsedQuery.cursor = cursor;
    }

    if (query.get("direction")) |direction| {
        if (std.ascii.eqlIgnoreCase(direction, "ASC")) {
            parsedQuery.direction = "ASC";
        } else if (std.ascii.eqlIgnoreCase(direction, "DESC")) {
            parsedQuery.direction = "DESC";
        } else {
            try validation_builder.addError(.{ .value = direction, .property = "direction", .message = "Direction can be either 'ASC' or 'DESC'. Case is ignored." });
        }
    }

    if (query.get("fields")) |fields| {
        var it = std.mem.splitSequence(u8, fields, ",");
        var i: u32 = 0;
        while (it.next()) |field| {
            if (!validateFieldName(field)) {
                try validation_builder.addError(.{
                    .value = field,
                    .property = try std.fmt.allocPrint(allocator, "fields:{d}", .{i}),
                    .message = "One of provided fields was invalid. Field list must be comma seperated list of strings that contains only UPPERCASE letters, number, underscores and can't start with double underscore.",
                });
            }
            i += 1;
        }
        parsedQuery.fields = fields;
    }

    if (query.get("unit")) |unit| {
        parsedQuery.unit = unit;
    }

    const validation_result = try validation_builder.build();
    if (!validation_result.success) {
        return QueryParseResult{
            .data = null,
            .validation_result = validation_result,
        };
    } else {
        return QueryParseResult{
            .data = parsedQuery,
            .validation_result = validation_result,
        };
    }
}

/// Journald allows only for underscores, UPPERCASE letters and numbers.
/// User defined fields cannot start from underscore, fields starting with 2 underscore are meta fields.
/// There are also metadata fields starting with 2 underscores, I am disallowing selecting that,
/// because I return metadata anyways using built in functions for getting them.
fn validateFieldName(field: []const u8) bool {
    if (field.len == 0) {
        return false;
    }
    if (field.len >= 2 and field[0] == '_' and field[1] == '_') {
        return false;
    }

    for (field) |char| {
        if (char == '_') continue;
        if (char >= 'A' and char <= 'Z') continue;
        if (char >= '0' and char <= '9') continue;
        return false;
    }

    return true;
}
