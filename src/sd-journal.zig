const c_sdjournal = @cImport({
    @cInclude("systemd/sd-journal.h");
});

const ErrnoError = error{Errno};

const std = @import("std");
const Journal = struct {
    j: ?*c_sdjournal.sd_journal = undefined,
    lastError: i32 = 0,

    pub fn seekHead(journal: *Journal) ErrnoError!void {
        const ret = c_sdjournal.sd_journal_seek_head(journal.j);
        if (ret < 0) {
            return journal.errno(ret);
        }
    }

    pub fn seekTail(journal: *Journal) ErrnoError!void {
        const ret = c_sdjournal.sd_journal_seek_tail(journal.j);
        if (ret < 0) {
            return journal.errno(ret);
        }
    }

    pub fn seekCursor(journal: *Journal, cursor: []const u8) ErrnoError!void {
        const ret = c_sdjournal.sd_journal_seek_cursor(journal.j, cursor);
        if (ret < 0) {
            return journal.errno(ret);
        }
    }

    pub fn testCursor(journal: *Journal, cursor: []const u8) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_test_cursor(journal.j, cursor);
        if (ret < 0) {
            return journal.errno(ret);
        }
        return ret > 0;
    }

    pub fn prev(journal: *Journal) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_previous(journal.j);
        if (ret < 0) {
            return journal.errno(ret);
        }
        return ret == 1;
    }

    pub fn next(journal: *Journal) ErrnoError!bool {
        const ret = c_sdjournal.sd_journal_next(journal.j);
        if (ret < 0) {
            return journal.errno(ret);
        }
        return ret == 1;
    }

    pub fn timestamp(journal: *Journal) ErrnoError!u64 {
        var t: u64 = 0;
        const ret = c_sdjournal.sd_journal_get_realtime_usec(journal.j, &t);
        if (ret < 0) {
            return journal.errno(ret);
        }
        return t;
    }

    pub fn cursorAlloc(allocator: std.mem.Allocator, journal: *Journal) ![]u8 {
        var cursorData: [*c]u8 = undefined;
        const ret = c_sdjournal.sd_journal_get_cursor(journal.j, &cursorData);
        defer std.c.free(cursorData);

        if (ret < 0) {
            return journal.errno(ret);
        }

        const slice = std.mem.sliceTo(cursorData, 0);
        const output = try allocator.alloc(u8, slice.len);
        @memcpy(output, slice);
        return output;
    }

    pub fn readNextFieldAlloc(allocator: std.mem.Allocator, journal: *Journal) !?[]u8 {
        var data: ?*anyopaque = undefined;
        var size: usize = 0;
        const ret = c_sdjournal.sd_journal_enumerate_data(journal.j, &data, &size);

        if (ret == 0) {
            return null;
        }
        if (ret < 0) {
            return journal.errno(ret);
        }

        const slice = @as([*]u8, @ptrCast(data))[0..size];
        const output = try allocator.alloc(u8, slice.len);
        @memcpy(output, slice);
        return output;
    }

    pub fn close(journal: *Journal) void {
        c_sdjournal.sd_journal_close(journal.j);
    }

    fn errno(journal: *Journal, val: c_int) ErrnoError {
        journal.lastError = val;
        return ErrnoError.Errno;
    }
};

pub fn openJournal(flags: c_int) Journal {
    var j = Journal{};
    _ = c_sdjournal.sd_journal_open(&(j.j), flags);
    return j;
}
