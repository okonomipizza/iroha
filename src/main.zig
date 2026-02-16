const std = @import("std");
const Io = std.Io;
const Claude = @import("claude.zig");

const clap = @import("clap");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help Display this help and exit.
        \\-v, --version Print version.
        \\-l, --log <str>  After chat, history will be save.
    );

    var diag = clap.Diagnostic{};
    var result = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer result.deinit();

    // Show help
    if (result.args.help != 0) {
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});
    }
    if (result.args.version != 0) {
        try print(stdout_writer, "0.0.1");
        return try stdout_writer.flush();
    }

    const log_path: ?[]const u8 = if (result.args.log) |path| blk: {
        try validateLogFilePath(path);
        break :blk path;
    } else null;

    // Get ANTHROPIC_API_KEY from envrionment variables
    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse {
        std.debug.print("ANTHROPIC_API_KEY not found.\n", .{});
        return;
    };

    var claude = try Claude.init(arena, api_key, init.io, .{ .log_path = log_path });
    defer claude.deinit(arena);

    // Get some data to be sent from stdin to Claude API.
    var stdin_buf: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().reader(init.io, &stdin_buf);

    // Read stdin into a dynamic buffer chunk by chunk.
    var input = std.ArrayList(u8){};
    var chunk: [1024]u8 = undefined;
    while (true) {
        const n = try reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        try input.appendSlice(arena, chunk[0..n]);
    }

    const res = try claude.call(arena, init.io, input.items);

    var writer = std.Io.Writer.Allocating.init(arena);
    defer writer.deinit();

    try print(stdout_writer, res);

    try stdout_writer.flush(); // Don't forget to flush!
}

fn print(writer: *Io.Writer, response_body: []const u8) Io.Writer.Error!void {
    try writer.print("{s}\n", .{response_body});
}

fn validateLogFilePath(path: []const u8) !void {
    const basename = std.Io.Dir.path.basename(path);
    if (basename.len == 0 or std.mem.eql(u8, basename, ".") or std.mem.eql(u8, basename, "..")) {
        return error.NotAFilePath;
    }
}
