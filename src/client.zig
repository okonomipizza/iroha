const std = @import("std");
const c = @cImport({
    @cInclude("curl/curl.h");
});

pub const Client = struct {
    curl: *c.CURL,
    api_key: []const u8,

    pub fn init(api_key: []const u8) !Client {
        const curl = c.curl_easy_init() orelse return error.CurlInitFailed;
        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, "https://api.anthropic.com/v1/messages");
        // _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
        // _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &response_buf);

        return .{
            .curl = curl,
            .api_key = api_key,
        };
    }

    pub fn deinit(self: *Client) void {
        c.curl_easy_cleanup(self.curl);
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

    pub fn call(self: *Client, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const curl = self.curl;
        const escaped = try jsonEscape(allocator, input);

        const body = try std.fmt.allocPrint(
            allocator,
            \\{{"model":"claude-haiku-4-5","max_tokens":1024,"messages":[{{"role":"user","content":"{s}"}}]}}
        ,
            .{escaped},
        );

        const auth_header = try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{self.api_key});
        var headers: ?*c.curl_slist = null;
        headers = c.curl_slist_append(headers, "Content-Type: application/json");
        headers = c.curl_slist_append(headers, "anthropic-version: 2023-06-01");
        headers = c.curl_slist_append(headers, auth_header.ptr);
        defer c.curl_slist_free_all(headers);

        var ctx = WriteContext{
            .allocator = allocator,
            .list = std.ArrayList(u8){},
        };

        _ = c.curl_easy_setopt(curl, c.CURLOPT_URL, "https://api.anthropic.com/v1/messages");
        const body_z = try allocator.dupeZ(u8, body);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_POSTFIELDS, body_z.ptr);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headers);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEFUNCTION, writeCallback);
        _ = c.curl_easy_setopt(curl, c.CURLOPT_WRITEDATA, &ctx);

        const res = c.curl_easy_perform(curl);
        if (res != c.CURLE_OK) return error.CurlFailed;
        return try extractResponse(allocator, ctx.list.items);
    }

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

    const ContentBlock = struct {
        type: []const u8,
        text: []const u8,
    };

    pub const ClaudeResponse = struct {
        id: []const u8,
        type: []const u8,
        role: []const u8,
        model: []const u8,
        content: []ContentBlock,
        stop_reason: []const u8,
    };

    fn jsonEscape(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var out = std.ArrayList(u8){};
        for (input) |ch| {
            switch (ch) {
                '\n' => try out.appendSlice(allocator, "\\n"),
                '\r' => try out.appendSlice(allocator, "\\r"),
                '\t' => try out.appendSlice(allocator, "\\t"),
                '"' => try out.appendSlice(allocator, "\\\""),
                '\\' => try out.appendSlice(allocator, "\\\\"),
                else => try out.append(allocator, ch),
            }
        }

        return out.toOwnedSlice(allocator);
    }
};
