const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gio = @import("gio");
const AppLauncheDataManager = @import("data.zig").AppLaunchManager;
const AppEntry = @import("info.zig").AppEntry;

const info = @import("./info.zig");

pub const Launcher = struct {
    allocator: std.mem.Allocator,

    apps: ?std.ArrayList(info.AppEntry),

    container: *gtk.Box,
    button: *gtk.MenuButton,
    popover: *gtk.Popover,
    app_box: *gtk.Box,
    scrolled_window: *gtk.ScrolledWindow,
    grid: *gtk.Grid,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        container: *gtk.Box,
        button: *gtk.MenuButton,
        popover: *gtk.Popover,
        app_box: *gtk.Box,
        scrolled_window: *gtk.ScrolledWindow,
        grid: *gtk.Grid,
    ) !*Self {
        const launcher = try allocator.create(Self);
        var apps = try info.getAllApplications(allocator);

        launcher.* = .{
            .allocator = allocator,
            .apps = apps,
            .container = container,
            .button = button,
            .popover = popover,
            .app_box = app_box,
            .scrolled_window = scrolled_window,
            .grid = grid,
        };

        const data_manager = try AppLauncheDataManager.init(allocator);
        defer data_manager.deinit();

        sortAppOrder(data_manager, &apps);

        // Populate launcher grid with 5 columns
        const columns: c_int = 5;
        var row: c_int = 0;
        var col: c_int = 0;

        for (apps.items) |*app| {
            const app_button = createAppButton(app);
            grid.attach(app_button.as(gtk.Widget), col, row, 1, 1);

            col += 1;
            if (col >= columns) {
                col = 0;
                row += 1;
            }
        }

        gtk.Popover.setHasArrow(popover, 0);

        return launcher;
    }

    fn createAppButton(app: *AppEntry) *gtk.Button {
        const button = gtk.Button.new();

        const box = gtk.Box.new(.vertical, 4);
        button.setChild(box.as(gtk.Widget));

        // Icon
        if (app.icon) |icon| {
            const image = gtk.Image.newFromGicon(icon);
            gtk.Image.setPixelSize(image, 48);
            box.append(image.as(gtk.Widget));
        } else {
            const placeholder = gtk.Image.newFromIconName("application-x-executable");
            gtk.Image.setPixelSize(placeholder, 48);
            box.append(placeholder.as(gtk.Widget));
        }

        // Label
        const label = gtk.Label.new(app.name);
        gtk.Label.setMaxWidthChars(label, 12);
        gtk.Label.setEllipsize(label, .end);
        gtk.Label.setJustify(label, .center);
        gtk.Widget.setHalign(label.as(gtk.Widget), .center);
        box.append(label.as(gtk.Widget));

        // Store app data using GObject data mechanism (info.zigと同じ方法)
        const UserData = struct {
            app_info: *gio.AppInfo,
            allocator: std.mem.Allocator,
        };

        const user_data = app.allocator.create(UserData) catch return button;
        _ = gobject.Object.ref(app.app_info.as(gobject.Object));
        user_data.* = .{
            .app_info = app.app_info,
            .allocator = app.allocator,
        };

        gobject.Object.setData(button.as(gobject.Object), "iroha-app-data", user_data);

        _ = gtk.Button.signals.clicked.connect(
            button,
            ?*anyopaque,
            &AppEntry.onAppButtonClicked, // info.zigのメソッドを使用
            null,
            .{},
        );

        _ = gtk.Widget.signals.destroy.connect(
            button,
            ?*anyopaque,
            &AppEntry.onButtonDestroy, // info.zigのメソッドを使用
            null,
            .{},
        );

        const style_context = gtk.Widget.getStyleContext(button.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "launcher-app-button");

        return button;
    }

    fn sortAppOrder(data_manager: *AppLauncheDataManager, apps: *std.ArrayList(AppEntry)) void {
        var i: usize = 0;
        while (i < data_manager.length()) : (i += 1) {
            const target = data_manager.stats.items[i].app_name;
            var t = i;
            while (t < apps.items.len) : (t += 1) {
                const current = std.mem.span(apps.items[t].name);
                if (std.mem.eql(u8, target, current)) {
                    if (t == i) break;
                    const temp = apps.items[i];
                    apps.items[i] = apps.items[t];
                    apps.items[t] = temp;
                    break;
                }
            }
        }
    }
};
