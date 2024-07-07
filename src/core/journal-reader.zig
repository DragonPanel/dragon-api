const std = @import("std");
const sdJournal = @import("./sd-journal.zig");

pub const ReadingDirection = enum { ASCENDING, DESCENDING };

pub const JournalReaderConfig = struct {
    /// Which fields to return. If not set then it will return all fields.
    fields: ?[][]const u8 = null,

    /// How many lines to load. Default = 100
    lines: u32 = 100,

    /// ReadingDirection.ASCENDING -> From oldest to newest, reading from the beginning of the journal if no cursor was set
    /// ReadingDirection.DESCEDING -> From newest to oldest, reading from the end of the journal if no cursor was set
    /// Default = .ASCENDING
    direction: ReadingDirection = .ASCENDING,

    /// Unit for which to load entries. If null then everything will be read
    unit: ?[]const u8 = null,

    /// Read start position
    cursor: ?[]const u8 = null,

    /// Timestamp starting point, if cursor is set then this has no effect
    real_timestamp: ?u64 = null,
};

pub const JournalReader = struct {
    allocator: std.mem.Allocator,
    journal: sdJournal.Journal,
    fields: ?std.BufSet = null,
    lines: u32,
    direction: ReadingDirection,
    unit: ?[]const u8,
    cursor: ?[]const u8,

    const Self = JournalReader;

    /// Opens journal and initializes reader.
    /// Reader has to be freed by calling deinit, otherwise memory will leak and we don't want that.
    pub fn init(allocator: std.mem.Allocator, config: JournalReaderConfig) !Self {
        var reader = Self{
            .allocator = allocator,
            .journal = try sdJournal.openJournal(0),
            .lines = config.lines,
            .direction = config.direction,
            .unit = config.unit,
            .cursor = config.cursor,
        };

        // in case of any init error I will free the journal to avoid memory leak
        errdefer reader.journal.close();

        if (config.fields) |fields| {
            reader.fields = std.BufSet.init(allocator);
            errdefer reader.fields.?.deinit();

            for (fields) |field| {
                try reader.fields.?.insert(field);
            }
        }

        return reader;
    }

    pub fn writeToJson(self: *Self, writer: anytype) !void {
        var ws = std.json.writeStream(writer, .{});
        try ws.beginArray();

        var i: u32 = 0;
        var nextFn: *const fn (*sdJournal.Journal) sdJournal.ErrnoError!bool = sdJournal.Journal.next;

        if (self.direction == .DESCENDING) {
            try self.journal.seekTail();
            nextFn = sdJournal.Journal.prev;
        }

        if (self.cursor) |cursor| {
            try self.journal.seekCursor(self.allocator, cursor);
        }

        if (self.unit) |unit| {
            try self.journal.addMatch(self.allocator, "UNIT", unit);
        }

        while (try nextFn(&self.journal) and i < self.lines) : (i += 1) {
            try self.writeSingleEntryToJson(&ws);
        }

        try ws.endArray();
        ws.deinit();
    }

    pub fn deinit(self: *Self) void {
        if (self.fields != null) {
            self.fields.?.deinit();
        }
        self.journal.close();
    }

    fn writeSingleEntryToJson(self: *Self, stream: anytype) !void {
        try stream.beginObject();

        if (self.fields) |selectedFields| {
            try self.writeSelectedFields(stream, selectedFields);
        } else {
            try self.writeAllFields(stream);
        }

        try stream.endObject();
    }

    fn writeSelectedFields(self: *Self, stream: anytype, fields: std.BufSet) !void {
        var fieldsIt = fields.iterator();

        while (fieldsIt.next()) |selectedField| {
            const data = try self.journal.readFieldAlloc(self.allocator, selectedField.*) orelse continue;
            defer self.allocator.free(data);

            var it = std.mem.split(u8, data, "=");
            const field = it.first();

            const fieldLower = try std.ascii.allocLowerString(self.allocator, field);
            defer self.allocator.free(fieldLower);

            try stream.objectField(fieldLower);

            const rawValue = it.rest();
            try self.writeValue(stream, rawValue);
        }
    }

    fn writeAllFields(self: *Self, stream: anytype) !void {
        // Because in journal fields can be duplicated and in JSON not
        // I need somehow to keep track of already added fields to handle duplicated field scenario.
        var addedFields = std.BufSet.init(self.allocator);
        defer addedFields.deinit();

        while (try self.journal.readNextFieldAlloc(self.allocator)) |data| {
            defer self.allocator.free(data);

            var it = std.mem.split(u8, data, "=");
            const field = it.first();

            if (self.fields) |selectedFields| {
                if (!selectedFields.contains(field)) {
                    continue;
                }
            }

            if (addedFields.contains(field)) {
                // For now I will skip duplicated fields, they're pretty rare and proble:matic to deal with on API Client side.
                // TODO: Maybe I should add duplicated fields as "field:n"?
                continue;
            }
            try addedFields.insert(field);

            const fieldLower = try std.ascii.allocLowerString(self.allocator, field);
            defer self.allocator.free(fieldLower);

            try stream.objectField(fieldLower);

            const rawValue = it.rest();
            try self.writeValue(stream, rawValue);
        }
    }

    fn writeValue(self: *Self, stream: anytype, rawValue: []const u8) !void {
        if (std.unicode.utf8ValidateSlice(rawValue)) {
            try stream.write(rawValue);
        } else {
            const b64encoder = std.base64.standard.Encoder;
            const size = b64encoder.calcSize(rawValue.len);

            const value = try self.allocator.alloc(u8, size);
            defer self.allocator.free(value);

            const encoded = b64encoder.encode(value, rawValue);
            try stream.write(encoded);
        }
    }
};
