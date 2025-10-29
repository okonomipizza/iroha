const std = @import("std");
const gio = @import("gio");
const glib = @import("glib");
const NotificationState = @import("./widget/notification.zig").NotificationState;
const NotificationData = @import("./widget/notification.zig").NotificationData;
const NotificationType = @import("./widget/notification.zig").NotificationType;

const notifications_interface = "org.freedesktop.Notifications";
const notifications_path = "/org/freedesktop/Notifications";
const introspection_xml =
    \\<?xml version="1.0" encoding="utf-8"?>
    \\<node>
    \\  <interface name='org.freedesktop.Notifications'>
    \\    <method name='Notify'>
    \\      <arg type='s' name='app_name' direction='in'/>
    \\      <arg type='u' name='replaces_id' direction='in'/>
    \\      <arg type='s' name='app_icon' direction='in'/>
    \\      <arg type='s' name='summary' direction='in'/>
    \\      <arg type='s' name='body' direction='in'/>
    \\      <arg type='as' name='actions' direction='in'/>
    \\      <arg type='a{sv}' name='hints' direction='in'/>
    \\      <arg type='i' name='expire_timeout' direction='in'/>
    \\      <arg type='u' name='id' direction='out'/>
    \\    </method>
    \\    <method name='CloseNotification'>
    \\      <arg type='u' name='id' direction='in'/>
    \\    </method>
    \\    <method name='GetCapabilities'>
    \\      <arg type='as' name='capabilities' direction='out'/>
    \\    </method>
    \\    <method name='GetServerInformation'>
    \\      <arg type='s' name='name' direction='out'/>
    \\      <arg type='s' name='vendor' direction='out'/>
    \\      <arg type='s' name='version' direction='out'/>
    \\      <arg type='s' name='spec_version' direction='out'/>
    \\    </method>
    \\    <signal name='NotificationClosed'>
    \\      <arg type='u' name='id'/>
    \\      <arg type='u' name='reason'/>
    \\    </signal>
    \\    <signal name='ActionInvoked'>
    \\      <arg type='u' name='id'/>
    \\      <arg type='s' name='action_key'/>
    \\    </signal>
    \\  </interface>
    \\</node>
;

var notification_id_counter: u32 = 1;

fn handleMethodCall(
    connection: *gio.DBusConnection,
    sender: [*:0]const u8,
    object_path: [*:0]const u8,
    interface_name: [*:0]const u8,
    method_name: [*:0]const u8,
    parameters: *glib.Variant,
    invocation: *gio.DBusMethodInvocation,
    user_data: ?*anyopaque,
) callconv(.c) void {
    _ = connection;
    _ = sender;
    _ = object_path;
    _ = interface_name;

    const method_name_slice = std.mem.span(method_name);

    if (std.mem.eql(u8, method_name_slice, "Notify")) {
        var app_name: [*:0]const u8 = undefined;
        var replaces_id: u32 = undefined;
        var app_icon: [*:0]const u8 = undefined;
        var summary: [*:0]const u8 = undefined;
        var body: [*:0]const u8 = undefined;
        var actions: *glib.Variant = undefined;
        var hints: *glib.Variant = undefined;
        var expire_timeout: i32 = undefined;

        _ = glib.Variant.get(
            parameters,
            "(&su&s&s&s@as@a{sv}i)",
            &app_name,
            &replaces_id,
            &app_icon,
            &summary,
            &body,
            &actions,
            &hints,
            &expire_timeout,
        );

        const id = if (replaces_id != 0) replaces_id else blk: {
            const new_id = notification_id_counter;
            notification_id_counter += 1;
            break :blk new_id;
        };

        std.debug.print("\n=== received notification ===\n", .{});
        std.debug.print("from: {s}\n", .{app_name});
        std.debug.print("icon: {s}\n", .{app_icon});
        std.debug.print("title: {s}\n", .{summary});
        std.debug.print("body: {s}\n", .{body});
        std.debug.print("timeout: {}ms\n", .{expire_timeout});
        std.debug.print("===============\n\n", .{});

        if (user_data) |data| {
            const state = @as(*NotificationState, @ptrCast(@alignCast(data)));
            state.addNotification(std.mem.span(app_name), std.mem.span(summary), id) catch |err| {
                std.debug.print("Failed to add notification: {}\n", .{err});
            };
        }

        actions.unref();
        hints.unref();

        const id_c: c_uint = @intCast(id);
        const return_value = glib.Variant.new("(u)", id_c);
        gio.DBusMethodInvocation.returnValue(invocation, return_value);
    } else if (std.mem.eql(u8, method_name_slice, "GetCapabilities")) {
        const builder = glib.VariantBuilder.new(glib.VariantType.new("as"));
        defer builder.unref();

        _ = glib.VariantBuilder.add(builder, "s", "body");
        _ = glib.VariantBuilder.add(builder, "s", "body-markup");
        _ = glib.VariantBuilder.add(builder, "s", "actions");
        _ = glib.VariantBuilder.add(builder, "s", "icon-static");
        const return_value = glib.Variant.new("(as)", builder);
        gio.DBusMethodInvocation.returnValue(invocation, return_value);
    } else if (std.mem.eql(u8, method_name_slice, "GetServerInformation")) {
        const name: [*:0]const u8 = "iroha-systembar";
        const vendor: [*:0]const u8 = "iroha";
        const version: [*:0]const u8 = "1.0.0";
        const spec_version: [*:0]const u8 = "1.2";

        const return_value = glib.Variant.new(
            "(ssss)",
            name,
            vendor,
            version,
            spec_version,
        );
        gio.DBusMethodInvocation.returnValue(invocation, return_value);
    } else if (std.mem.eql(u8, method_name_slice, "CloseNotification")) {
        var id: u32 = undefined;
        _ = glib.Variant.get(parameters, "(u)", &id);

        std.debug.print("close #{}\n", .{id});

        gio.DBusMethodInvocation.returnValue(invocation, null);
    }
}

