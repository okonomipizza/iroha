const std = @import("std");
const testing = std.testing;

const AppLaunchStats = struct {
    app_name: []const u8,
    launch_count: usize,
};

const AppLaunchManager = struct {
    stats: std.ArrayList(AppLaunchStats),
    allocator: std.mem.Allocator,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        return initWithDir(allocator, null);
    }

    pub fn initWithDir(allocator: std.mem.Allocator, test_dir: ?std.fs.Dir) !*Self {
        var data_dir = if (test_dir) |dir| dir else try getDataDir(allocator);
        const should_close = test_dir == null;
        defer if (should_close) data_dir.close();

        const file_name = "iroha_launcher";

        var file = data_dir.openFile(file_name, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var new_file = try data_dir.createFile(file_name, .{});
                const initial_data = "";
                try new_file.writeAll(initial_data);
                try new_file.sync();
                new_file.close();

                break :blk try data_dir.openFile(file_name, .{ .mode = .read_only });
            },
            else => return err,
        };
        defer file.close();

        const file_size = try file.getEndPos();

        const msgs_buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(msgs_buffer);

        var reader = file.reader(msgs_buffer);
        const messages = try reader.interface.readAlloc(allocator, file_size);
        defer allocator.free(messages);

        const manager = try allocator.create(Self);

        const list = try readAppData(allocator, messages);
        manager.* = .{ .stats = list, .allocator = allocator };
        try manager.sort();
        return manager;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self.allocator;
        for (self.stats.items) |stat| {
            allocator.free(stat.app_name);
        }
        self.stats.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn readAppData(allocator: std.mem.Allocator, input: []u8) !std.ArrayList(AppLaunchStats) {
        var map = std.StringHashMap(usize).init(allocator);
        defer {
            var key_iter = map.keyIterator();
            while (key_iter.next()) |key| {
                allocator.free(key.*);
            }
            map.deinit();
        }

        var line_iter = std.mem.splitScalar(u8, input, '\n');
        while (line_iter.next()) |line| {
            const app_name_slice = std.mem.trim(u8, line, " \t\r");
            if (app_name_slice.len == 0) continue;

            if (map.getKey(app_name_slice)) |existing_key| {
                const old_value = map.get(existing_key).?;
                try map.put(existing_key, old_value + 1);
            } else {
                const app_name_owned = try allocator.dupe(u8, app_name_slice);
                try map.put(app_name_owned, 1);
            }
        }

        var list = try std.ArrayList(AppLaunchStats).initCapacity(allocator, 10);
        var iter = map.iterator();

        while (iter.next()) |entry| {
            const app_name = try allocator.dupe(u8, entry.key_ptr.*);
            const count = entry.value_ptr.*;
            try list.append(allocator, AppLaunchStats{ .app_name = app_name, .launch_count = count });
        }

        return list;
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

    pub fn appendAppName(allocator: std.mem.Allocator, app_name: []const u8) !void {
        var data_dir = try getDataDir(allocator);
        defer data_dir.close();

        const file_name = "iroha_launcher";

        var file = data_dir.openFile(file_name, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => {
                var new_file = try data_dir.createFile(file_name, .{});
                try new_file.writeAll(app_name);
                try new_file.writeAll("\n");
                try new_file.sync();
                new_file.close();
                return;
            },
            else => return err,
        };
        defer file.close();

        try file.seekFromEnd(0);

        try file.writeAll(app_name);
        try file.writeAll("\n");
        try file.sync();
    }
};

/// Returns app data directory
/// App data storaged at XDG_DATA_HOME
pub fn getDataDir(allocator: std.mem.Allocator) !std.fs.Dir {
    if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg_data| {
        var data_dir = blk: {
            const dir = std.fs.openDirAbsolute(xdg_data, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.makeDirAbsolute(xdg_data);
                    break :blk try std.fs.openDirAbsolute(xdg_data, .{});
                },
                else => return err,
            };

            break :blk dir;
        };
        defer data_dir.close();

        data_dir.makeDir("iroha") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return try data_dir.openDir("iroha", .{});
    } else |_| {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);

        const data_dir_path = try std.fmt.allocPrint(allocator, "{s}/.local/share", .{home});
        defer allocator.free(data_dir_path);

        var data_dir = blk: {
            const dir = std.fs.openDirAbsolute(data_dir_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.makeDirAbsolute(data_dir_path);
                    break :blk try std.fs.openDirAbsolute(data_dir_path, .{});
                },
                else => return err,
            };

            break :blk dir;
        };
        defer data_dir.close();

        data_dir.makeDir("iroha") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return try data_dir.openDir("iroha", .{});
    }
}

