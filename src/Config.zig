pub const std = @import("std");
const jsonc = @import("jsonc");

pub const Config = @This();

app_dir: []const u8,
config_file: []const u8,
log_dir: []const u8,
max_log: ?u64,

model: []const u8 = DEFAULT_MODEL,

pub fn init(io: std.Io, allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !Config {
    const xdg = environ_map.get("XDG_CONFIG_HOME");
    const app_config_home = xdg orelse blk: {
        const home = environ_map.get("HOME") orelse return error.HomeNotFound;
        break :blk try std.fs.path.join(allocator, &.{ home, ".config" });
    };
    defer if (xdg == null) allocator.free(app_config_home);

    const app_dir_path = try std.fs.path.join(allocator, &.{ app_config_home, "iroha" });
    errdefer allocator.free(app_dir_path);
    const config_file_path = try std.fs.path.join(allocator, &.{ app_config_home, "iroha", "config.jsonc" });
    errdefer allocator.free(config_file_path);
    const log_dir_path = try std.fs.path.join(allocator, &.{ app_config_home, "iroha", "logs" });
    errdefer allocator.free(log_dir_path);

    std.Io.Dir.createDirAbsolute(io, app_dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.Io.Dir.createDirAbsolute(io, log_dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const config_file = std.Io.Dir.createFileAbsolute(io, config_file_path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => null,
        else => return err,
    };
    if (config_file) |f| f.close(io);

    var app_dir = try std.Io.Dir.openDirAbsolute(io, app_dir_path, .{});
    defer app_dir.close(io);

    const config_src = try std.Io.Dir.readFileAlloc(app_dir, io, "config.jsonc", allocator, .unlimited);
    defer allocator.free(config_src);

    var cfg_parsed: ?std.json.Parsed(std.json.Value) = null;
    defer if (cfg_parsed) |c| c.deinit();

    if (config_src.len > 0) {
        var jsonc_parser = jsonc.Jsonc.init(config_src);
        defer jsonc_parser.deinit();

        cfg_parsed = try jsonc_parser.parse(std.json.Value, allocator, .{});
    }

    const model = if (cfg_parsed) |p| blk: {
        if (p.value.object.get("model")) |m| {
            if (m == .string) {
                break :blk try allocator.dupe(u8, m.string);
            }
        }
        break :blk try allocator.dupe(u8, DEFAULT_MODEL);
    } else blk: {
        break :blk try allocator.dupe(u8, DEFAULT_MODEL);
    };

    const max_log: ?u64 = if (cfg_parsed) |p|
        if (p.value.object.get("max_log")) |m|
            if (m == .integer) @intCast(m.integer) else null
        else
            null
    else
        null;

    return .{
        .app_dir = app_dir_path,
        .config_file = config_file_path,
        .log_dir = log_dir_path,
        .model = model,
        .max_log = max_log,
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

/// User can determine max number of logs.
pub fn deleteOldLogFiles(self: Config, io: std.Io, allocator: std.mem.Allocator) !void {
    // Nothing to do if max_log is not configured.
    const max_log = self.max_log orelse return;

    var log_dir = try std.Io.Dir.openDirAbsolute(io, self.log_dir, .{ .iterate = true });
    defer log_dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    var iter = log_dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    if (names.items.len > max_log) {
        const to_delete = names.items[0 .. names.items.len - max_log];
        for (to_delete) |name| {
            const path = try std.Io.Dir.path.join(allocator, &.{ self.log_dir, name });
            defer allocator.free(path);
            try std.Io.Dir.deleteFileAbsolute(io, path);
        }
    }
}

pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
    allocator.free(self.app_dir);
    allocator.free(self.config_file);
    allocator.free(self.log_dir);
    allocator.free(self.model);
}

const DEFAULT_MODEL = "claude-haiku-4-5-20251001";

const valid_models = &[_][]const u8{
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-opus-4-5-20251101",
    "claude-haiku-4-5-20251001",
    "claude-sonnet-4-5-20250929",
    "claude-opus-4-1-20250805",
    "claude-opus-4-20250514",
    "claude-sonnet-4-20250514",
    "claude-3-haiku-20240307",
};

fn validateModel(model: []const u8) !void {
    for (valid_models) |valid| {
        if (std.mem.eql(u8, model, valid)) return;
    }
    return error.InvalidModel;
}
