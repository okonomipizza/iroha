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
const jsonc = @import("zig_jsonc");
const Config = @import("config.zig");
const loadCss = @import("css.zig").loadCss;
const Launcher = @import("./launcher/launcher.zig").Launcher;

const AppData = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    config: Config,
    css_provider: ?*gtk.CssProvider = null,

    pub fn init(parent_allocator: std.mem.Allocator) !*AppData {
        const data = try parent_allocator.create(AppData);
        const arena = try parent_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(parent_allocator);
        const allocator = arena.allocator();
        const config = Config.init();

        data.* = .{
            .arena = arena,
            .allocator = allocator,
            .config = config,
            .css_provider = null,
        };

        return data;
    }

    pub fn deinit(self: *AppData, parent_allocator: std.mem.Allocator) void {
        if (self.css_provider) |provider| {
            provider.unref();
        }
        self.arena.deinit();
        parent_allocator.destroy(self.arena);
        parent_allocator.destroy(self);
    }
};

fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data) |data| {
        const app_data = @as(*AppData, @ptrCast(@alignCast(data)));
        const allocator = app_data.allocator;

        app_data.css_provider = loadCss(
            allocator,
            &app_data.config,
            app_data.css_provider,
        ) catch |err| {
            std.debug.print("Failed to load CSS: {}\n", .{err});
            std.posix.exit(1);
        };

        const builder = gtk.Builder.newFromFile(".zig-cache/ui/system-bar.ui");
        defer builder.unref();

        const window_obj = gtk.Builder.getObject(builder, "window") orelse {
            std.debug.print("Failed to get window from UI file\n", .{});
            std.posix.exit(1);
        };
        const window = @as(*gtk.ApplicationWindow, @ptrCast(window_obj));

        const music_container_obj = gtk.Builder.getObject(builder, "music_container") orelse {
            std.debug.print("Failed to get music_container from UI file\n", .{});
            std.posix.exit(1);
        };
        const music_container = @as(*gtk.Box, @ptrCast(music_container_obj));

        const clock_container_obj = gtk.Builder.getObject(builder, "clock_container") orelse {
            std.debug.print("Failed to get clock_container from UI file\n", .{});
            std.posix.exit(1);
        };
        const clock_container = @as(*gtk.Box, @ptrCast(clock_container_obj));

        const popover_obj = gtk.Builder.getObject(builder, "menu_popover") orelse {
            std.debug.print("Failed to get menu_popover\n", .{});
            std.posix.exit(1);
        };
        const popover = @as(*gtk.Popover, @ptrCast(popover_obj));
        gtk.Popover.setHasArrow(popover, 0);

        const launcher_container_obj = gtk.Builder.getObject(builder, "launcher_container") orelse {
            std.debug.print("Failed to get launcher_container\n", .{});
            std.posix.exit(1);
        };
        const launcher_container = @as(*gtk.Box, @ptrCast(launcher_container_obj));
        gtk.Popover.setHasArrow(popover, 0);

        // Create clock component (JST)
        var clock = Clock.new(9);
        gtk.Box.append(clock_container, clock.as(gtk.Widget));

        var music = Music.new(app_data.allocator);
        gtk.Box.append(music_container, music.as(gtk.Widget));

        var launcher = Launcher.new(app_data.allocator) catch {
            std.debug.print("Failed to initialized launcher\n", .{});
            std.posix.exit(1);
        };
        gtk.Box.append(launcher_container, launcher.as(gtk.Widget));

        setupActions(app);

        gtk.Application.addWindow(app, window.as(gtk.Window));
        gtk.Widget.show(window.as(gtk.Widget));

        // Make window style like system bar
        layer_shell.setupLayerShell(
            window,
            &app_data.config,
        );
    }
}

