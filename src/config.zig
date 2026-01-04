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
    background: []const u8 = "rgba(0, 0, 0, 0.95)",
    surface: []const u8 = "rgba(18, 18, 18, 0.95)",
    foreground: []const u8 = "#ffffff",

    @"font-family": []const u8 = "sans-serif",
    @"font-size": i32 = 9,

    @"clock-color": []const u8 = "#ffffff",
};

pub fn init() Config {
    return .{};
}
