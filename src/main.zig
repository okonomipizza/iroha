const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const layer_shell = @import("layer_shell.zig");
const gdk = @import("gdk");
const Clock = @import("./widget/clock.zig").Clock;
const SystemMenu = @import("./widget/system.zig").SystemMenu;
const Music = @import("./widget/music.zig").Music;
const Notification = @import("./widget/notification.zig").Notification;
const jsonc = @import("zig_jsonc");
const app_config = @import("config.zig");
const Config = app_config.Config;
const loadCss = @import("css.zig").loadCss;

fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data) |data| {
        const allocator = std.heap.page_allocator;

        const config = @as(*Config, @ptrCast(@alignCast(data)));
        var window = gtk.ApplicationWindow.new(app);
        gtk.Window.setTitle(window.as(gtk.Window), "System Bar");
        gtk.Window.setDefaultSize(window.as(gtk.Window), 200, 10);

        loadCss(allocator, config) catch {
            std.posix.exit(1);
        };

        const style_context = gtk.Widget.getStyleContext(window.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "system-bar");

        // Make window style like system bar
        layer_shell.initForWindow(window);
        layer_shell.setLayer(window, layer_shell.GTK_LAYER_SHELL_LAYER_TOP);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_TOP, true);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_LEFT, true);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_RIGHT, true);
        layer_shell.setExclusiveZone(window, 30);

        var main_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(main_box.as(gtk.Widget), gtk.Align.fill);
        gtk.Widget.setValign(main_box.as(gtk.Widget), gtk.Align.center);
        gtk.Window.setChild(window.as(gtk.Window), main_box.as(gtk.Widget));

        var left_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(left_box.as(gtk.Widget), gtk.Align.start);
        gtk.Widget.setValign(left_box.as(gtk.Widget), gtk.Align.center);

        var right_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(right_box.as(gtk.Widget), gtk.Align.start);
        gtk.Widget.setValign(right_box.as(gtk.Widget), gtk.Align.center);

        // Create clock widget (JST)
        var clock = Clock.new(9);
        var menu = SystemMenu.new();

        var music = Music.new(allocator);

        const clock_style_context = gtk.Widget.getStyleContext(clock.as(gtk.Widget));
        gtk.StyleContext.addClass(clock_style_context, "clock");
        gtk.StyleContext.addClass(clock_style_context, "clock-button");

        const messages = config.message_config.messages;
        const msg_ptr = allocator.create(std.json.Value) catch {
            std.debug.print("Failed to allocate memory for messages\n", .{});
            std.posix.exit(1);
        };
        msg_ptr.* = messages;
        var norification = Notification.new(allocator, msg_ptr) catch {
            std.posix.exit(1);
        };

        gtk.Box.append(left_box, menu.as(gtk.Widget));
        gtk.Box.append(left_box, music.as(gtk.Widget));
        gtk.Box.append(right_box, norification.as(gtk.Widget));
        gtk.Box.append(right_box, clock.as(gtk.Widget));

        gtk.Box.append(main_box, left_box.as(gtk.Widget));

        var spacer = gtk.Box.new(gtk.Orientation.horizontal, 0);
        gtk.Widget.setHexpand(spacer.as(gtk.Widget), 1);
        gtk.Box.append(main_box, spacer.as(gtk.Widget));

        gtk.Box.append(main_box, right_box.as(gtk.Widget));

        gtk.Widget.show(window.as(gtk.Widget));
    }
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    const config = try Config.init(allocator);

    var app = gtk.Application.new("org.iroha.systembar", .{});
    defer app.unref();
    
    const config_ptr = try allocator.create(Config);
    config_ptr.* = config;
    
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, @ptrCast(config_ptr), .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);

    std.process.exit(@intCast(status));
}



