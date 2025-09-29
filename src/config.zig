const std = @import("std");

/// Returns iroha's config directory
///
pub fn getConfigDir(allocator: std.mem.Allocator) !std.fs.Dir {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config| {
        var config_dir = blk: {
            const dir = std.fs.openDirAbsolute(xdg_config, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.makeDirAbsolute(xdg_config);
                    break :blk try std.fs.openDirAbsolute(xdg_config, .{});
                },
                else => return err,
            };

            break :blk dir;
        };
        defer config_dir.close();

        config_dir.makeDir("iroha") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return try config_dir.openDir("iroha", .{});
    } else |_| {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
            return err;
        };
        defer allocator.free(home);
        const config_dir_path = try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
        defer allocator.free(config_dir_path);

        var config_dir = blk: {
            const dir = std.fs.openDirAbsolute(config_dir_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try std.fs.makeDirAbsolute(config_dir_path);
                    break :blk try std.fs.openDirAbsolute(config_dir_path, .{});
                },
                else => return err,
            };

            break :blk dir;
        };
        defer config_dir.close();

        return try config_dir.openDir("iroha", .{});
    }
}
