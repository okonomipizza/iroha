const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const layer_shell = @import("layer_shell.zig");
const gdk = @import("gdk");
const Clock = @import("./widget/clock.zig").Clock;
const Powermenu = @import("./widget/power.zig").PowerMenu;
const Music = @import("./widget/music.zig").Music;
const Notification = @import("./widget/notification.zig").Notification;
const jsonc = @import("zig_jsonc");
const config = @import("config.zig");


fn activate(app: *gtk.Application, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data) |data| {
        const messages = @as(*std.json.Value, @ptrCast(@alignCast(data))); 
        var window = gtk.ApplicationWindow.new(app);
        gtk.Window.setTitle(window.as(gtk.Window), "System Bar");
        gtk.Window.setDefaultSize(window.as(gtk.Window), 200, 10);

        loadCss() catch {
            std.posix.exit(1);
        };

        const style_context = gtk.Widget.getStyleContext(window.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "system-bar");

        // Make window style like system bar
        layer_shell.initForWindow(window);
        layer_shell.setLayer(window, layer_shell.GTK_LAYER_SHELL_LAYER_TOP);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_TOP, true);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_LEFT, true);
        layer_shell.setAnchor(window, layer_shell.GTK_LAYER_SHELL_EDGE_RIGHT, true);
        layer_shell.setExclusiveZone(window, 30);

        var main_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(main_box.as(gtk.Widget), gtk.Align.fill);
        gtk.Widget.setValign(main_box.as(gtk.Widget), gtk.Align.center);
        gtk.Window.setChild(window.as(gtk.Window), main_box.as(gtk.Widget));

        var left_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(left_box.as(gtk.Widget), gtk.Align.start);
        gtk.Widget.setValign(left_box.as(gtk.Widget), gtk.Align.center);

        var right_box = gtk.Box.new(gtk.Orientation.horizontal, 1);
        gtk.Widget.setHalign(right_box.as(gtk.Widget), gtk.Align.start);
        gtk.Widget.setValign(right_box.as(gtk.Widget), gtk.Align.center);

        // Create clock widget (JST)
        var clock = Clock.new(9);
        var menu = Powermenu.new();

        const allocator = std.heap.page_allocator;
        var music = Music.new(allocator);

        const clock_style_context = gtk.Widget.getStyleContext(clock.as(gtk.Widget));
        gtk.StyleContext.addClass(clock_style_context, "clock");
        gtk.StyleContext.addClass(clock_style_context, "clock-button");

        var norification = Notification.new(allocator, messages) catch {
            std.posix.exit(1);
        };

        gtk.Box.append(left_box, menu.as(gtk.Widget));
        gtk.Box.append(left_box, music.as(gtk.Widget));
        gtk.Box.append(right_box, norification.as(gtk.Widget));
        gtk.Box.append(right_box, clock.as(gtk.Widget));

        gtk.Box.append(main_box, left_box.as(gtk.Widget));

        var spacer = gtk.Box.new(gtk.Orientation.horizontal, 0);
        gtk.Widget.setHexpand(spacer.as(gtk.Widget), 1);
        gtk.Box.append(main_box, spacer.as(gtk.Widget));

        gtk.Box.append(main_box, right_box.as(gtk.Widget));

        gtk.Widget.show(window.as(gtk.Widget));

    }
}
pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var iroha_dir = try config.getConfigDir(allocator);
    defer iroha_dir.close();

    const file_name = "message.jsonc";

    var file = iroha_dir.openFile(file_name, .{.mode = .read_only}) catch |err| switch (err) {
        error.FileNotFound => blk: {
            var new_file = try iroha_dir.createFile(file_name, .{});
            const initial_data =
                \\{
                \\    "messages": [
                \\        "kick back",
                \\        "iris out",
                \\        "jane doe",
                \\        ]
                \\}
            ;
            try new_file.writeAll(initial_data);
            try new_file.sync();
            new_file.close();

        break :blk try iroha_dir.openFile(file_name, .{.mode = .read_only});
        },
        else => return err,
    };
    defer file.close();

    const file_size = try file.getEndPos();

    const msgs_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(msgs_buffer);

    var reader = file.reader(msgs_buffer);
    const messages = try reader.interface.readAlloc(allocator, file_size);

    var jsonc_parser = try jsonc.JsoncParser.init(allocator, messages);
    defer jsonc_parser.deinit();

    const message_json = try jsonc_parser.parse();
    if (message_json == .object) {
        const msgs = message_json.object.get("messages");
        if (msgs) |m| {
            if (m == .array) {
                std.debug.print("num of messages {d}\n", .{m.array.items.len});
            }
        }

    } else {
        std.debug.print("No messages", .{});
    }

    var app = gtk.Application.new("org.iroha.systembar", .{});
    defer app.unref();
        const message_ptr = try allocator.create(std.json.Value);
        message_ptr.* = message_json;

        _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, @ptrCast(message_ptr), .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);

    std.process.exit(@intCast(status));
}

fn loadCss() anyerror!void {
    const provider = gtk.CssProvider.new();

    const css_path: [*:0]const u8 = "./src/style.css";
    gtk.CssProvider.loadFromPath(provider, css_path);

    const display = gdk.Display.getDefault() orelse {
        return error.FailedToGetDisplay;
    };

    gtk.StyleContext.addProviderForDisplay(display, provider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
}
