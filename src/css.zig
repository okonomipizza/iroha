const std = @import("std");
const app_config = @import("config.zig");
const Config = app_config.Config;
const gtk = @import("gtk");
const gdk = @import("gdk");
const AppContext = @import("main.zig").AppContext;

pub fn loadCss(allocator: std.mem.Allocator, config: *const Config, provider: ?*gtk.CssProvider) anyerror!*gtk.CssProvider {
    const css_provider = provider orelse gtk.CssProvider.new();

    const css_data = try generateCssFromConfig(allocator, config);
    defer allocator.free(css_data);
    const css_data_z = try allocator.dupeZ(u8, css_data);
    defer allocator.free(css_data_z);

    gtk.CssProvider.loadFromData(css_provider, css_data_z.ptr, @intCast(css_data_z.len));

    const display = gdk.Display.getDefault() orelse {
        return error.FailedToGetDisplay;
    };

    if (provider == null) {
        gtk.StyleContext.addProviderForDisplay(display, css_provider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    return css_provider;
}

fn generateCssVariables(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const system_color_cfg = try ColorConfig.fromRgba(config.system_config.color);
    const system_colors = try system_color_cfg.generateColorVariants(allocator);

    const launcher_color_cfg = try ColorConfig.fromRgba(config.launcher_config.color);
    const launcher_colors = try launcher_color_cfg.generateColorVariants(allocator);

    const music_color_cfg = try ColorConfig.fromRgba(config.music_config.color);
    const music_colors = try music_color_cfg.generateColorVariants(allocator);

    const message_color_cfg = try ColorConfig.fromRgba(config.message_config.color);
    const message_colors = try message_color_cfg.generateColorVariants(allocator);

    const clock_color_cfg = try ColorConfig.fromRgba(config.clock_config.color);
    const clock_colors = try clock_color_cfg.generateColorVariants(allocator);

    const css = try std.fmt.allocPrint(allocator,
        \\:root {{
        \\    /* Base colors */
        \\    --color-white: #ffffff;
        \\    --color-black: rgba(0, 0, 0, 0.7);
        \\    --color-black-dark: rgba(0, 0, 0, 1.0);
        \\    --color-black-light: rgba(0, 0, 0, 0.2);
        \\    --color-gray: rgba(49, 49, 49, 1);
        \\    --color-transparent: transparent;
        \\    
        \\    --color-system: {s};
        \\    --color-system-light: {s};
        \\    --color-system-medium: {s};
        \\    --color-system-dim: {s};
        \\    --color-system-dimmer: {s};
        \\
        \\    --color-launcher: {s};
        \\    --color-launcher-light: {s};
        \\    --color-launcher-medium: {s};
        \\    --color-launcher-dim: {s};
        \\    --color-launcher-dimmer: {s};
        \\
        \\    --color-music: {s};
        \\    --color-music-light: {s};
        \\    --color-music-medium: {s};
        \\    --color-music-dim: {s};
        \\    --color-music-dimmer: {s};
        \\
        \\    --color-notification: {s};
        \\    --color-notification-light: {s};
        \\    --color-notification-medium: {s};
        \\    --color-notification-dim: {s};
        \\    --color-notification-dimmer: {s};
        \\
        \\    --color-clock: {s};
        \\    --color-clock-light: {s};
        \\    --color-clock-medium: {s};
        \\    --color-clock-dim: {s};
        \\    --color-clock-dimmer: {s};
        \\    
        \\    /* Measurements */
        \\    --border-radius-small: 4px;
        \\    --border-radius-medium: 8px;
        \\    --border-radius-large: 50px;
        \\    --border-radius-xlarge: 70px;
        \\    
        \\    /* Effects */
        \\    --blur-medium: blur(10px);
        \\    --blur-heavy: blur(20px);
        \\    
        \\    /* Transitions */
        \\    --transition-fast: 0.2s ease;
        \\}}        
    , .{
        system_colors.base,
        system_colors.bright,
        system_colors.dim,
        system_colors.light,
        system_colors.dimmer,
        launcher_colors.base,
        launcher_colors.bright,
        launcher_colors.dim,
        launcher_colors.light,
        launcher_colors.dimmer,
        music_colors.base,
        music_colors.bright,
        music_colors.dim,
        music_colors.light,
        music_colors.dimmer,
        message_colors.base,
        message_colors.bright,
        message_colors.dim,
        message_colors.light,
        message_colors.dimmer,
        clock_colors.base,
        clock_colors.bright,
        clock_colors.dim,
        clock_colors.light,
        clock_colors.dimmer,
    });
    return css;
}

fn generateSystemCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    _ = config;
    const css = try std.fmt.allocPrint(allocator,
        \\
        \\button.system-button {{
        \\    color: var(--color-white);
        \\    background: var(--color-transparent);
        \\    border: none;
        \\}}
        \\
        \\button.system-button image {{
        \\    color: var(--color-white);
        \\    -gtk-icon-palette: success var(--color-white);
        \\    transition: all var(--transition-fast);
        \\}}
        \\
        \\button.system-button:hover image {{
        \\    color: var(--color-system-light);
        \\    -gtk-icon-palette: success var(--color-system-light);
        \\}}
        \\
        \\button.system-button.active image {{
        \\    color: var(--color-system-light);
        \\    -gtk-icon-palette: success var(--color-system-light);
        \\}}
        \\
        \\popover.system-menu {{
        \\    background: var(--color-transparent);
        \\    border: none;
        \\    padding: 0;
        \\    margin: 0;
        \\}}
        \\
        \\popover.system-menu > contents {{
        \\    background: var(--color-transparent);
        \\    border: none;
        \\    padding: 0;
        \\    margin: 0;
        \\}}
        \\
        \\.system-menu-box {{
        \\    background-color: var(--color-black-dark);
        \\    backdrop-filter: var(--blur-heavy);
        \\    border: none;
        \\    border-radius: var(--border-radius-medium);
        \\    padding: 8px;
        \\    margin: 0;
        \\    min-width: 250px;
        \\}}
        \\
        \\.system-menu-item {{
        \\    color: var(--color-white);
        \\    background-color: var(--color-transparent);
        \\    background: var(--color-transparent);
        \\    border: none;
        \\    padding: 4px 16px;
        \\    margin: 4px 8px;
        \\    font-size: 12px;
        \\    text-align: left;
        \\    border-radius: var(--border-radius-small);
        \\    transition: background-color var(--transition-fast);
        \\}}
        \\
        \\.system-menu-item:hover {{
        \\    background-color: var(--color-gray);
        \\    color: var(--color-system);
        \\}}
    , .{});
    return css;
}

fn generateMusicCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const css = try std.fmt.allocPrint(allocator,
        \\.music {{
        \\    color: var(--color-white);
        \\    font-size: {d}px;
        \\    min-height: 20px;
        \\    max-height: 20px;
        \\    margin: 2px 6px;
        \\    background-color: var(--color-black-light);
        \\    border: 1px solid var(--color-music);
        \\    border-radius: var(--border-radius-large);
        \\}}
        \\
        \\.music-icon-button {{
        \\    margin-left: 8px;
        \\    margin-right: 2px;
        \\    margin-top: 4px;
        \\    margin-bottom: 4px;
        \\    padding: 0px;
        \\    min-width: 24px;
        \\    min-height: 16px;
        \\    border: 1px solid var(--color-music);
        \\    border-radius: var(--border-radius-xlarge);
        \\    background: var(--color-transparent);
        \\    background-color: var(--color-transparent);
        \\}}
        \\
        \\.music-icon-button:hover {{
        \\    color: var(--color-white);
        \\    border-color: var(--color-music-medium);
        \\    background-color: var(--color-music-light);
        \\}}
        \\
        \\.music-icon {{
        \\    color: var(--color-music);
        \\    padding-left: 4px;
        \\    padding-right: 2px;
        \\    padding-top: 1px;
        \\    padding-bottom: 1px;
        \\    min-width: 16px;
        \\    min-height: 16px;
        \\    -gtk-icon-size: 16px;
        \\}}
    , .{config.music_config.font_size});
    return css;
}

