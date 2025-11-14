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
// const Notification = @import("./widget/notification.zig").Notification;
const jsonc = @import("zig_jsonc");
const app_config = @import("config.zig");
const Config = app_config.Config;
const loadCss = @import("css.zig").loadCss;
const Launcher = @import("./launcher/launcher.zig").Launcher;

pub const AppContext = struct {
    arena: *std.heap.ArenaAllocator,
    config: *Config,
    css_provider: ?*gtk.CssProvider = null,
    window: ?*gtk.ApplicationWindow = null,
    // notification: ?*Notification = null,
    music: ?*Music = null,
    clock: ?*Clock = null,
    system_menu: ?*SystemMenu = null,

    pub fn allocator(self: *AppContext) std.mem.Allocator {
        return self.arena.allocator();
    }
};


fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data) |data| {
        const ctx = @as(*AppContext, @ptrCast(@alignCast(data)));

        var window = gtk.ApplicationWindow.new(app);
        gtk.Window.setTitle(window.as(gtk.Window), "System Bar");
        gtk.Window.setDefaultSize(window.as(gtk.Window), 200, 10);

        ctx.window = window;
        ctx.css_provider = loadCss(ctx.allocator(), ctx.config, ctx.css_provider) catch {
            std.posix.exit(1);
        };

        const style_context = gtk.Widget.getStyleContext(window.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "system-bar");

        // Make window style like system bar
        layer_shell.setupLayerShell(window, ctx.config);

        // Build window component
        buildUI(window, ctx);

        gtk.Widget.show(window.as(gtk.Widget));
    }
}

fn buildUI(window: *gtk.ApplicationWindow, ctx: *AppContext) void {
    var main_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
    gtk.Widget.setHalign(main_box.as(gtk.Widget), gtk.Align.fill);
    gtk.Widget.setValign(main_box.as(gtk.Widget), gtk.Align.center);
    gtk.Window.setChild(window.as(gtk.Window), main_box.as(gtk.Widget));

    var left_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
    gtk.Widget.setHalign(left_box.as(gtk.Widget), gtk.Align.start);
    gtk.Widget.setValign(left_box.as(gtk.Widget), gtk.Align.center);

    var spacer = gtk.Box.new(gtk.Orientation.horizontal, 0);
    gtk.Widget.setHexpand(spacer.as(gtk.Widget), 1);

    var right_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
    gtk.Widget.setHalign(right_box.as(gtk.Widget), gtk.Align.start);
    gtk.Widget.setValign(right_box.as(gtk.Widget), gtk.Align.center);

    // Create system menu component for controlling system and app
    var menu = SystemMenu.new(ctx);
    // Create music player control component
    var music = Music.new(ctx.allocator());

    var launcher = Launcher.new(ctx.allocator()) catch {
        std.posix.exit(1);
    };
    
    // var norification = Notification.new(ctx.allocator(), ctx.config);
    // Create clock component (JST)
    var clock = Clock.new(9);

    gtk.Box.append(left_box, menu.as(gtk.Widget));
    gtk.Box.append(left_box, launcher.as(gtk.Widget));
    gtk.Box.append(right_box, music.as(gtk.Widget));
    gtk.Box.append(right_box, clock.as(gtk.Widget));

    gtk.Box.append(main_box, left_box.as(gtk.Widget));
    gtk.Box.append(main_box, spacer.as(gtk.Widget));
    gtk.Box.append(main_box, right_box.as(gtk.Widget));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const config_ptr = try arena.allocator().create(Config);
    config_ptr.* = try Config.init(arena.allocator());

    const ctx = try arena.allocator().create(AppContext);
    ctx.* = .{
        .arena = &arena,
        .config = config_ptr,
    };

    var app = gtk.Application.new("org.iroha.systembar", .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, @ptrCast(ctx), .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}
