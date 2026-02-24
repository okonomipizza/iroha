const std = @import("std");
const Io = std.Io;
const c = @cImport({
    @cInclude("curl/curl.h");
});
const Resources = @import("Resources.zig");

const Claude = @This();
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const Config = @import("Config.zig");

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

/// Options to configure client behavior.
const ClaudeOption = struct {
    config: Config,
    log_path: ?[]const u8 = null,
    resources: *Resources,
};

/// We use curl to query the Anthropic API.
curl: *c.CURL,
/// Anthropic API key.
/// Export "ANTHROPIC_API_KEY=<your_key>" before running.
api_key: []const u8,
/// Paths to resource files that sent to api
resources: *Resources,
/// If log_path is provided via options, the client loads message history from the log file.
log: ?[]Message,
/// Path to log file.
log_path: ?[]const u8 = null,
io: std.Io,
/// App config
config: Config,

/// Initialize a Claude client.
pub fn init(allocator: std.mem.Allocator, api_key: []const u8, io: std.Io, option: ClaudeOption) !Claude {
    const curl = c.curl_easy_init() orelse return error.CurlInitFailed;

    var log: ?[]Message = null;
    if (option.log_path) |path| {
        log = try loadLog(allocator, io, path);
    }

    return .{
        .curl = curl,
        .api_key = api_key,
        .resources = option.resources,
        .log = log,
        .log_path = option.log_path,
        .io = io,
        .config = option.config,
    };
}

/// Load message history from a JSON Lines (.jsonl) file.
fn loadLog(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]Message {
    // Validate file extension
    const extension = std.Io.Dir.path.extension(path);
    if (!std.mem.eql(u8, ".jsonl", extension)) return error.InvalidLogFileExtension;

    const cwd = std.Io.Dir.cwd();
    const text = std.Io.Dir.readFileAlloc(cwd, io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer allocator.free(text);

    var messages: std.ArrayList(Message) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(
            Message,
            allocator,
            line,
            .{
                .ignore_unknown_fields = true,
            },
        ) catch continue;
        defer parsed.deinit();

        try messages.append(allocator, .{
            .role = try allocator.dupe(u8, parsed.value.role),
            .content = try allocator.dupe(u8, parsed.value.content),
        });
    }

    return messages.toOwnedSlice(allocator);
}

fn appendLog(allocator: std.mem.Allocator, io: std.Io, path: []const u8, input: []const u8, response: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    var file = cwd.openFile(io, path, .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(io, path, .{}),
        else => return err,
    };
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var w = file.writer(io, &buf);

    // Seek to end.
    const stat = try file.stat(io);
    try w.seekTo(stat.size);

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    try aw.writer.print("{f}\n", .{std.json.fmt(Message{ .role = "user", .content = input }, .{})});
    try aw.writer.print("{f}\n", .{std.json.fmt(Message{ .role = "assistant", .content = response }, .{})});

    try w.interface.writeAll(aw.written());
    try w.flush();
}

pub fn deinit(self: *Claude, allocator: std.mem.Allocator) void {
    c.curl_easy_cleanup(self.curl);
    if (self.log) |log| {
        for (log) |msg| {
            allocator.free(msg.role);
            allocator.free(msg.content);
        }
        allocator.free(log);
    }
}

const WriteContext = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(u8),
    accumulated: std.ArrayList(u8),
    writer: *Io.Writer,

    pub fn init(allocator: std.mem.Allocator, writer: *Io.Writer) WriteContext {
        return .{
            .allocator = allocator,
            .pending = std.ArrayList(u8){},
            .accumulated = std.ArrayList(u8){},
            .writer = writer,
        };
    }

    pub fn deinit(self: *WriteContext) void {
        self.pending.deinit(self.allocator);
        self.accumulated.deinit(self.allocator);
    }
};

const TextDelta = struct {
    type: []const u8 = "",
    text: []const u8 = "",
};

const ContentDelta = struct {
    type: []const u8 = "",
    delta: ?TextDelta = null,
};

