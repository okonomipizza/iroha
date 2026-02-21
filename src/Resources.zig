const std = @import("std");

pub const Resources = @This();

/// Paths to resource files
paths: std.ArrayList([]const u8),

/// Initialize Resources by searching for each file name recursively from cwd.
/// Users can specify file names without full paths; the file contents will be
/// included in the query sent to the Claude API.
pub fn init(allocator: std.mem.Allocator, io: std.Io, paths: []const []const u8) !*Resources {
    const resources = try allocator.create(Resources);
    var list = std.ArrayList([]const u8){};
    for (paths) |path| {
        const file_path = try getFilePath(allocator, path, io);
        if (file_path) |fp| {
            try list.append(allocator, fp);
        }
    }
    resources.paths = list;
    return resources;
}

pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
    for (self.paths.items) |path| {
        allocator.free(path);
    }
    self.paths.deinit(allocator);
    allocator.destroy(self);
}

/// Recursively search for a file by name starting from cwd.
/// Returns the relative path if found, or null if not found.
fn getFilePath(allocator: std.mem.Allocator, file_name: []const u8, io: std.Io) !?[]const u8 {
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.eql(u8, entry.basename, file_name)) {
            return try allocator.dupe(u8, entry.path);
        }
    }

    return null;
}

const ResourceMetaData = struct {
    path: []const u8,
    content: []const u8,

    pub fn deinit(self: ResourceMetaData, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }
};

/// Caller must free after returned value is used
pub fn getFileContent(self: *Resources, allocator: std.mem.Allocator, io: std.Io) !std.ArrayList(ResourceMetaData) {
    const cwd = std.Io.Dir.cwd();

    var resource_list = std.ArrayList(ResourceMetaData){};
    errdefer resource_list.deinit(allocator);

    for (self.paths.items) |path| {
        const text = try std.Io.Dir.readFileAlloc(cwd, io, path, allocator, .unlimited);
        try resource_list.append(allocator, .{ .path = path, .content = text });
    }

    return resource_list;
}
