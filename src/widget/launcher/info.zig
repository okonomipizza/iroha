const std = @import("std");
const gio = @import("gio");
const glib = @import("glib");
const gtk = @import("gtk");
const gobject = @import("gobject");
const AppLauncheDataManager = @import("data.zig").AppLaunchManager;

pub const AppEntry = struct {
    name: [*:0]const u8,
    icon: ?*gio.Icon,
    app_info: *gio.AppInfo,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn launch(self: *const AppEntry) void {
        _ = self.app_info.launch(null, null, null);
    }

    pub fn createWidget(self: *const Self) *gtk.Button {
        const button = gtk.Button.new();

        const style_context = gtk.Widget.getStyleContext(button.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "launcher-app-icon");

        const box = gtk.Box.new(.vertical, 4);
        button.setChild(box.as(gtk.Widget));

        if (self.icon) |icon| {
            const image = gtk.Image.newFromGicon(icon);
            image.setPixelSize(16);
            box.append(image.as(gtk.Widget));
        } else {
            // Fallback icon
            const placefolder = gtk.Image.newFromIconName("application-x-executable");
            placefolder.setPixelSize(16);
            box.append(placefolder.as(gtk.Widget));
        }

        const UserData = struct {
            app_info: *gio.AppInfo,
            allocator: std.mem.Allocator,
        };

        const user_data = self.allocator.create(UserData) catch return button;

        _ = gobject.Object.ref(self.app_info.as(gobject.Object));
        user_data.* = .{
            .app_info = self.app_info,
            .allocator = self.allocator,
        };

        gobject.Object.setData(button.as(gobject.Object), "iroha-app-data", user_data);

        _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &onAppButtonClicked, null, .{});

        _ = gtk.Widget.signals.destroy.connect(
            button,
            ?*anyopaque,
            &onButtonDestroy,
            null,
            .{},
        );

        return button;
    }

    pub fn onButtonDestroy(button: *gtk.Button, user_data: ?*anyopaque) callconv(.c) void {
        _ = user_data;
        const UserData = struct {
            app_info: *gio.AppInfo,
            allocator: std.mem.Allocator,
        };

        const data_ptr = gobject.Object.getData(button.as(gobject.Object), "iroha-app-data");
        if (data_ptr) |ptr| {
            const data: *UserData = @ptrCast(@alignCast(ptr));
            gobject.Object.unref(data.app_info.as(gobject.Object));
            data.allocator.destroy(data);
        }
    }

    pub fn onAppButtonClicked(button: *gtk.Button, user_data: ?*anyopaque) callconv(.c) void {
        _ = user_data;

        const UserData = struct {
            app_info: *gio.AppInfo,
            allocator: std.mem.Allocator,
        };

        const data_ptr = gobject.Object.getData(button.as(gobject.Object), "iroha-app-data");
        if (data_ptr) |ptr| {
            const data: *UserData = @ptrCast(@alignCast(ptr));
            const app_info = data.app_info;
            const allocator = data.allocator;

            var error_ptr: ?*glib.Error = null;
            const result = app_info.launch(null, null, &error_ptr);

            if (result == 0) {
                if (error_ptr) |err| {
                    glib.Error.free(err);
                }
            } else {
                const app_name_cstr = app_info.getName();
                const app_name = std.mem.span(app_name_cstr);

                AppLauncheDataManager.appendAppName(allocator, app_name) catch return;
            }
        }
    }
};

pub fn getAllApplications(allocator: std.mem.Allocator) !std.ArrayList(AppEntry) {
    const app_list = gio.AppInfo.getAll();
    defer glib.List.freeFull(app_list, @ptrCast(&gobject.Object.unref));

    const app_length: usize = @intCast(app_list.length());
    var apps = try std.ArrayList(AppEntry).initCapacity(allocator, app_length);

    var current: ?*glib.List = app_list;
    while (current) |node| {
        const app_info: *gio.AppInfo = @ptrCast(@alignCast(node.f_data));
        if (shouldInclude(app_info)) {
            // Avoid freeing required AppInfo from memory
            _ = gobject.Object.ref(@ptrCast(@alignCast(app_info)));
            const entry: AppEntry = .{
                .name = app_info.getName(),
                .icon = app_info.getIcon(),
                .app_info = app_info,
                .allocator = allocator,
            };
            try apps.append(allocator, entry);
        }

        current = node.f_next;
    }
    return apps;
}

fn shouldInclude(app_info: *gio.AppInfo) bool {
    if (app_info.shouldShow() == 0) return false;
    if (app_info.getIcon() == null) return false;

    return true;
}
