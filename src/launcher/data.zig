const std = @import("std");
const testing = std.testing;

// ディレクトリを検索作成
// ファイルを検索作成
// ファイルは30行まで
// １行１アプリ
// 頻度をmapで
/// iroha_history
const AppLaunchStats = struct {
    app_name: []const u8,
    launch_count: usize,
};

const AppLaunchManager = struct {
    stats: std.ArrayList(AppLaunchStats),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const manager = try allocator.create(Self);
        const list = try std.ArrayList(AppLaunchStats).initCapacity(allocator, 10);
        manager.* = .{ .stats = list, .allocator = allocator };
        try manager.sort();
        return manager;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self.allocator;
        self.stats.deinit(allocator);
        allocator.destroy(self);
    }

    /// Sorts by launch_count in descending order
    fn sort(self: *Self) !void {
        if (self.length() == 0) return; // empty list

        var i: usize = 0;
        while (i < self.length() - 1) : (i += 1) {
            var c = i;
            while (c < self.length() - 1) : (c += 1) {
                const n = c + 1;
                const current = self.stats.items[c];
                const next = self.stats.items[n];

                // swap items
                if (current.launch_count < next.launch_count) {
                    self.stats.items[c] = next;
                    self.stats.items[n] = current;
                }
            }
        }
    }

    fn length(self: *const Self) usize {
        return self.stats.items.len;
    }
};

test "AppLaunchManager.sort - sorts by launch_count in descending order" {
    const allocator = testing.allocator;

    var manager = try AppLaunchManager.init(allocator);
    defer manager.deinit();

    // test data
    try manager.stats.append(allocator, .{ .app_name = "Browser", .launch_count = 5 });
    try manager.stats.append(allocator, .{ .app_name = "Editor", .launch_count = 10 });
    try manager.stats.append(allocator, .{ .app_name = "Terminal", .launch_count = 3 });
    try manager.stats.append(allocator, .{ .app_name = "Message", .launch_count = 8 });

    try manager.sort();

    try testing.expectEqual(@as(usize, 10), manager.stats.items[0].launch_count);
    try testing.expectEqualStrings("Editor", manager.stats.items[0].app_name);

    try testing.expectEqual(@as(usize, 8), manager.stats.items[1].launch_count);
    try testing.expectEqualStrings("Message", manager.stats.items[1].app_name);

    try testing.expectEqual(@as(usize, 5), manager.stats.items[2].launch_count);
    try testing.expectEqualStrings("Browser", manager.stats.items[2].app_name);

    try testing.expectEqual(@as(usize, 3), manager.stats.items[3].launch_count);
    try testing.expectEqualStrings("Terminal", manager.stats.items[3].app_name);
}
