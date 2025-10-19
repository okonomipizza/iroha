const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const gdkpixbuf = @import("gdkpixbuf");

const Action = enum {
    sleep,
    restart,
    shutdown,
};

const ICON_DIR = "assets/";

pub const SystemMenu = extern struct {
    parent_instance: Parent,

    const Self = @This();
    pub const Parent = gtk.Button;

    const Private = struct {
        menu_icon: ?*gtk.Image,
        popover: ?*gtk.Popover,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "IrohaPowerMenu",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new() *Self {
        var menu = gobject.ext.newInstance(Self, .{});
        const menu_style_context = gtk.Widget.getStyleContext(menu.as(gtk.Widget));
        gtk.StyleContext.addClass(menu_style_context, "system-button");
        return menu;
    }

    pub fn as(menu: *Self, comptime T: type) *T {
        return gobject.ext.as(T, menu);
    }

    fn init(menu: *Self, _: *Class) callconv(.c) void {
        var priv = menu.private();

        // Initialize private data
        priv.popover = null;

        // Create box to hold icon
        const box = gtk.Box.new(gtk.Orientation.horizontal, 0);

        const icon_image = gtk.Image.newFromIconName("view-grid-symbolic");
        priv.menu_icon = icon_image;

        // Set power icon (using Unicode symbol as fallback)
        gtk.Box.append(box, icon_image.as(gtk.Widget));
        gtk.Button.setChild(menu.as(gtk.Button), box.as(gtk.Widget));

        // Connect click signal
        _ = gtk.Button.signals.clicked.connect(menu, ?*anyopaque, &handleClicked, null, .{});

        // Create popover menu
        menu.createPopover();
    }

    fn createPopover(menu: *Self) void {
        // Create popover
        const popover = gtk.Popover.new();
        gtk.Widget.setParent(popover.as(gtk.Widget), menu.as(gtk.Widget));
        gtk.Popover.setHasArrow(popover, 0);

        gtk.Widget.setMarginTop(popover.as(gtk.Widget), 0);
        gtk.Widget.setMarginBottom(popover.as(gtk.Widget), 0);
        gtk.Widget.setMarginStart(popover.as(gtk.Widget), 0);
        gtk.Widget.setMarginEnd(popover.as(gtk.Widget), 0);

        menu.private().popover = popover;
        const popover_style_context = gtk.Widget.getStyleContext(popover.as(gtk.Widget));
        gtk.StyleContext.addClass(popover_style_context, "system-menu");

        _ = gtk.Popover.signals.activate_default.connect(popover, ?*anyopaque, &onPopoverShow, menu, .{});
        _ = gtk.Popover.signals.closed.connect(popover, ?*anyopaque, &onPopoverHide, menu, .{});

        // Create vertical box for menu items
        const box = gtk.Box.new(gtk.Orientation.vertical, 0);
        gtk.Widget.setSizeRequest(box.as(gtk.Widget), 250, -1);
        gtk.Widget.setMarginTop(box.as(gtk.Widget), 0);
        gtk.Widget.setMarginBottom(box.as(gtk.Widget), 0);
        gtk.Widget.setMarginStart(box.as(gtk.Widget), 0);
        gtk.Widget.setMarginEnd(box.as(gtk.Widget), 0);
        gtk.Popover.setChild(popover, box.as(gtk.Widget));

        const box_style_context = gtk.Widget.getStyleContext(box.as(gtk.Widget));
        gtk.StyleContext.addClass(box_style_context, "system-menu-box");

        // Create menu items
        menu.createMenuItem(box, "sleep", Action.sleep);
        menu.createMenuItem(box, "restart", Action.restart);
        menu.createMenuItem(box, "shutdown", Action.shutdown);
    }

    fn onPopoverShow(_: *gtk.Popover, menu: ?*anyopaque) callconv(.c) void {
        if (menu) |m| {
            const power_menu: *Self = @ptrCast(@alignCast(m));
            const style_context = gtk.Widget.getStyleContext(power_menu.as(gtk.Widget));
            gtk.StyleContext.addClass(style_context, "active");
        }
    }

    fn onPopoverHide(_: *gtk.Popover, menu: ?*anyopaque) callconv(.c) void {
        if (menu) |m| {
            const power_menu: *Self = @ptrCast(@alignCast(m));
            const style_context = gtk.Widget.getStyleContext(power_menu.as(gtk.Widget));
            gtk.StyleContext.removeClass(style_context, "active");
        }
    }

    fn createMenuItem(menu: *Self, box: *gtk.Box, label: [*:0]const u8, action: Action) void {
        const container = gtk.Box.new(gtk.Orientation.horizontal, 0);
        gtk.Widget.setMarginStart(container.as(gtk.Widget), 1);
        gtk.Widget.setMarginEnd(container.as(gtk.Widget), 1);

        const button = gtk.Button.newWithLabel(label);

        // Set button styling
        const style_context = gtk.Widget.getStyleContext(button.as(gtk.Widget));
        gtk.StyleContext.addClass(style_context, "system-menu-item");
        gtk.StyleContext.removeClass(style_context, "button");

        // Set button properties
        gtk.Widget.setHalign(button.as(gtk.Widget), gtk.Align.fill);
        gtk.Widget.setHexpand(button.as(gtk.Widget), 1);
        gtk.Widget.setVexpand(button.as(gtk.Widget), 0);

        gtk.Box.append(container, button.as(gtk.Widget));

        const button_child = gtk.Button.getChild(button);
        if (button_child) |child| {
            gtk.Widget.setHalign(child, gtk.Align.start);
        }

        // Connect button signal with action data
        switch (action) {
            .sleep => _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &handleSleep, menu, .{}),
            .restart => _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &handleRestart, menu, .{}),
            .shutdown => _ = gtk.Button.signals.clicked.connect(button, ?*anyopaque, &handleShutdown, menu, .{}),
        }

        gtk.Box.append(box, container.as(gtk.Widget));
    }

    fn handleClicked(menu: *Self, _: ?*anyopaque) callconv(.c) void {
        if (menu.private().popover) |popover| {
            gtk.Popover.popup(popover);
        }
    }

    fn handleSleep(_: *gtk.Button, menu: ?*anyopaque) callconv(.c) void {
        if (menu) |m| {
            const power_menu: *Self = @ptrCast(@alignCast(m));
            power_menu.hidePopover();
            power_menu.executePowerAction(.sleep);
        }
    }

    fn handleRestart(_: *gtk.Button, menu: ?*anyopaque) callconv(.c) void {
        if (menu) |m| {
            const power_menu: *Self = @ptrCast(@alignCast(m));
            power_menu.hidePopover();
            power_menu.executePowerAction(.restart);
        }
    }

    fn handleShutdown(_: *gtk.Button, menu: ?*anyopaque) callconv(.c) void {
        if (menu) |m| {
            const power_menu: *Self = @ptrCast(@alignCast(m));
            power_menu.hidePopover();
            power_menu.executePowerAction(.shutdown);
        }
    }

    fn hidePopover(menu: *Self) void {
        if (menu.private().popover) |popover| {
            gtk.Popover.popdown(popover);
        }
    }

    fn executePowerAction(menu: *Self, action: Action) void {
        // Log the action for debugging
        switch (action) {
            .sleep => std.debug.print("Executing: Sleep\n", .{}),
            .restart => std.debug.print("Executing: Restart\n", .{}),
            .shutdown => std.debug.print("Executing: Shutdown\n", .{}),
        }

        // Execute system commands
        const allocator = std.heap.page_allocator;

        const command = switch (action) {
            .sleep => "systemctl suspend",
            .restart => "systemctl reboot",
            .shutdown => "systemctl poweroff",
        };

        // Execute command in background
        menu.executeSystemCommand(allocator, command) catch |err| {
            std.debug.print("Failed to execute {s}: {}\n", .{ command, err });
        };
    }

    fn executeSystemCommand(menu: *Self, allocator: std.mem.Allocator, command: []const u8) !void {
        _ = menu; // suppress unused parameter warning

        // Split command into arguments
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(allocator);

        var iter = std.mem.splitAny(u8, command, " ");
        while (iter.next()) |arg| {
            try args.append(allocator, arg);
        }

        // Create null-terminated arguments for execvp
        var c_args: std.ArrayList([*:0]const u8) = .empty;
        defer c_args.deinit(allocator);

        for (args.items) |arg| {
            const c_arg = try allocator.dupeZ(u8, arg);
            try c_args.append(allocator, c_arg);
        }

        // Execute command
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = args.items,
        }) catch |err| {
            std.debug.print("Command execution failed: {}\n", .{err});
            return err;
        };

        if (result.term.Exited != 0) {
            std.debug.print("Command failed with exit code: {}\n", .{result.term.Exited});
        }

        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    fn setIcon(menu: *Self) void {
        const priv = menu.private();
        gtk.Image.setFromIconName(priv.power_button_icon, "");
    }

    fn dispose(menu: *Self) callconv(.c) void {
        // Clean up popover
        if (menu.private().popover) |popover| {
            gtk.Widget.unparent(popover.as(gtk.Widget));
            menu.private().popover = null;
        }

        // Call parent dispose
        gobject.Object.virtual_methods.dispose.call(Class.parent, menu.as(Parent));
    }

    fn private(menu: *Self) *Private {
        return gobject.ext.impl_helpers.getPrivate(menu, Private, Private.offset);
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
