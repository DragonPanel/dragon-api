const std = @import("std");
const httpz = @import("httpz");
const Request = httpz.Request;
const Response = httpz.Response;
const common = @import("../common.zig");
const JournalReader = @import("../core/journal-reader.zig").JournalReader;
const configModule = @import("../config.zig");

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

    /// If base64 is set to true then binary fields will be returned as base64, otherwise as byte array
    base64: bool = true,

    /// Unit name. If no unit is specified then all units are includes.
    unit: ?[]const u8 = null,

    // TODO: add later cool filtering stuff ^^
};

pub fn queryJournal(req: *Request, res: *Response) !void {
    var parsedQuery = try parseQuery(req, res);
    const config = try configModule.getConfig();

    // If parse query returns null then is means some query param was invalid
    // In that case function sends 400 - Bad request with appropriate message to the client
    // Yeah, it's kinda ugly but since I can't pass values with zig's errors yet I did that as temporary solution.
    // TODO: fix it when zig 0.13 will be released
    if (parsedQuery == null) {
        return;
    }

    if (parsedQuery.?.limit > config.maxJournalLines) {
        std.log.warn("Requested {d} lines of journal, but maxJournalLines in config is set to {d}.", .{ parsedQuery.?.limit, config.maxJournalLines });
        parsedQuery.?.limit = config.maxJournalLines;
    }

    const allocator = res.arena;
    var fields: ?[][]const u8 = null;

    if (parsedQuery.?.fields) |f| {
        var fieldsList = std.ArrayList([]const u8).init(allocator);
        var it = std.mem.splitSequence(u8, f, ",");

        while (it.next()) |x| {
            try fieldsList.append(x);
        }

        fields = try fieldsList.toOwnedSlice();
    }

    var reader = try JournalReader.init(allocator, .{
        .unit = parsedQuery.?.unit,
        .lines = parsedQuery.?.limit,
        .fields = fields,
        .cursor = parsedQuery.?.cursor,
        .direction = if (std.mem.eql(u8, parsedQuery.?.direction, "DESC")) .DESCENDING else .ASCENDING,
        .encodeBinaryAsBase64 = parsedQuery.?.base64,
    });
    defer reader.deinit();

    var outputBuffer = std.ArrayList(u8).init(allocator);
    try reader.writeToJson(outputBuffer.writer());
    const output = try outputBuffer.toOwnedSlice();
    defer allocator.free(output);

    res.body = output;
    res.content_type = .JSON;
    // try res.write();
}

/// Parses get query
/// If something is wrong it sends 400 - Bad Request response and returns null.
/// You **MUST** return from your route handler if this returs null.
fn parseQuery(req: *Request, res: *Response) !?JournalQuery {
    var parsedQuery = JournalQuery{};
    const query = try req.query();

    if (query.get("limit")) |limit| {
        parsedQuery.limit = std.fmt.parseInt(u32, limit, 0) catch {
            try common.sendBadRequest(
                res,
                "Query parameter 'limit' is invalid, it must be positive integer.",
                .{ .param = "limit", .value = limit },
            );
            return null;
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
            try common.sendBadRequest(
                res,
                "Query parameter 'direction' is invalid, it must be either 'ASC' or 'DESC'.",
                .{ .param = "direction", .value = direction },
            );
            return null;
        }
    }

    if (query.get("fields")) |fields| {
        var it = std.mem.splitSequence(u8, fields, ",");
        var i: u32 = 0;
        while (it.next()) |field| {
            if (!validateFieldName(field)) {
                try common.sendBadRequest(
                    res,
                    "Query parameter 'fields' is invalid, it must be comma seperated list of strings that contains only UPPERCASE letters, number, underscores and can't start with double underscore.",
                    .{ .param = try std.fmt.allocPrint(res.arena, "field:{d}", .{i}), .value = field },
                );
                return null;
            }
            i += 1;
        }
        parsedQuery.fields = fields;
    }

    if (query.get("base64")) |base64| {
        if (std.ascii.eqlIgnoreCase(base64, "true") or std.ascii.eqlIgnoreCase(base64, "yes")) {
            parsedQuery.base64 = true;
        } else if (std.ascii.eqlIgnoreCase(base64, "false") or std.ascii.eqlIgnoreCase(base64, "no")) {
            parsedQuery.base64 = false;
        } else {
            try common.sendBadRequest(
                res,
                "Query parameter 'base64' is invalid, it must be true, false, yes or no.",
                .{ .param = "base64", .value = base64 },
            );
            return null;
        }
    }

    if (query.get("unit")) |unit| {
        parsedQuery.unit = unit;
    }

    return parsedQuery;
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
