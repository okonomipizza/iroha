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
const onSleep = @import("./widget/system.zig").onSleep;
const onRestart = @import("./widget/system.zig").onRestart;
const onShutdown = @import("./widget/system.zig").onShutdown;

fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.c) void {
    const data = user_data orelse return;
    const app_data = @as(*AppData, @ptrCast(@alignCast(data)));
    const allocator = app_data.allocator;

    app_data.css_provider = loadCss(
        allocator,
        &app_data.config,
        app_data.css_provider,
    ) catch |err| {
        fatalError("css", err);
    };

    const ui_path = getUIPath(allocator) catch |err| {
        fatalError("UI file not found", err);
    };
    defer allocator.free(ui_path);

    const ui_path_z = allocator.dupeZ(u8, ui_path) catch |err| {
        fatalError("Failed to allocate UI path", .{err});
    };
    defer allocator.free(ui_path_z);

    const builder = gtk.Builder.newFromFile(ui_path_z.ptr);
    defer builder.unref();

    const window_obj = gtk.Builder.getObject(builder, "window") orelse {
        fatalError("Failed to get window from UI file", .{});
    };
    const window = @as(*gtk.ApplicationWindow, @ptrCast(window_obj));

    setupLauncher(allocator, builder) catch |err| {
        fatalError("Failed to set up Launcher", .{err});
    };

    const music = setupMusic(allocator, builder) catch |err| {
        fatalError("Failed to set up Music", .{err});
    };

    setupClock(builder) catch |err| {
        fatalError("Failed to set up Clock", .{err});
    };

    setupMenuPopover(builder) catch |err| {
        fatalError("Failed to set up Menu popover", .{err});
    };
    setupActions(app);

    // Finalize window
    gtk.Application.addWindow(app, window.as(gtk.Window));
    gtk.Widget.show(window.as(gtk.Widget));

    music.startAnimation();
    layer_shell.setupLayerShell(
        window,
        &app_data.config,
    );
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

fn setupLauncher(allocator: std.mem.Allocator, builder: *gtk.Builder) !void {
    const launcher_container = try getWidget(gtk.Box, builder, "launcher_container");
    const launcher_button = try getWidget(gtk.MenuButton, builder, "launcher_button");
    const launcher_popover = try getWidget(gtk.Popover, builder, "launcher_popover");
    const launcher_popover_box = try getWidget(gtk.Box, builder, "launcher_popover_box");
    const launcher_scrolled_window = try getWidget(gtk.ScrolledWindow, builder, "launcher_scroll");
    const launcher_grid = try getWidget(gtk.Grid, builder, "launcher_grid");

    _ = try Launcher.init(
        allocator,
        launcher_container,
        launcher_button,
        launcher_popover,
        launcher_popover_box,
        launcher_scrolled_window,
        launcher_grid,
    );
}

fn setupMusic(allocator: std.mem.Allocator, builder: *gtk.Builder) !*Music {
    const music_container = try getWidget(gtk.Box, builder, "music_container");
    const music_play_pause_button = try getWidget(gtk.Button, builder, "music_play_pause_button");
    const music_play_pause_icon = try getWidget(gtk.Image, builder, "music_play_pause_icon");
    const music_scrolled = try getWidget(gtk.ScrolledWindow, builder, "music_scrolled_window");
    const music_scrolled_title_box = try getWidget(gtk.Box, builder, "music_scrolled_title_box");
    const music_scrolled_title_label = try getWidget(gtk.Label, builder, "music_scrolled_label");

    return try Music.init(
        allocator,
        music_container,
        music_play_pause_button,
        music_play_pause_icon,
        music_scrolled,
        music_scrolled_title_box,
        music_scrolled_title_label,
    );
}

fn setupClock(builder: *gtk.Builder) !void {
    const clock_container = try getWidget(gtk.Box, builder, "clock_container");
    var clock = Clock.new(9);
    gtk.Box.append(clock_container, clock.as(gtk.Widget));
}

fn setupMenuPopover(builder: *gtk.Builder) !void {
    const menu_popover = try getWidget(gtk.Popover, builder, "menu_popover");
    gtk.Popover.setHasArrow(menu_popover, 0);
}

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

fn getWidget(comptime T: type, builder: *gtk.Builder, name: [*:0]const u8) !*T {
    const obj = gtk.Builder.getObject(builder, name) orelse
        return error.WidgetNotFound;
    return @ptrCast(obj);
}

fn fatalError(component: []const u8, err: anytype) noreturn {
    std.debug.print("{s}: {}\n", .{ component, err });
    std.posix.exit(1);
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

const UI_PATHS = [_][]const u8{
    "zig-out/ui/system-bar.ui", // zig build run
    "zig-out/share/iroha/ui/system-bar.ui", // local install
    "/usr/share/iroha/ui/system-bar.ui", // system install
    "/usr/local/share/iroha/ui/system-bar.ui",
};

fn getUIPath(allocator: std.mem.Allocator) ![]const u8 {
    // First try direct paths
    for (UI_PATHS) |path| {
        std.fs.cwd().access(path, .{}) catch continue;
        return try allocator.dupe(u8, path);
    }

    // Try XDG_DATA_DIRS
    if (std.posix.getenv("XDG_DATA_DIRS")) |data_dirs| {
        var iter = std.mem.splitAny(u8, data_dirs, ":");
        while (iter.next()) |dir| {
            const path = try std.fs.path.join(allocator, &.{ dir, "iroha", "ui", "system-bar.ui" });
            defer allocator.free(path);

            std.fs.cwd().access(path, .{}) catch continue;
            return try allocator.dupe(u8, path);
        }
    }

    return error.UIFileNotFound;
}
