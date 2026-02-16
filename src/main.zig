const std = @import("std");
const Io = std.Io;
const Client = @import("client.zig").Client;
// const c = @cImport({
//     @cInclude("curl/curl.h");
// });

const pai = @import("pai");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // Get ANTHROPIC_API_KEY from envrionment variables
    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse {
        std.debug.print("ANTHROPIC_API_KEY not found.\n", .{});
        return;
    };

    var client = try Client.init(api_key);
    defer client.deinit();

    // Get some data to be sent from stdin to Claude API.
    var stdin_buf: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().reader(init.io, &stdin_buf);

    // Read stdin into a dynamic buffer chunk by chunk.
    var input = std.ArrayList(u8){};
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = try reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        try input.appendSlice(arena, chunk[0..n]);
    }
    std.debug.print("{s}\n", .{input.items});

    const res = try client.call(arena, input.items);
    std.debug.print("{s}\n", .{res});

    // Accessing command line arguments:
    // const args = try init.minimal.args.toSlice(arena);
    // for (args) |arg| {
    //     std.log.info("arg: {s}", .{arg});
    // }

    // In order to do I/O operations need an `Io` instance.

    // var writer = std.Io.Writer.Allocating.init(arena);
    // defer writer.deinit();

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    // var stdout_buffer: [1024]u8 = undefined;
    // var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    // const stdout_writer = &stdout_file_writer.interface;

    // try pai.printAnotherMessage(stdout_writer);

    // try stdout_writer.flush(); // Don't forget to flush!
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
