const std = @import("std");
const print = std.debug.print;

fn clear_input(in_reader: anytype) !void {
    try in_reader.skipUntilDelimiterOrEof('\n');
}

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Siema, podaj nickname, max 16 znakuf> ", .{});
    var buf: [16]u8 = undefined;
    var read: ?[]u8 = null;

    while (read == null) {
        if (stdin.readUntilDelimiterOrEof(&buf, '\n')) |_read| {
            read = _read;
        } else |err| if (err == error.StreamTooLong) {
            try stdout.print("K***O, 16 ZNAKÓW MAX POWIEDZIAŁEM DO C***A\n", .{});
            try stdout.print("Jeszcze raz> ", .{});
            try clear_input(stdin);
        } else {
            return err;
        }
    }

    try stdout.print("Witaj, {s}\n", .{read.?});
}
