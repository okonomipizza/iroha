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
