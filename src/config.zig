const std = @import("std");
const jsonc = @import("zig_jsonc");

fn getWidgetConfig(root: std.json.Value, widget_name: []const u8) ?std.json.Value {
    if (root != .object) return null;
    if (root.object.get(widget_name)) |widget_config| {
        if (widget_config != .object) return null;
        return widget_config;
    }
    return null;
}

fn getWidgetThemeObj(root: std.json.Value, widget_name: []const u8) ?std.json.Value {
    const widget_root = getWidgetConfig(root, widget_name) orelse return null;
    const widget_theme = widget_root.object.get("theme") orelse return null;
    if (widget_theme == .object) return widget_theme;
    return null;
}

/// For power control
const SystemConfig = struct {
    color: []const u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        // default: dark violet
        var color: []const u8 = "rgb(148, 0, 211)";

        if (getWidgetThemeObj(config_json, "system")) |music_theme| {
            if (music_theme.object.get("color")) |bc| {
                color = bc.string;
            }
        }
        return .{
            .color = color,
        };
    }
};
const MusicConfig = struct {
    text: []const u8,
    color: []const u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        // default: dark violet
        var text: []const u8 = "rgb(255, 255, 255)";
        var color: []const u8 = "rgb(148, 0, 211)";

        if (getWidgetThemeObj(config_json, "music")) |music_theme| {
            if (music_theme.object.get("text")) |txt| {
                text = txt.string;
            }
            if (music_theme.object.get("color")) |bc| {
                color = bc.string;
            }
        }
        return .{
            .text = text,
            .color = color,
        };
    }
};

const MessageConfig = struct {
    // This value must to be an array of string
    messages: std.json.Value,
    text: []const u8,
    color: []const u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        var text: []const u8 = "rgb(255, 255, 255)";
        var color: []const u8 = "rgb(255, 95, 0)";

        if (getWidgetThemeObj(config_json, "messages")) |messages_theme| {
            if (messages_theme.object.get("text")) |txt| {
                text = txt.string;
            }
            if (messages_theme.object.get("color")) |bc| {
                color = bc.string;
            }
        }
        if (config_json.object.get("messages")) |messages| {
            if (messages != .object) {
                return error.InvalidMessages;
            }

            if (messages.object.get("default")) |default| {
                return .{ 
                    .text = text,
                    .color = color,
                    .messages = default };
            }
        }

        return error.InvalidMusicConfig;
    }
};

const ClockConfig = struct {
    color: []const u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        // default: dark violet
        var color: []const u8 = "rgb(255, 255, 255)";

        if (getWidgetThemeObj(config_json, "clock")) |color_theme| {
            if (color_theme.object.get("color")) |c| {
                color = c.string;
            }
        }
        return .{
            .color = color,
        };
    }
};

// App config
pub const Config = struct {
    system_config: SystemConfig,
    music_config: MusicConfig,
    message_config: MessageConfig,
    clock_config: ClockConfig,
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

        const system_config = try SystemConfig.init(config_json);
        const music_config = try MusicConfig.init(config_json);
        const messages_config = try MessageConfig.init(config_json);
        const clock_config = try ClockConfig.init(config_json);

        return .{
            .system_config = system_config,
            .music_config = music_config,
            .message_config = messages_config,
            .clock_config = clock_config,
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
