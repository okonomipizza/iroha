const std = @import("std");
const Io = std.Io;
const Claude = @import("Claude.zig");
const Resources = @import("Resources.zig");
const Config = @import("Config.zig");

const clap = @import("clap");
const jsonc = @import("jsonc");

/// Version string shared across zig and nix builds, managed in .version file.
const version = std.mem.trim(u8, @embedFile("./.version"), "\r\n");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Load config directory.
    // If the config directory does not exist,
    // it will be created in $HOME/.config/iroha.
    var iroha_config = try Config.init(init.io, gpa, init.environ_map);
    defer iroha_config.deinit(gpa);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    // Clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Display this help and exit.
        \\-v, --version             Print version.
        \\-n, --new                 Start new conversation. New chat log file will be created.
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
        try stdout_writer.print("{s}\n", .{version});
        return try stdout_writer.flush();
    }

    // With --new: create a new log file and start a fresh session.
    // Witout --new: resume the latest existing conversation.
    const log_path = if (result.args.new != 0) blk: {
        break :blk try iroha_config.getLogFilePath(init.io, gpa, .{});
    } else blk: {
        break :blk try iroha_config.getLogFilePath(init.io, gpa, .{ .latest = true });
    };
    defer gpa.free(log_path);

    // Get ANTHROPIC_API_KEY from envrionment variables
    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse {
        std.debug.print("ANTHROPIC_API_KEY not found.\nDo 'export ANTHROPIC_API_KEY=<your_api_key>'\n", .{});
        return;
    };

    // Collect input data from stdin and -p
    var input = std.ArrayList(u8){};
    defer input.deinit(gpa);
    if (result.args.prompt) |p| {
        try input.appendSlice(gpa, p);
        try input.append(gpa, '\n');
    }
    // Read stdin only if it's piped (not a tty)
    const is_not_tty = !try std.Io.File.stdin().isTty(init.io);
    if (is_not_tty) {
        var stdin_buf: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().reader(init.io, &stdin_buf);
        var chunk: [1024]u8 = undefined;
        while (true) {
            const n = try reader.interface.readSliceShort(&chunk);
            if (n == 0) break;
            try input.appendSlice(gpa, chunk[0..n]);
        }
    }

    if (input.items.len == 0 and result.args.resource.len == 0) {
        std.debug.print("Error: No input provided. Use -p <prompt>, pipe via stdin, or specify resources with -r.\n", .{});
        return error.NoInput;
    }

    // Collect some resources user input
    var resources = try Resources.init(gpa, init.io, result.args.resource);
    defer resources.deinit(gpa);

    var claude = try Claude.init(
        gpa,
        api_key,
        init.io,
        .{ .config = iroha_config, .resources = resources, .log_path = log_path },
    );
    defer claude.deinit(gpa);

    claude.call(stdout_writer, gpa, init.io, input.items) catch |err| {
        std.debug.print("Error occurred while calling API: {}\n", .{err});
        std.process.exit(1);
    };

    // Delete old log files to stay within the max_log lilmit.
    // Configure max_log in $HOME/.config/iroha/config.jsonc
    // {
    //   "max_log": 100
    // }
    try iroha_config.deleteOldLogFiles(init.io, gpa);
}