fn generateLauncherCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    _ = config;
    const css = try std.fmt.allocPrint(allocator,
        \\.launcher {{
        \\    color: var(--color-white);
        \\    font-size: 8px;
        \\    min-height: 20px;
        \\    max-height: 20px;
        \\    margin: 2px 6px;
        \\    background-color: var(--color-black-light);
        \\    border: 1px solid var(--color-launcher);
        \\    border-radius: var(--border-radius-large);
        \\}}
        \\
        \\.launcher-app-icon {{
        \\    margin-left: 8px;
        \\    margin-right: 2px;
        \\    margin-top: 4px;
        \\    margin-bottom: 4px;
        \\    padding: 0px;
        \\    min-width: 24px;
        \\    min-height: 16px;
        \\    border: none;
        \\    background: var(--color-transparent);
        \\    background-color: var(--color-transparent);
        \\}}
    , .{});
    return css;
}
fn generateNotificationCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const css = try std.fmt.allocPrint(allocator,
        \\.notification {{
        \\    color: var(--color-white);
        \\    font-size: {d}px;
        \\    min-height: 20px;
        \\    max-height: 20px;
        \\    margin: 2px 6px;
        \\    background-color: var(--color-black-light);
        \\    border: 1px solid var(--color-notification);
        \\    border-radius: var(--border-radius-large);
        \\}}
    , .{config.message_config.font_size});
    return css;
}

