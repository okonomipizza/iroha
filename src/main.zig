const std = @import("std");
const Io = std.Io;
const Claude = @import("Claude.zig");
const Resources = @import("Resources.zig");

const clap = @import("clap");

const version = std.mem.trim(u8, @embedFile("./.version"), "\r\n");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var stdout_buffer: [65536]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    // Clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Display this help and exit.
        \\-v, --version             Print version.
        \\-l, --log <str>           After chat, history will be save.
        \\-r, --resource <str>...   Path to resource files sent to Claude.
        \\-p, --prompt <str>        Allows setting the request content for Claude.
    );
    var diag = clap.Diagnostic{};
    var result = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer result.deinit();

    // --- Show help ---
    if (result.args.help != 0) {
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});
    }
    // --- Show version ---
    if (result.args.version != 0) {
        try print(stdout_writer, version);
        return try stdout_writer.flush();
    }

    // Get ANTHROPIC_API_KEY from envrionment variables
    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse {
        std.debug.print("ANTHROPIC_API_KEY not found.\nDo 'export ANTHROPIC_API_KEY=<your_api_key>'\n", .{});
        return;
    };

    var input = std.ArrayList(u8){};
    defer input.deinit(gpa);

    if (result.args.prompt) |p| {
        try input.appendSlice(gpa, p);
    }

    // Read stdin into a dynamic buffer chunk by chunk.
    var stdin_buf: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().reader(init.io, &stdin_buf);

    var chunk: [1024]u8 = undefined;
    while (true) {
        const n = try reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        try input.appendSlice(gpa, chunk[0..n]);
    }

    if (input.items.len == 0) {
        std.debug.print("Error: No input provided. Use -p <prompt> or pipe input via stdin.\n", .{});
        return error.NoInput;
    }

    // Collect some resources user input
    var resources = try Resources.init(gpa, init.io, result.args.resource);
    defer resources.deinit(gpa);

    // If thr user specified a log file path, retrieve it.
    const log_path: ?[]const u8 = if (result.args.log) |path| blk: {
        try validateLogFilePath(path);
        break :blk path;
    } else null;

    var claude = try Claude.init(
        gpa,
        api_key,
        init.io,
        .{ .resources = resources, .log_path = log_path },
    );
    defer claude.deinit(gpa);

    const res = try claude.call(gpa, init.io, input.items);
    defer gpa.free(res);

    // Print response from Claude API
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