test "AppLaunchManager.sort - sorts by launch_count in descending order" {
    const allocator = testing.allocator;

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const input =
        \\ Browser
        \\ Editor
        \\ Editor
        \\ Terminal
        \\ Terminal
        \\ Terminal
        \\ Message
        \\ Message
        \\ Message
        \\ Message
    ;

    const file = try temp.dir.createFile("iroha_launcher", .{});
    defer file.close();
    try file.writeAll(input);
    try file.sync();

    var manager = try AppLaunchManager.initWithDir(allocator, temp.dir);
    defer manager.deinit();

    try manager.sort();

    try testing.expectEqual(@as(usize, 4), manager.stats.items[0].launch_count);
    try testing.expectEqualStrings("Message", manager.stats.items[0].app_name);

    try testing.expectEqual(@as(usize, 3), manager.stats.items[1].launch_count);
    try testing.expectEqualStrings("Terminal", manager.stats.items[1].app_name);

    try testing.expectEqual(@as(usize, 2), manager.stats.items[2].launch_count);
    try testing.expectEqualStrings("Editor", manager.stats.items[2].app_name);

    try testing.expectEqual(@as(usize, 1), manager.stats.items[3].launch_count);
    try testing.expectEqualStrings("Browser", manager.stats.items[3].app_name);
}

test "AppLaunchManager.sort - handles empty list" {
    const allocator = testing.allocator;

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const input = "";

    const file = try temp.dir.createFile("iroha_launcher", .{});
    defer file.close();
    try file.writeAll(input);
    try file.sync();

    var manager = try AppLaunchManager.initWithDir(allocator, temp.dir);
    defer manager.deinit();

    try manager.sort();

    try testing.expectEqual(@as(usize, 0), manager.length());
}

test "AppLaunchManager.sort - handles single item" {
    const allocator = testing.allocator;

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const input =
        \\ Terminal
        \\ Terminal
        \\ Terminal
    ;

    const file = try temp.dir.createFile("iroha_launcher", .{});
    defer file.close();
    try file.writeAll(input);
    try file.sync();

    var manager = try AppLaunchManager.initWithDir(allocator, temp.dir);
    defer manager.deinit();

    try manager.sort();

    try testing.expectEqual(@as(usize, 1), manager.length());
    try testing.expectEqual(@as(usize, 3), manager.stats.items[0].launch_count);
}

test "AppLaunchManager.sort - handles equal launch_counts" {
    const allocator = testing.allocator;

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const input =
        \\ App1
        \\ App2
        \\ App3
    ;
    const file = try temp.dir.createFile("iroha_launcher", .{});
    defer file.close();
    try file.writeAll(input);
    try file.sync();

    var manager = try AppLaunchManager.initWithDir(allocator, temp.dir);
    defer manager.deinit();

    try manager.sort();

    try testing.expectEqual(@as(usize, 3), manager.length());
}

test "AppLaunchManager.sort - already sorted list" {
    const allocator = testing.allocator;

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const input =
        \\ App1
        \\ App1
        \\ App1
        \\ App1
        \\ App1
        \\ App1
        \\ App1
        \\ App2
        \\ App2
        \\ App2
        \\ App2
        \\ App3
        \\ App3
        \\ App3
    ;

    const file = try temp.dir.createFile("iroha_launcher", .{});
    defer file.close();
    try file.writeAll(input);
    try file.sync();

    var manager = try AppLaunchManager.initWithDir(allocator, temp.dir);
    defer manager.deinit();

    try manager.sort();

    try testing.expectEqual(@as(usize, 7), manager.stats.items[0].launch_count);
    try testing.expectEqual(@as(usize, 4), manager.stats.items[1].launch_count);
    try testing.expectEqual(@as(usize, 3), manager.stats.items[2].launch_count);
}
