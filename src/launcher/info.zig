const std = @import("std");
const gio = @import("gio");
const glib = @import("glib");
const gtk = @import("gtk");
const gobject = @import("gobject");
const DotDesktopParser = @import("desktop.zig").DotDesktopParser;

pub const AppEntry = struct {
    name: [*:0]const u8,
    icon: ?*gio.Icon,
    app_info: *gio.AppInfo,

    const Self = @This();

    pub fn launch(self: *const AppEntry) void {
        _ = self.app_info.launch(self.app_info, null, null);
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

        const app_ref = gobject.Object.ref(self.app_info.as(gobject.Object));
        gobject.Object.setData(button.as(gobject.Object), "app-info", app_ref);

        _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &onAppButtonClicked, null, .{});

        return button;
    }

    fn onAppButtonClicked(button: *gtk.Button, user_data: ?*anyopaque) callconv(.c) void {
        _ = user_data;

        const app_info_ptr = gobject.Object.getData(button.as(gobject.Object), "app-info");
        if (app_info_ptr) |ptr| {
            const app_info: *gio.AppInfo = @ptrCast(@alignCast(ptr));
            var error_ptr: ?*glib.Error = null;
            const result = app_info.launch(null, null, &error_ptr);

            if (result == 0) {
                if (error_ptr) |err| {
                    std.debug.print("Failed to launch app: {s}\n", .{err.f_message});
                    glib.Error.free(err);
                }
            } else {
                const app_name = app_info.getName();
                std.debug.print("Launched app: {s}\n", .{app_name});
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
