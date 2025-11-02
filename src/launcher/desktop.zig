const std = @import("std");

/// This parser can parse .desktop file
pub const DotDesktopParser = struct {
    input: []const u8,
    map: *std.StringHashMap([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !Self {
        const map = try allocator.create(std.StringHashMap([]const u8));
        map.* = std.StringHashMap([]const u8).init(allocator);
        try parse(input, map);
        return .{ .input = input, .map = map };
    }

    pub fn deinit(self: *Self, allcator: std.mem.Allocator) void {
        self.map.deinit();
        allcator.destroy(self.map);
    }

    fn parse(input: []const u8, map: *std.StringHashMap([]const u8)) !void {
        var line_iter = std.mem.splitScalar(u8, input, '\n');
        while (line_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            // Skip empty line and comments
            if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '[') continue;

            var words = std.mem.splitScalar(u8, trimmed, '=');
            if (words.next()) |key| {
                if (words.next()) |value| {
                    try map.put(key, value);
                }
            }
        }
    }

    pub fn getValue(self: Self, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }
};

const testing = std.testing;

test "parse .desktop" {
    const allocator = testing.allocator;
    const input =
        \\[Desktop Entry]
        \\Name=Iroha
        \\Terminal=false
    ;

    var parser = try DotDesktopParser.init(allocator, input);
    defer parser.deinit(allocator);

    try testing.expectEqualStrings("Iroha", parser.getValue("Name").?);
}
