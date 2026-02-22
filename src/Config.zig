pub const std = @import("std");

pub const Config = @This();

app_dir: []const u8,
config_file: []const u8,
log_dir: []const u8,

pub fn init(io: std.Io, allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !Config {
    const xdg = environ_map.get("XDG_CONFIG_HOME");
    const app_config_home = xdg orelse blk: {
        const home = environ_map.get("HOME") orelse return error.HomeNotFound;
        break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
    };
    defer if (xdg == null) allocator.free(app_config_home);

    const app_dir = try std.fs.path.join(allocator, &.{ app_config_home, "iroha" });
    errdefer allocator.free(app_dir);
    const config_file = try std.fs.path.join(allocator, &.{ app_config_home, "iroha", "config.jsonc" });
    errdefer allocator.free(config_file);
    const log_dir = try std.fs.path.join(allocator, &.{ app_config_home, "iroha", "logs" });
    errdefer allocator.free(log_dir);

    std.Io.Dir.createDirAbsolute(io, app_dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.Io.Dir.createDirAbsolute(io, log_dir, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    return .{
        .app_dir = app_dir,
        .config_file = config_file,
        .log_dir = log_dir,
    };
}

const LogFileOption = struct {
    latest: bool = false,
};

pub fn getLogFilePath(self: Config, io: std.Io, allocator: std.mem.Allocator, option: LogFileOption) ![]const u8 {
    const log_path: []const u8 = if (option.latest) blk: {
        // Get path to latest log file.
        var log_dir = try std.Io.Dir.openDirAbsolute(io, self.log_dir, .{ .iterate = true });
        defer log_dir.close(io);

        var iter = log_dir.iterate();
        var latest_name: ?[]const u8 = null;
        while (try iter.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (latest_name == null or std.mem.order(u8, entry.name, latest_name.?) == .gt) {
                latest_name = entry.name;
            }
        }
        const name = latest_name orelse try self.createNewLogFile(io, allocator);
        break :blk try std.Io.Dir.path.join(allocator, &.{ self.log_dir, name });
    } else blk: {
        break :blk try self.createNewLogFile(io, allocator);
    };

    return log_path;
}

fn createNewLogFile(self: Config, io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var threaded_io: std.Io.Threaded = .init_single_threaded;
    const io_thread = threaded_io.io();
    defer threaded_io.deinit();
    const timestamp = std.Io.Clock.now(.awake, io_thread).toNanoseconds();

    const log_filename = try std.fmt.allocPrint(allocator, "{d}.jsonl", .{timestamp});
    defer allocator.free(log_filename);
    const new_log_path = try std.fs.path.join(allocator, &.{ self.log_dir, log_filename });

    const file = try std.Io.Dir.createFileAbsolute(io, new_log_path, .{});
    file.close(io);

    return new_log_path;
}

pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
    allocator.free(self.app_dir);
    allocator.free(self.config_file);
    allocator.free(self.log_dir);
}
