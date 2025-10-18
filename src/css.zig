const std = @import("std");
const app_config = @import("config.zig");
const Config = app_config.Config;
const gtk = @import("gtk");
const gdk = @import("gdk");

pub fn loadCss(allocator: std.mem.Allocator, config: *const Config) anyerror!void {
    const provider = gtk.CssProvider.new();
    const css_data = try generateCssFromConfig(allocator, config); 
    defer allocator.free(css_data);
    const css_data_z = try allocator.dupeZ(u8, css_data);
    defer allocator.free(css_data_z);

    gtk.CssProvider.loadFromData(provider, css_data_z.ptr, @intCast(css_data_z.len));

    const display = gdk.Display.getDefault() orelse {
        return error.FailedToGetDisplay;
    };

    gtk.StyleContext.addProviderForDisplay(display, provider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
}

fn generateCssVariables(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const color_config = try ColorConfig.fromRgba(config.music_config.color);
    const music_colors = try color_config.generateColorVariants(allocator);

    // const clock_color_config = try ColorConfig.fromRgba(config.music_config.color);
    // const clock_colors = try clock_color_config.generateColorVariants(allocator);
    
    const css = try std.fmt.allocPrint(allocator,
        \\:root {{
        \\    /* Base colors */
        \\    --color-white: #ffffff;
        \\    --color-black: rgba(0, 0, 0, 0.7);
        \\    --color-black-dark: rgba(0, 0, 0, 0.8);
        \\    --color-black-light: rgba(0, 0, 0, 0.2);
        \\    --color-transparent: transparent;
        \\    
        \\    /* Accent colors */
        \\    --color-green: rgba(173, 255, 47, 0.8);
        \\    --color-green-bright: rgba(173, 255, 47, 1.0);
        \\    --color-green-dim: rgba(173, 255, 47, 0.6);
        \\    --color-green-light: rgba(173, 255, 47, 0.2);
        \\    --color-green-dimmer: rgba(173, 255, 47, 0.9);
        \\    
        \\    --color-orange: rgba(255, 95, 0, 1.0);
        \\    --color-orange-light: rgba(255, 95, 0, 0.2);
        \\    --color-orange-medium: rgba(255, 95, 0, 0.3);
        \\    --color-orange-dim: rgba(255, 95, 0, 0.6);
        \\    --color-orange-dimmer: rgba(255, 95, 0, 0.9);
        \\
        \\    --color-music: {s};
        \\    --color-music-bright: {s};
        \\    --color-music-dim: {s};
        \\    --color-music-light: {s};
        \\    --color-music-dimmer: {s};
        \\
        \\    --color-clock: rgba(0,255,255, 1.0);
        \\    --color-clock-bright: rgba(0, 255, 255, 0.2);
        \\    --color-clock-dim: rgba(0, 255, 255, 0.2);
        \\    --color-clock-light: rgba(0, 255, 255, 0.2);
        \\    --color-clock-dimmer: rgba(0, 255, 255, 0.2);
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
        music_colors.base,
        music_colors.bright,
        music_colors.dim,
        music_colors.light,
        music_colors.dimmer,
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
        \\    color: var(--color-green-bright);
        \\    -gtk-icon-palette: success var(--color-green-bright);
        \\}}
    , .{});
    return css;
}
fn generateMusicCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    _ = config;
    const css = try std.fmt.allocPrint(allocator,
        \\.music {{
        \\    color: var(--color-white);
        \\    font-size: 12px;
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
        \\    color: var(--color-music-bright);
        \\    border-color: var(--color-music-dimmer);
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
    , .{});
    return css;
}

fn generateClockCss(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    _ = config;
    const css = try std.fmt.allocPrint(allocator,
        \\
        \\.clock,
        \\.clock-button,
        \\button.clock,
        \\button.clock-button {{
        \\    color: var(--color-white);
        \\    font-size: 12px;
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
    , .{});
    return css;
}
fn generateCssFromConfig(allocator: std.mem.Allocator, config: *const Config) ![]const u8 {
    const root_css = try generateCssVariables(allocator, config);
    const system_css = try generateSystemCss(allocator, config);
    const music_css = try generateMusicCss(allocator, config);
    const clock_css = try generateClockCss(allocator, config);
    const css = try std.fmt.allocPrint(allocator,
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
        \\.notification {{
        \\    color: var(--color-white);
        \\    font-size: 12px;
        \\    min-height: 20px;
        \\    max-height: 20px;
        \\    margin: 2px 6px;
        \\    background-color: var(--color-black-light);
        \\    border: 1px solid var(--color-orange-dim);
        \\    border-radius: var(--border-radius-large);
        \\}}
        \\
        \\.notification-icon-button {{
        \\    margin-left: 8px;
        \\    margin-right: 2px;
        \\    margin-top: 4px;
        \\    margin-bottom: 4px;
        \\    padding: 0px;
        \\    min-width: 24px;
        \\    min-height: 16px;
        \\    border: 1px solid var(--color-orange-dim);
        \\    border-radius: var(--border-radius-xlarge);
        \\    background: var(--color-transparent);
        \\    background-color: var(--color-transparent);
        \\}}
        \\
        \\.notification-icon-button:hover {{
        \\    color: var(--color-green-bright);
        \\    border-color: var(--color-orange-dimmer);
        \\    background-color: var(--color-orange-light);
        \\}}
        \\
        \\.notification-icon {{
        \\    color: var(--color-orange);
        \\    padding-left: 4px;
        \\    padding-right: 2px;
        \\    padding-top: 1px;
        \\    padding-bottom: 1px;
        \\    min-width: 16px;
        \\    min-height: 16px;
        \\    -gtk-icon-size: 16px;
        \\}}
        \\
        \\popover.notification-menu {{
        \\    background: var(--color-transparent);
        \\    border: none;
        \\    padding: 0;
        \\    margin: 0;
        \\}}
        \\
        \\popover.notification-menu > contents {{
        \\    background: var(--color-transparent);
        \\    border: none;
        \\    padding: 0;
        \\    margin: 0;
        \\}}
        \\
        \\.notification-menu-box {{
        \\    background-color: var(--color-black-dark);
        \\    backdrop-filter: var(--blur-heavy);
        \\    border: none;
        \\    border-radius: var(--border-radius-medium);
        \\    padding: 8px, 8px;
        \\    margin: 0;
        \\    min-width: 250px;
        \\}}
        \\
        \\.notification-menu-item {{
        \\    color: var(--color-white);
        \\    background-color: var(--color-transparent);
        \\    background: var(--color-transparent);
        \\    backdrop-filter: var(--blur-heavy);
        \\    border: none;
        \\    padding: 4px 16px;
        \\    margin: 4px 8px;
        \\    font-size: 12px;
        \\    text-align: left;
        \\    display: block;
        \\    border-radius: var(--border-radius-small);
        \\    transition: background-color var(--transition-fast);
        \\}}
        \\
        \\.notification-menu-item:hover {{
        \\    background-color: var(--color-green-light);
        \\    color: var(--color-green);
        \\}}
    , .{root_css, system_css, music_css, clock_css});

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

        return ColorConfig{.r = r, .g = g, .b = b};
    }

    pub fn toRgba(self: ColorConfig, alpha: f32, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "rgba({d}, {d}, {d}, {d:.1})", .{ self.r, self.g, self.b, alpha});
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
        // \\button.power-button {{
        // \\    background: var(--color-transparent);
        // \\    background-color: var(--color-transparent);
        // \\    border: none;
        // \\    color: var(--color-white);
        // \\    transition: color var(--transition-fast), background-color var(--transition-fast);
        // \\}}
        // \\
        // \\button.power-button:hover:not(.active) {{
        // \\    color: var(--color-green);
        // \\}}
        // \\
        // \\button.power-button.active {{
        // \\    color: var(--color-green);
        // \\    background-color: var(--color-green-light);
        // \\    border: 1px solid var(--color-green-dim);
        // \\    border-radius: var(--border-radius-small);
        // \\}}
        // \\
        // \\button.power-button.active:hover {{
        // \\    background-color: var(--color-green-medium);
        // \\    border-color: var(--color-green-dimmer);
        // \\}}
        // \\
        // \\popover.power-menu {{
        // \\    background: var(--color-transparent);
        // \\    border: none;
        // \\    padding: 0;
        // \\    margin: 0;
        // \\}}
        // \\
        // \\popover.power-menu > contents {{
        // \\    background: var(--color-transparent);
        // \\    border: none;
        // \\    padding: 0;
        // \\    margin: 0;
        // \\}}
        // \\
        // \\.power-menu-box {{
        // \\    background-color: var(--color-black-dark);
        // \\    backdrop-filter: var(--blur-heavy);
        // \\    border: none;
        // \\    border-radius: var(--border-radius-medium);
        // \\    padding: 8px, 8px;
        // \\    margin: 0;
        // \\    min-width: 250px;
        // \\}}
        // \\
        // \\.power-menu-item {{
        // \\    color: var(--color-white);
        // \\    background-color: var(--color-transparent);
        // \\    background: var(--color-transparent);
        // \\    backdrop-filter: var(--blur-heavy);
        // \\    border: none;
        // \\    padding: 4px 16px;
        // \\    margin: 4px 8px;
        // \\    font-size: 12px;
        // \\    text-align: left;
        // \\    display: block;
        // \\    border-radius: var(--border-radius-small);
        // \\    transition: background-color var(--transition-fast);
        // \\}}
        // \\
        // \\.power-menu-item:hover {{
        // \\    background-color: var(--color-green-light);
        // \\    color: var(--color-green);
        // \\}}
