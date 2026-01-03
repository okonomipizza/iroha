const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gio = @import("gio");
const gdkpixbuf = @import("gdkpixbuf");
const AppContext = @import("../main.zig").AppContext;
const Config = @import("../config.zig").Config;
const layer_shell = @import("../layer_shell.zig");

pub fn onRestart(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
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

pub fn onSleep(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
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

pub fn onShutdown(_: *gio.SimpleAction, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) void {
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