fn generateClockCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const css = try std.fmt.allocPrint(allocator,
        \\
        \\.clock,
        \\.clock-button,
        \\button.clock,
        \\button.clock-button {{
        \\    color: var(--color-white);
        \\    font-size: {d}px;
        \\    font-family: monospace;
        \\    background: var(--color-transparent);
        \\    padding: 4px 8px;
        \\    border: none;
        \\    min-height: 20px;
        \\    max-height: 20px;
        \\    margin: 0;
        \\}}
        \\
        \\button.clock:hover {{
        \\    color: var(--color-clock);
        \\}}
        \\
    , .{config.clock_config.font_size});
    return css;
}

fn generateCssFromConfig(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const root_css = try generateCssVariables(allocator, config);
    const system_css = try generateSystemCss(allocator, config);
    const music_css = try generateMusicCss(allocator, config);
    const launcher_css = try generateLauncherCss(allocator, config);
    const notification_css = try generateNotificationCss(allocator, config);
    const clock_css = try generateClockCss(allocator, config);
    const css = try std.fmt.allocPrint(allocator,
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\{s}
        \\.system-bar {{
        \\    background-color: var(--color-black);
        \\    border: none;
        \\    min-height: 24px;
        \\    max-height: 24px;
        \\    padding: 4px 12px;
        \\    margin: 0;
        \\}}
        \\
        \\
    , .{ root_css, system_css, music_css, launcher_css, notification_css, clock_css });

    return css;
}

const ColorConfig = struct {
    r: u8,
    g: u8,
    b: u8,

    const Self = @This();

    pub fn fromRgba(rgba_str: []const u8) !ColorConfig {
        const start = std.mem.indexOf(u8, rgba_str, "(") orelse return error.InvalidFormat;
        const end = std.mem.indexOf(u8, rgba_str, ")") orelse return error.InvalidFormat;

        const content = rgba_str[start + 1 .. end];

        var split_iter = std.mem.splitAny(u8, content, ",");

        const r_str = std.mem.trim(u8, split_iter.next() orelse return error.InvalidFormat, " ");
        const g_str = std.mem.trim(u8, split_iter.next() orelse return error.InvalidFormat, " ");
        const b_str = std.mem.trim(u8, split_iter.next() orelse return error.InvalidFormat, " ");

        const r = try std.fmt.parseInt(u8, r_str, 10);
        const g = try std.fmt.parseInt(u8, g_str, 10);
        const b = try std.fmt.parseInt(u8, b_str, 10);

        return ColorConfig{ .r = r, .g = g, .b = b };
    }

    pub fn toRgba(self: ColorConfig, alpha: f32, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "rgba({d}, {d}, {d}, {d:.1})", .{ self.r, self.g, self.b, alpha });
    }

    fn generateColorVariants(self: Self, allocator: std.mem.Allocator) !struct {
        base: []const u8,
        bright: []const u8,
        dim: []const u8,
        light: []const u8,
        dimmer: []const u8,
    } {
        return .{
            .base = try self.toRgba(0.8, allocator),
            .bright = try self.toRgba(1.0, allocator),
            .dim = try self.toRgba(0.6, allocator),
            .light = try self.toRgba(0.2, allocator),
            .dimmer = try self.toRgba(0.9, allocator),
        };
    }
};
