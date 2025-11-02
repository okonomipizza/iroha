const std = @import("std");
const jsonc = @import("zig_jsonc");

const DEFASULT_EXCLUSIVE_ZONE = 30;
const DEFAULT_FONT_SIZE = 12;

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

fn getWidgetFontSize(root: std.json.Value, widget_name: []const u8) ?u8 {
    const widget_root = getWidgetConfig(root, widget_name) orelse return null;
    const font_size = widget_root.object.get("font-size") orelse return null;
    if (font_size == .integer) return @intCast(font_size.integer);
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
    font_size: u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        // default: dark violet
        var text: []const u8 = "rgb(255, 255, 255)";
        var color: []const u8 = "rgb(148, 0, 211)";
        // const font_size: u8 = getWidgetFontSize(config_json, "music") orelse DEFAULT_FONT_SIZE;
        const font_size: u8 = blk: {
            if (getWidgetFontSize(config_json, "music")) |music_fs| {
                break :blk music_fs;
            } else {
                if (getWidgetFontSize(config_json, "iroha")) |bar_fs| {
                    break :blk bar_fs;
                }
                break :blk DEFAULT_FONT_SIZE;
            }
        };

        if (getWidgetThemeObj(config_json, "music")) |music_theme| {
            if (music_theme.object.get("text")) |txt| {
                text = txt.string;
            }
            if (music_theme.object.get("color")) |bc| {
                color = bc.string;
            }
        }
        return .{ .text = text, .color = color, .font_size = font_size };
    }
};

const LauncherConfig = struct {
    text: []const u8,
    color: []const u8,
    font_size: u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        // default: dark violet
        var text: []const u8 = "rgb(255, 255, 255)";
        var color: []const u8 = "rgb(255, 255, 0)";
        const font_size: u8 = blk: {
            if (getWidgetFontSize(config_json, "launcher")) |launcher_fs| {
                break :blk launcher_fs;
            } else {
                if (getWidgetFontSize(config_json, "iroha")) |bar_fs| {
                    break :blk bar_fs;
                }
                break :blk DEFAULT_FONT_SIZE;
            }
        };

        if (getWidgetThemeObj(config_json, "launcher")) |theme| {
            if (theme.object.get("text")) |txt| {
                text = txt.string;
            }
            if (theme.object.get("color")) |bc| {
                color = bc.string;
            }
        }
        return .{ .text = text, .color = color, .font_size = font_size };
    }
};

const MessageConfig = struct {
    // This value must to be an array of string
    messages: std.json.Value,
    text: []const u8,
    color: []const u8,
    font_size: u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        var text: []const u8 = "rgb(255, 255, 255)";
        var color: []const u8 = "rgb(255, 95, 0)";
        const font_size: u8 = getWidgetFontSize(config_json, "messages") orelse DEFAULT_FONT_SIZE;

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
                return .{ .text = text, .color = color, .messages = default, .font_size = font_size };
            }
        }

        return error.InvalidMusicConfig;
    }
};

const ClockConfig = struct {
    font_size: u8,
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

        const font_size: u8 = getWidgetFontSize(config_json, "clock") orelse DEFAULT_FONT_SIZE;
        return .{
            .font_size = font_size,
            .color = color,
        };
    }
};

const BarConfig = struct {
    exclusive_zone: c_int,
    font_size: u8,

    const Self = @This();

    fn init(config_json: std.json.Value) !Self {
        var exclusive_zone: c_int = DEFASULT_EXCLUSIVE_ZONE;
        var font_size: u8 = DEFAULT_FONT_SIZE;

        if (getWidgetConfig(config_json, "iroha")) |iroha| {
            if (iroha != .object) return error.InvalidConfig;
            if (iroha.object.get("exclusive_zone")) |ez| {
                if (ez == .integer) {
                    const value = ez.integer;
                    if (value < std.math.minInt(c_int) or value > std.math.maxInt(c_int)) {
                        return error.ValueOutOfRange;
                    }
                    exclusive_zone = @intCast(value);
                }
            }
            if (iroha.object.get("font-size")) |size| {
                if (size == .integer) {
                    font_size = @intCast(size.integer);
                }
            }
        }
        return .{ .exclusive_zone = exclusive_zone, .font_size = font_size };
    }
};

// App config
pub const Config = struct {
    bar_config: BarConfig,
    system_config: SystemConfig,
    launcher_config: LauncherConfig,
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

        const bar_config = try BarConfig.init(config_json);
        const system_config = try SystemConfig.init(config_json);
        const launcher_config = try LauncherConfig.init(config_json);
        const music_config = try MusicConfig.init(config_json);
        const messages_config = try MessageConfig.init(config_json);
        const clock_config = try ClockConfig.init(config_json);

        return .{
            .bar_config = bar_config,
            .system_config = system_config,
            .launcher_config = launcher_config,
            .music_config = music_config,
            .message_config = messages_config,
            .clock_config = clock_config,
            .parser = jsonc_parser,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parser.deinit();
    }

    pub fn getExclusiveZone(self: Self) c_int {
        return self.bar_config.exclusive_zone;
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