fn extractStreamDelta(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(
        ContentDelta,
        allocator,
        json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (std.mem.eql(u8, parsed.value.type, "content_block_delta")) {
        if (parsed.value.delta) |delta| {
            if (std.mem.eql(u8, delta.type, "text_delta")) {
                return allocator.dupe(u8, delta.text);
            }
        }
    }
    return allocator.dupe(u8, "");
}

fn writeCallback(ptr: *anyopaque, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const ctx: *WriteContext = @ptrCast(@alignCast(userdata));
    const data: [*]u8 = @ptrCast(ptr);
    ctx.pending.appendSlice(ctx.allocator, data[0 .. size * nmemb]) catch return 0;

    while (true) {
        const buf = ctx.pending.items;
        const newline_pos = std.mem.indexOfScalar(u8, buf, '\n') orelse break;
        const line = std.mem.trimEnd(u8, buf[0..newline_pos], "\r");

        if (std.mem.startsWith(u8, line, "data: ")) {
            const json_part = line["data: ".len..];
            if (!std.mem.eql(u8, json_part, "[DONE]")) {
                if (extractStreamDelta(ctx.allocator, json_part)) |text| {
                    defer ctx.allocator.free(text);
                    if (text.len > 0) {
                        ctx.writer.print("{s}", .{text}) catch {};
                        ctx.writer.flush() catch {};
                        ctx.accumulated.appendSlice(ctx.allocator, text) catch {};
                    }
                } else |_| {}
            }
        }

        const remaining = ctx.pending.items[newline_pos + 1 ..];
        std.mem.copyForwards(u8, ctx.pending.items, remaining);
        ctx.pending.items.len = remaining.len;
    }

    return size * nmemb;
}

/// Call the Claude API with the message history and the given input.
pub fn call(self: *Claude, writer: *Io.Writer, allocator: std.mem.Allocator, io: std.Io, input: []const u8) !void {
    // Include resources as contents
    var content_aw = std.Io.Writer.Allocating.init(allocator);
    defer content_aw.deinit();

    try content_aw.writer.writeAll(input);

    if (self.resources.paths.items.len > 0) {
        var metadata_list = try self.resources.getFileContent(allocator, self.io);
        defer {
            for (metadata_list.items) |data| {
                data.deinit(allocator);
            }
            metadata_list.deinit(allocator);
        }

        try content_aw.writer.writeAll("\n\n---\n\n");
        for (metadata_list.items) |metadata| {
            try content_aw.writer.print("{s}\n\n{s}\n\n", .{ metadata.path, metadata.content });
        }
    }

    const full_content = try content_aw.toOwnedSlice();
    defer allocator.free(full_content);

    // Create 'messages' to be sent to api
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    try aw.writer.writeByte('[');
    if (self.log) |log| {
        for (log) |msg| {
            try aw.writer.print("{f},", .{std.json.fmt(msg, .{})});
        }
    }
    const new_msg = Message{ .role = "user", .content = full_content };
    try aw.writer.print("{f}", .{std.json.fmt(new_msg, .{})});
    try aw.writer.writeAll("\n\n");
    try aw.writer.writeByte(']');

    const messages_json = try aw.toOwnedSlice();
    defer allocator.free(messages_json);

    const body = try std.fmt.allocPrint(
        allocator,
        \\{{"model":"{s}","max_tokens":1024,"stream":true,"messages":{s}}}
    ,
        .{ self.config.model, messages_json },
    );
    defer allocator.free(body);

    // Null-terminate the body for curl.
    const body_z = try allocator.dupeZ(u8, body);
    defer allocator.free(body_z);

    const curl = self.curl;
    const auth_header = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{self.api_key});
    var headers: ?*c.curl_slist = null;
    headers = c.curl_slist_append(headers, auth_header.ptr);
    headers = c.curl_slist_append(headers, "anthropic-version: 2023-06-01");
    headers = c.curl_slist_append(headers, "Content-Type: application/json");
    defer {
        allocator.free(auth_header);
        c.curl_slist_free_all(headers);
    }

    var ctx = WriteContext.init(allocator, writer);
    defer ctx.deinit();

    _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, ANTHROPIC_API_URL);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body_z.ptr);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headers);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &ctx);

    const res = c.curl_easy_perform(curl);
    if (res != c.CURLE_OK) return error.CurlFailed;

    if (self.log_path) |path| {
        try appendLog(allocator, io, path, input, ctx.accumulated.items);
    }
}

fn appendResources(self: *Claude, allocator: std.mem.Allocator, aw: *std.Io.Writer.Allocating, resources: *Resources) !void {
    const metadata_list = try resources.getFileContent(allocator, self.io);
    try aw.writer.writeAll("\\n---\\n");
    for (metadata_list.items) |metadata| {
        try aw.writer.writeAll(metadata.path);
        try aw.writer.writeAll(metadata.content);
        try aw.writer.writeAll("\\n");
    }
}
