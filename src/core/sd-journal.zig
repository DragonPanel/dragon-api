const std = @import("std");
const c_sdjournal = @cImport({
    @cInclude("systemd/sd-journal.h");
});
const c_errno = @cImport({
    @cInclude("errno.h");
});

pub const ErrnoError = error{Errno};
threadlocal var lastOpenError: i32 = 0;

pub fn getLastOpenError() i32 {
    return lastOpenError;
}

pub const Journal = struct {
    j: ?*c_sdjournal.sd_journal = undefined,
    lastError: i32 = 0,

    pub fn seekHead(self: *Journal) ErrnoError!void {
        const ret = c_sdjournal.sd_journal_seek_head(self.j);
        if (ret < 0) {
            return self.errno(ret);
        }
    }

    pub fn seekTail(self: *Journal) ErrnoError!void {
        const ret = c_sdjournal.sd_journal_seek_tail(self.j);
        if (ret < 0) {
            return self.errno(ret);
        }
    }

    pub fn seekCursor(self: *Journal, allocator: std.mem.Allocator, cursor: []const u8) !void {
        // I need to pass to sd_journal_seek_cursor null terminated string
        const nullTerminatedCursor: [:0]u8 = try allocator.allocSentinel(u8, cursor.len, 0);
        defer allocator.free(nullTerminatedCursor);
        @memcpy(nullTerminatedCursor, cursor);

        const ret = c_sdjournal.sd_journal_seek_cursor(self.j, @ptrCast(nullTerminatedCursor));
        if (ret < 0) {
            return self.errno(ret);
        }
    }

    pub fn testCursor(self: *Journal, cursor: []const u8) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_test_cursor(self.j, cursor);
        if (ret < 0) {
            return self.errno(ret);
        }
        return ret > 0;
    }

    pub fn prev(self: *Journal) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_previous(self.j);
        if (ret < 0) {
            return self.errno(ret);
        }
        return ret == 1;
    }

    pub fn next(self: *Journal) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_next(self.j);
        if (ret < 0) {
            return self.errno(ret);
        }
        return ret == 1;
    }

    pub fn timestamp(self: *Journal) ErrnoError!u64 {
        var t: u64 = 0;
        const ret = c_sdjournal.sd_journal_get_realtime_usec(self.j, &t);
        if (ret < 0) {
            return self.errno(ret);
        }
        return t;
    }

    pub fn cursorAlloc(self: *Journal, allocator: std.mem.Allocator) ![]u8 {
        var cursorData: [*c]u8 = undefined;
        const ret = c_sdjournal.sd_journal_get_cursor(self.j, &cursorData);
        defer std.c.free(cursorData);

        if (ret < 0) {
            return self.errno(ret);
        }

        const slice = std.mem.sliceTo(cursorData, 0);
        const output = try allocator.alloc(u8, slice.len);
        @memcpy(output, slice);
        return output;
    }

    pub fn readNextFieldAlloc(self: *Journal, allocator: std.mem.Allocator) !?[]u8 {
        var data: ?*anyopaque = undefined;
        var size: usize = 0;
        const ret = c_sdjournal.sd_journal_enumerate_data(self.j, &data, &size);

        if (ret == 0) {
            return null;
        }
        if (ret < 0) {
            return self.errno(ret);
        }

        const slice = @as([*]u8, @ptrCast(data))[0..size];
        const output = try allocator.alloc(u8, slice.len);
        @memcpy(output, slice);
        return output;
    }

    pub fn readFieldAlloc(self: *Journal, allocator: std.mem.Allocator, field: []const u8) !?[]u8 {
        var data: ?*anyopaque = undefined;

        // I need to pass to sd_journal_get_data null terminated string.
        const nullTerminatedField: [:0]u8 = try allocator.allocSentinel(u8, field.len, 0);
        defer allocator.free(nullTerminatedField);
        @memcpy(nullTerminatedField, field);

        var size: usize = 0;
        const ret = c_sdjournal.sd_journal_get_data(self.j, @ptrCast(nullTerminatedField.ptr), &data, &size);

        if (ret < 0) {
            if (ret == -c_errno.ENOENT) {
                return null; // Not found
            }
            return self.errno(ret);
        }

        const slice = @as([*]u8, @ptrCast(data))[0..size];
        const output = try allocator.alloc(u8, slice.len);
        @memcpy(output, slice);
        return output;
    }

    pub fn addMatch(self: *Journal, allocator: std.mem.Allocator, field: []const u8, value: []const u8) !void {
        var match = try allocator.alloc(u8, field.len + value.len + 1);
        defer allocator.free(match);
        @memcpy(match[0..field.len], field);
        @memcpy(match[field.len .. field.len + 1], "=");
        @memcpy(match[field.len + 1 ..], value);

        const ret = c_sdjournal.sd_journal_add_match(self.j, @ptrCast(match), match.len);

        if (ret < 0) {
            return self.errno(ret);
        }
    }

    pub fn close(self: *Journal) void {
        c_sdjournal.sd_journal_close(self.j);
    }

    pub fn errno(self: *Journal, val: c_int) ErrnoError {
        self.lastError = val;
        std.debug.print("Shaise: {s}\n", .{c_sdjournal.strerror(-val)});
        return ErrnoError.Errno;
    }
};

pub fn openJournal(flags: c_int) ErrnoError!Journal {
    var j = Journal{};
    const ret = c_sdjournal.sd_journal_open(&(j.j), flags);

    if (ret < 0) {
        lastOpenError = ret;
        return ErrnoError.Errno;
    }

    return j;
}