fn setupActions(app: *gtk.Application) void {
    // Sleep action
    const sleep_action = gio.SimpleAction.new("sleep", null);
    _ = gio.SimpleAction.signals.activate.connect(
        sleep_action,
        ?*anyopaque,
        &onSleep,
        null,
        .{},
    );
    gio.ActionMap.addAction(app.as(gio.ActionMap), sleep_action.as(gio.Action));
    sleep_action.unref();

    const restart_action = gio.SimpleAction.new("restart", null);
    _ = gio.SimpleAction.signals.activate.connect(
        restart_action,
        ?*anyopaque,
        &onRestart,
        null,
        .{},
    );

    gio.ActionMap.addAction(app.as(gio.ActionMap), restart_action.as(gio.Action));
    restart_action.unref();

    // Shutdown action
    const shutdown_action = gio.SimpleAction.new("shutdown", null);
    _ = gio.SimpleAction.signals.activate.connect(
        shutdown_action,
        ?*anyopaque,
        &onShutdown,
        null,
        .{},
    );
    gio.ActionMap.addAction(app.as(gio.ActionMap), shutdown_action.as(gio.Action));
    shutdown_action.unref();
}

fn onRestart(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
    std.debug.print("Restarting system...\n", .{});

    var err: ?*glib.Error = null;
    const connection = gio.busGetSync(.system, null, &err);

    if (err) |_| {
        std.debug.print("Failed to get system bus\n", .{});
        return;
    }

    if (connection == null) {
        std.debug.print("Failed to get system bus connection\n", .{});
        return;
    }
    defer connection.?.unref();
    std.debug.print("D-Bus connection established\n", .{});

    const interactive = glib.Variant.newBoolean(1);
    const params_array = [_]*glib.Variant{interactive};
    const params = glib.Variant.newTuple(&params_array, params_array.len);

    var call_err: ?*glib.Error = null;
    const result = gio.DBusConnection.callSync(
        connection.?,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "Reboot",
        params,
        null,
        .{},
        -1,
        null,
        &call_err,
    );

    if (result) |r| {
        defer r.unref();
    }
}

fn onSleep(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
    std.debug.print("Suspending system...\n", .{});
    var err: ?*glib.Error = null;
    const connection = gio.busGetSync(.system, null, &err);
    if (err) |_| {
        std.debug.print("Failed to get system bus\n", .{});
        return;
    }
    if (connection == null) {
        std.debug.print("Failed to get system bus connection\n", .{});
        return;
    }
    defer connection.?.unref();

    const interactive = glib.Variant.newBoolean(1);
    const params_array = [_]*glib.Variant{interactive};
    const params = glib.Variant.newTuple(&params_array, params_array.len);

    var call_err: ?*glib.Error = null;
    const result = gio.DBusConnection.callSync(
        connection.?,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "Suspend",
        params,
        null,
        .{},
        -1,
        null,
        &call_err,
    );
    if (result) |r| {
        defer r.unref();
    }
}

fn onShutdown(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
    std.debug.print("Shutting down system...\n", .{});
    var err: ?*glib.Error = null;
    const connection = gio.busGetSync(.system, null, &err);
    if (err) |_| {
        std.debug.print("Failed to get system bus\n", .{});
        return;
    }
    if (connection == null) {
        std.debug.print("Failed to get system bus connection\n", .{});
        return;
    }
    defer connection.?.unref();

    const interactive = glib.Variant.newBoolean(1);
    const params_array = [_]*glib.Variant{interactive};
    const params = glib.Variant.newTuple(&params_array, params_array.len);

    var call_err: ?*glib.Error = null;
    const result = gio.DBusConnection.callSync(
        connection.?,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "PowerOff",
        params,
        null,
        .{},
        -1,
        null,
        &call_err,
    );
    if (result) |r| {
        defer r.unref();
    }
}

fn getUIPath(allocator: std.mem.Allocator) ![]const u8 {
    const cache_path = ".zig-cache/ui/system-bar.ui";
    if (std.fs.cwd().access(cache_path, .{})) {
        return try allocator.dupe(u8, cache_path);
    }

    return error.UIFileNotFound;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const app_data = try AppData.init(allocator);
    defer app_data.deinit(allocator);

    var app = gtk.Application.new("org.iroha.systembar", .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(
        app,
        ?*anyopaque,
        &activate,
        @ptrCast(@alignCast(app_data)),
        .{},
    );
    const status = gio.Application.run(
        app.as(gio.Application),
        @intCast(std.os.argv.len),
        std.os.argv.ptr,
    );
    std.process.exit(@intCast(status));
}
