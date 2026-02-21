const std = @import("std");
const c = @cImport({
    @cInclude("curl/curl.h");
});
const Resources = @import("Resources.zig");

const Claude = @This();
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

/// Options to configure client behavior.
const ClaudeOption = struct {
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
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            },
        ) catch continue;
        try messages.append(allocator, parsed.value);
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
    list: std.ArrayList(u8),
};

fn writeCallback(ptr: *anyopaque, size: usize, nmemb: usize, userdata: *anyopaque) callconv(.c) usize {
    const ctx: *WriteContext = @ptrCast(@alignCast(userdata));
    const data: [*]u8 = @ptrCast(ptr);
    ctx.list.appendSlice(ctx.allocator, data[0 .. size * nmemb]) catch return 0;
    return size * nmemb;
}

/// Call the Claude API with the message history and the given input.
pub fn call(self: *Claude, allocator: std.mem.Allocator, io: std.Io, input: []const u8) ![]u8 {
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
        \\{{"model":"claude-haiku-4-5","max_tokens":1024,"messages":{s}}}
    ,
        .{messages_json},
    );
    defer allocator.free(body);
    std.debug.print("body: {s}\n", .{body});

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

    var ctx = WriteContext{
        .allocator = allocator,
        .list = std.ArrayList(u8){},
    };
    defer ctx.list.deinit(allocator);

    _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, ANTHROPIC_API_URL);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body_z.ptr);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headers);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
    _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &ctx);

    const res = c.curl_easy_perform(curl);
    if (res != c.CURLE_OK) return error.CurlFailed;

    const response = try extractResponse(allocator, ctx.list.items);

    if (self.log_path) |path| {
        try appendLog(allocator, io, path, input, response);
    }

    return response;
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

const ContentBlock = struct {
    type: []const u8,
    text: []const u8,
};

const Usage = struct {
    input_tokens: u64,
    output_tokens: u64,
};

pub const ClaudeResponse = struct {
    id: []const u8,
    type: []const u8,
    role: []const u8,
    content: []ContentBlock,
    model: []const u8,
    stop_reason: []const u8,
    usage: Usage,
};

fn extractResponse(allocator: std.mem.Allocator, response_text: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(
        ClaudeResponse,
        allocator,
        response_text,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (parsed.value.content.len == 0) return error.EmptyResponse;

    return try allocator.dupe(u8, parsed.value.content[0].text);
}
