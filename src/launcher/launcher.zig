const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const info = @import("./info.zig");

pub const Launcher = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Widget;
    const Self = @This();

    const Private = struct {
        scrolled_window: ?*gtk.ScrolledWindow,
        app_box: ?*gtk.Box,
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

    pub fn new(allocator: std.mem.Allocator) !*Self {
        var launcher = gobject.ext.newInstance(Self, .{});
        const priv = launcher.private();

        const style_context = gtk.Widget.getStyleContext(launcher.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "launcher");

        const apps = try info.getAllApplications(allocator);
        priv.apps = apps;
        priv.allocator = allocator;

        if (priv.app_box) |app_box| {
            for (apps.items) |*app| {
                const widget = app.createWidget();
                app_box.append(widget.as(gtk.Widget));
            }
        }

        return launcher;
    }

    pub fn as(clock: *Self, comptime T: type) *T {
        return gobject.ext.as(T, clock);
    }

    fn init(self: *Self, _: *Class) callconv(.c) void {
        const priv = self.private();

        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setPolicy(.automatic, .never); // Only scrollable horizontal
        
        scrolled.setMinContentHeight(40);
        scrolled.setMaxContentHeight(40);

        scrolled.setMinContentWidth(300);

        const widget = self.as(gtk.Widget);

        const bin_layout = gtk.BinLayout.new();
        const layout_manager: *gtk.LayoutManager = @ptrCast(@alignCast(bin_layout));
        widget.setLayoutManager(layout_manager);

        gtk.Widget.setParent(scrolled.as(gtk.Widget), widget);

        priv.scrolled_window = scrolled;
        priv.apps = null;
        priv.allocator = null;

        const box = gtk.Box.new(.horizontal, 8);
        scrolled.setChild(box.as(gtk.Widget));

        priv.app_box = box;
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = self.private();

        const allocator = priv.allocator orelse return;

        if (priv.apps) |*apps| {
            for (apps.items) |*app| {
                _ = app;
            }
            apps.deinit(allocator);
            priv.apps = null;
        }

        if (priv.scrolled_window) |scrolled| {
            gtk.Widget.unparent(scrolled.as(gtk.Widget));
            priv.scrolled_window = null;
        }

        priv.app_box = null;
        priv.allocator = null;
        
        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
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
    };
};
