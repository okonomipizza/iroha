const std = @import("std");

pub const Config = @This();

bar: BarConfig = .{},
theme: ThemeConfig = .{},

pub const BarConfig = struct {
    height: i32 = 30,
    @"exclusive-zone": c_int = 15,
    margin: MarginConfig = .{},
    spacing: i32 = 2,
};

pub const MarginConfig = struct {
    top: i32 = 3,
    bottom: i32 = 5,
    left: i32 = 5,
    right: i32 = 5,
};

pub const ThemeConfig = struct {
    background: []const u8 = "#1e1e2e",
    background_darker: []const u8 = "#191924",
    foreground: []const u8 = "#ffffff",
    @"font-family": []const u8 = "sans-serif",
    @"font-size": i32 = 9,

    @"clock-color": []const u8 = "#ffffff",

    // Menu specific colors
    @"menu-backgroung": []const u8 = "rgba(40, 40, 50, 0.95)",
    @"menu-hover": []const u8 = "rgba(137, 180, 250, 0.2)",
    @"menu-active": []const u8 = "#89b4fa",
    @"menu-border": []const u8 = "rgba(255, 255, 255, 0.1)",
};

pub fn init() Config {
    return .{};
}

pub fn getWidgetBackground(self: ThemeConfig, allocator: std.mem.Allocator) ![]const u8 {
    return RGB.getDarkerColor(allocator, self.background, 0.85);
}

pub fn getDeeperBackground(self: ThemeConfig, allocator: std.mem.Allocator) ![]const u8 {
    return RGB.getDarkerColor(allocator, self.background, 0.7);
}

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
    a: f32 = 1.0,

    pub fn fromHex(hex: []const u8) !RGB {
        var color = hex;

        // Remove '#'
        if (color[0] == '#') {
            color = color[1..];
        }

        if (color.len == 6) {
            const r = try std.fmt.parseInt(u8, color[0..2], 16);
            const g = try std.fmt.parseInt(u8, color[2..4], 16);
            const b = try std.fmt.parseInt(u8, color[4..6], 16);
            return RGB{ .r = r, .g = g, .b = b, .a = 1.0 };
        } else if (color.len == 8) {
            // #rrggbbaa
            const r = try std.fmt.parseInt(u8, color[0..2], 16);
            const g = try std.fmt.parseInt(u8, color[2..4], 16);
            const b = try std.fmt.parseInt(u8, color[4..6], 16);
            const a = try std.fmt.parseInt(u8, color[6..8], 16);
            return RGB{ .r = r, .g = g, .b = b, .a = @as(f32, @floatFromInt(a)) / 255.0 };
        }

        return error.InvalidHexColor;
    }

    pub fn fromRgba(rgba: []const u8) !RGB {
        // "rgba(40, 40, 50, 0.95)" -> "40, 40, 50, 0.95"
        const start = std.mem.indexOf(u8, rgba, "(") orelse return error.InvalidRgbaFormat;
        const end = std.mem.indexOf(u8, rgba, ")") orelse return error.InvalidRgbaFormat;
        const values = rgba[start + 1 .. end];

        var iter = std.mem.split(u8, values, ",");

        const r_str = std.mem.trim(u8, iter.next() orelse return error.InvalidRgbaFormat, " ");
        const g_str = std.mem.trim(u8, iter.next() orelse return error.InvalidRgbaFormat, " ");
        const b_str = std.mem.trim(u8, iter.next() orelse return error.InvalidRgbaFormat, " ");
        const a_str = std.mem.trim(u8, iter.next() orelse return error.InvalidRgbaFormat, " ");

        const r = try std.fmt.parseInt(u8, r_str, 10);
        const g = try std.fmt.parseInt(u8, g_str, 10);
        const b = try std.fmt.parseInt(u8, b_str, 10);
        const a = try std.fmt.parseFloat(f32, a_str);

        return RGB{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn darken(self: RGB, factor: f32) RGB {
        const f = std.math.clamp(factor, 0.0, 1.0);
        return RGB{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * f),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * f),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * f),
            .a = self.a,
        };
    }

    pub fn lighten(self: RGB, factor: f32) RGB {
        const f = @max(factor, 1.0);
        return RGB{
            .r = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.r)) * f))),
            .g = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.g)) * f))),
            .b = @min(255, @as(u8, @intFromFloat(@as(f32, @floatFromInt(self.b)) * f))),
            .a = self.a,
        };
    }

    pub fn toCssString(self: RGB, allocator: std.mem.Allocator) ![]const u8 {
        if (self.a >= 0.999) {
            return try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
        } else {
            return try std.fmt.allocPrint(allocator, "rgba({d}, {d}, {d}, {d:.2})", .{ self.r, self.g, self.b, self.a });
        }
    }

    pub fn getDarkerColor(allocator: std.mem.Allocator, color_str: []const u8, factor: f32) ![]const u8 {
        var rgb: RGB = undefined;

        if (std.mem.startsWith(u8, color_str, "rgba(") or std.mem.startsWith(u8, color_str, "rgb(")) {
            rgb = try RGB.fromRgba(color_str);
        } else if (std.mem.startsWith(u8, color_str, "#")) {
            rgb = try RGB.fromHex(color_str);
        } else {
            return error.UnsupportedColorFormat;
        }

        const darker = rgb.darken(factor);
        return try darker.toCssString(allocator);
    }
};
