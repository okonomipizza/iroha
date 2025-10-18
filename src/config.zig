const std = @import("std");
const jsonc = @import("zig_jsonc");

const MusicConfig = struct {
    color: []const u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        if (config_json != .object) {
            return error.InvalidMusicConfig;
        }
        if (config_json.object.get("music")) |music| {
            if (music != .object) {
                return error.InvalidMusic;
            }
            if (music.object.get("theme")) |theme| {
                if (theme != .object) {
                    return error.InvalidMusicTheme;
                }
                if (theme.object.get("border-color")) |border_color| {
                    return .{ .color = border_color.string };
                }
            }
        }
        return error.InvalidMusicConfig;
    }
};

const MessageConfig = struct {
    // This value must to be an array of string
    messages: std.json.Value,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        if (config_json != .object) {
            return error.InvalidMusicConfig;
        }
        if (config_json.object.get("messages")) |messages| {
            if (messages != .object) {
                return error.InvalidMessages;
            }
            if (messages.object.get("default")) |default| {
                return .{ .messages = default };
            }
        }
        return error.InvalidMusicConfig;
    }
};

// App config
pub const Config = struct {
    music_config: MusicConfig,
    message_config: MessageConfig,
    parser: jsonc.JsoncParser,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var iroha_dir = try getConfigDir(allocator);
        defer iroha_dir.close();

        const file_name = "iroha.jsonc";

        var file = iroha_dir.openFile(file_name, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                var new_file = try iroha_dir.createFile(file_name, .{});
                const initial_data =
                    \\{
                    \\    "music": {
                    \\        "theme": {
                    \\            "border-color": "#8a2be2"
                    \\        },
                    \\    },
                    \\    "messages": [
                    \\        "kick back",
                    \\        "iris out",
                    \\        "jane doe",
                    \\        ]
                    \\}
                ;
                try new_file.writeAll(initial_data);
                try new_file.sync();
                new_file.close();

                break :blk try iroha_dir.openFile(file_name, .{ .mode = .read_only });
            },
            else => return err,
        };
        defer file.close();

        const file_size = try file.getEndPos();

        const msgs_buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(msgs_buffer);

        var reader = file.reader(msgs_buffer);
        const messages = try reader.interface.readAlloc(allocator, file_size);

        var jsonc_parser = try jsonc.JsoncParser.init(allocator, messages);

        const config_json = try jsonc_parser.parse();
        if (config_json != .object) return error.InvalidConfig;

        const music_config = try MusicConfig.init(config_json);
        const messages_config = try MessageConfig.init(config_json);

        return .{
            .music_config = music_config,
            .message_config = messages_config,
            .parser = jsonc_parser,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
    }
};

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
