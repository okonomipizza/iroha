const std = @import("std");
const gtk = @import("gtk");
const gdk = @import("gdk");
const Config = @import("config.zig");

extern "c" fn gtk_layer_init_for_window(window: *anyopaque) void;
extern "c" fn gtk_layer_set_layer(window: *anyopaque, layer: c_int) void;
extern "c" fn gtk_layer_set_anchor(window: *anyopaque, edge: c_int, anchor_to_edge: c_int) void;
extern "c" fn gtk_layer_set_exclusive_zone(window: *anyopaque, exclusive_zone: c_int) void;

pub const GTK_LAYER_SHELL_LAYER_BACKGROUND: c_int = 0;
pub const GTK_LAYER_SHELL_LAYER_BOTTOM: c_int = 1;
pub const GTK_LAYER_SHELL_LAYER_TOP: c_int = 2;
pub const GTK_LAYER_SHELL_LAYER_OVERLAY: c_int = 3;

pub const GTK_LAYER_SHELL_EDGE_LEFT: c_int = 0;
pub const GTK_LAYER_SHELL_EDGE_RIGHT: c_int = 1;
pub const GTK_LAYER_SHELL_EDGE_TOP: c_int = 2;
pub const GTK_LAYER_SHELL_EDGE_BOTTOM: c_int = 3;

pub fn initForWindow(window: *gtk.ApplicationWindow) void {
    gtk_layer_init_for_window(@ptrCast(window));
}

pub fn setLayer(window: *gtk.ApplicationWindow, layer: c_int) void {
    gtk_layer_set_layer(@ptrCast(window), layer);
}

pub fn setAnchor(window: *gtk.ApplicationWindow, edge: c_int, anchor_to_edge: bool) void {
    gtk_layer_set_anchor(@ptrCast(window), edge, if (anchor_to_edge) 1 else 0);
}

pub fn setExclusiveZone(window: *gtk.ApplicationWindow, exclusive_zone: c_int) void {
    gtk_layer_set_exclusive_zone(@ptrCast(window), exclusive_zone);
}

pub fn setupLayerShell(window: *gtk.ApplicationWindow, config: *Config) void {
    initForWindow(window);
    setLayer(window, GTK_LAYER_SHELL_EDGE_TOP);
    setLayer(window, GTK_LAYER_SHELL_LAYER_TOP);
    setAnchor(window, GTK_LAYER_SHELL_EDGE_TOP, true);
    setAnchor(window, GTK_LAYER_SHELL_EDGE_LEFT, true);
    setAnchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, true);

    setExclusiveZone(window, config.bar.@"exclusive-zone");
}
