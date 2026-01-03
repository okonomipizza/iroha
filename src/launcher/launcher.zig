const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gio = @import("gio");
const AppLauncheDataManager = @import("data.zig").AppLaunchManager;
const AppEntry = @import("info.zig").AppEntry;

const info = @import("./info.zig");

pub const Launcher = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Widget;
    const Self = @This();

    const Private = struct {
        launcher_button: ?*gtk.MenuButton,
        launcher_popover: ?*gtk.Popover,
        launcher_grid: ?*gtk.Grid,
        // scrolled_window: ?*gtk.ScrolledWindow,
        // app_box: ?*gtk.Box,
        apps: ?std.ArrayList(info.AppEntry),
        allocator: ?std.mem.Allocator,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "IrohaLauncher",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(
        allocator: std.mem.Allocator,
        launcher_button: *gtk.MenuButton,
        launcher_popover: *gtk.Popover,
        launcher_grid: *gtk.Grid,
    ) !*Self {
        var launcher = gobject.ext.newInstance(Self, .{});
        const priv = launcher.private();

        priv.launcher_button = launcher_button;
        priv.launcher_popover = launcher_popover;
        priv.launcher_grid = launcher_grid;
        priv.allocator = allocator;

        // const style_context = gtk.Widget.getStyleContext(launcher.as(gtk.Widget));
        // gtk.StyleContext.addClass(style_context, "launcher");

        var apps = try info.getAllApplications(allocator);
        priv.apps = apps;

        const data_manager = try AppLauncheDataManager.init(allocator);
        defer data_manager.deinit();

        sortAppOrder(data_manager, &apps);

        // Populate launcher grid with 5 columns
        const columns: c_int = 5;
        var row: c_int = 0;
        var col: c_int = 0;

        for (apps.items) |*app| {
            const button = createAppButton(app);
            launcher_grid.attach(button.as(gtk.Widget), col, row, 1, 1);

            col += 1;
            if (col >= columns) {
                col = 0;
                row += 1;
            }
        }
        // if (priv.app_box) |app_box| {
        //     sortAppOrder(data_manager, &apps);
        //     // Add app launch buttons
        //     for (apps.items) |*app| {
        //         const widget = app.createWidget();
        //         app_box.append(widget.as(gtk.Widget));
        //     }
        // }

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
        // const button = gtk.Button.new();
        //
        // const box = gtk.Box.new(.horizontal, 8);
        // button.setChild(box.as(gtk.Widget));
        //
        // // Icon
        // if (app.icon) |icon_name| {
        //     if (icon_name.toString()) |name| {
        //         const icon = gtk.Image.newFromIconName(name);
        //         gtk.Image.setPixelSize(icon, 32);
        //         box.append(icon.as(gtk.Widget));
        //     }
        // }
        //
        // // Label
        // const label = gtk.Label.new(app.name);
        // gtk.Label.setXalign(label, 0.0);
        // gtk.Widget.setHexpand(label.as(gtk.Widget), 1);
        // box.append(label.as(gtk.Widget));
        //
        // // Connect click signal
        // _ = gtk.Button.signals.clicked.connect(
        //     button,
        //     *AppEntry,
        //     &onAppButtonClicked,
        //     app,
        //     .{},
        // );
        //
        // const style_context = gtk.Widget.getStyleContext(button.as(gtk.Widget));
        // gtk.StyleContext.addClass(style_context, "launcher-app-button");
        //
        // return button;
    }

    // fn onAppButtonClicked(button: *gtk.Button, app: *AppEntry) callconv(.c) void {
    //     _ = button;
    //     app.launch();
    // }

    /// Sorts the app list based on launch frequency
    ///
    /// Reorders the app list according to the launch statistics stored in data_manager.
    /// App that have been launched more recently or frequently appear first in the sorted list.
    /// The order in data_manager.stats determines the priority, and the apps list is rearranged
    /// to match that order.
    ///
    /// Parameters:
    ///   - data_manager: Manager containing app launch statistics
    ///   - apps: List ot app entries to be sorted (modified in place)
    ///
    /// Note:
    ///   - Apps not present in data_manager remain at the end of the list
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

    pub fn as(clock: *Self, comptime T: type) *T {
        return gobject.ext.as(T, clock);
    }

    fn init(self: *Self, _: *Class) callconv(.c) void {
        const priv = self.private();
        priv.launcher_button = null;
        priv.launcher_popover = null;
        priv.launcher_grid = null;
        priv.apps = null;
        priv.allocator = null;
        // const priv = self.private();
        //
        // const scrolled = gtk.ScrolledWindow.new();
        // scrolled.setPolicy(.automatic, .never); // Only scrollable horizontal
        //
        // scrolled.setMinContentHeight(40);
        // scrolled.setMaxContentHeight(40);
        //
        // scrolled.setMinContentWidth(300);
        //
        // const widget = self.as(gtk.Widget);
        //
        // const bin_layout = gtk.BinLayout.new();
        // const layout_manager: *gtk.LayoutManager = @ptrCast(@alignCast(bin_layout));
        // widget.setLayoutManager(layout_manager);
        //
        // gtk.Widget.setParent(scrolled.as(gtk.Widget), widget);
        //
        // priv.scrolled_window = scrolled;
        // priv.apps = null;
        // priv.allocator = null;
        //
        // const box = gtk.Box.new(.horizontal, 8);
        // scrolled.setChild(box.as(gtk.Widget));
        //
        // priv.app_box = box;
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = self.private();

        if (priv.apps) |*apps| {
            if (priv.allocator) |a| {
                apps.deinit(a);
            }
            priv.apps = null;
        }

        priv.launcher_button = null;
        priv.launcher_popover = null;
        priv.launcher_grid = null;
        priv.allocator = null;

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        // const priv = self.private();
        //
        // const allocator = priv.allocator orelse return;
        //
        // if (priv.apps) |*apps| {
        //     for (apps.items) |*app| {
        //         _ = app;
        //     }
        //     apps.deinit(allocator);
        //     priv.apps = null;
        // }
        //
        // if (priv.scrolled_window) |scrolled| {
        //     gtk.Widget.unparent(scrolled.as(gtk.Widget));
        //     priv.scrolled_window = null;
        // }
        //
        // priv.app_box = null;
        // priv.allocator = null;
        //
        // gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    fn private(self: *Self) *Private {
        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }
        // parent_class: Parent.Class,
        //
        // var parent: *Parent.Class = undefined;
        //
        // pub const Instance = Self;
        //
        // pub fn as(class: *Class, comptime T: type) *T {
        //     return gobject.ext.as(T, class);
        // }
        //
        // fn init(class: *Class) callconv(.c) void {
        //     gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        // }
    };
};
