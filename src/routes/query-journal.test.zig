const ht = @import("httpz").testing;
const queryJournal = @import("query-journal.zig").queryJournal;

test "query-journal without query parameters should return 200" {
    var web_test = ht.init(.{});
    defer web_test.deinit();

    try queryJournal(web_test.req, web_test.res);
    try web_test.expectStatus(200);
}