fn dummyDestroyNotify(data: ?*anyopaque) callconv(.c) void {
    _ = data;
}

fn onBusAcquired(
    connection: *gio.DBusConnection,
    name: [*:0]const u8,
    user_data: ?*anyopaque,
) callconv(.c) void {
    _ = name;

    var err: ?*glib.Error = null;
    const introspection_data = gio.DBusNodeInfo.newForXml(introspection_xml, &err);
    if (err) |e| {
        if (e.f_message) |msg| {
            std.debug.print("XML parse error: {s}\n", .{msg});
        }
        return;
    }

    defer introspection_data.?.unref();

    const vtable = gio.DBusInterfaceVTable{
        .f_method_call = handleMethodCall,
        .f_get_property = null,
        .f_set_property = null,
        .f_padding = undefined,
    };

    const interfaces = introspection_data.?.f_interfaces orelse {
        std.debug.print("no interface found\n", .{});
        return;
    };

    const first_interface = interfaces[0];
    const registration_id = gio.DBusConnection.registerObject(
        connection,
        notifications_path,
        first_interface,
        &vtable,
        user_data,
        dummyDestroyNotify,
        &err,
    );

    if (err) |e| {
        std.debug.print("error of object registration: {s}\n", .{e.f_message.?});
        return;
    }

    if (registration_id > 0) {
        std.debug.print("notification daemon started: registration_id={}\n", .{registration_id});
    }
}

fn onNameAcquired(
    connection: *gio.DBusConnection,
    name: [*:0]const u8,
    user_data: ?*anyopaque,
) callconv(.c) void {
    _ = connection;
    _ = user_data;
    std.debug.print("d-bus name: {s}\n", .{name});
}

fn onNameLost(
    connection: *gio.DBusConnection,
    name: [*:0]const u8,
    user_data: ?*anyopaque,
) callconv(.c) void {
    _ = connection;
    _ = user_data;
    std.debug.print("failed to get d-bus name: {s}\n", .{name});
    std.debug.print("other daemon seem to be activated\n", .{});
}

pub fn startNotificationDaemon(notification_state: *NotificationState) u32 {
    return gio.busOwnName(.session, notifications_interface, .{}, onBusAcquired, onNameAcquired, onNameLost, notification_state, null);
}
