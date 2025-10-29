const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");
const Config = @import("../config.zig").Config;

/// Supported Notifition type
pub const NotificationType = enum {
    config, // Loaded from app config file
    notify, // Received from D-bus Notify
};

/// D-bus notification data
pub const NotificationData = struct {
    app_name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    id: ?u32,
    type: NotificationType,

    const Self = @This();

    /// Create a notification from D-bus notification event
    /// Used when receiving notifications from D-bus
    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, message: []const u8, id: u32) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const app_name_cstr = try allocator.dupeZ(u8, app_name);
        errdefer allocator.free(app_name_cstr);

        const message_cstr = try allocator.dupeZ(u8, message);
        errdefer allocator.free(message_cstr);

        self.* = .{
            .app_name = app_name_cstr,
            .message = message_cstr,
            .id = id,
            .type = .notify,
        };

        return self;
    }

    /// Create a notification from app configuration.
    /// Used when loading notifications from the config file.
    pub fn fromConfig(allocator: std.mem.Allocator, message: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const app_name_cstr = try allocator.dupeZ(u8, "iroha");
        errdefer allocator.free(app_name_cstr);

        const message_cstr = try allocator.dupeZ(u8, message);
        errdefer allocator.free(message_cstr);

        self.* = .{
            .app_name = app_name_cstr,
            .message = message_cstr,
            .id = null,
            .type = .config,
        };

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.app_name) |app_name| {
            allocator.free(std.mem.span(app_name));
        }
        if (self.message) |message| {
            allocator.free(std.mem.span(message));
        }
        allocator.destroy(self);
    }
};

/// `NotificationNode` is managed by `NotificationManager`
/// as a content of doubly linked list.
const NotificationNode = struct {
    data: *NotificationData,
    prev: ?*NotificationNode,
    next: ?*NotificationNode,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator, data: *NotificationData) !*Self {
        const node = try allocator.create(Self);
        node.* = Self{
            .data = data,
            .prev = null,
            .next = null,
        };
        return node;
    }

    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Manages notifications in a doubly linked list.
const NotificationManager = struct {
    head: ?*NotificationNode,
    tail: ?*NotificationNode,
    current: ?*NotificationNode,
    max_couont: usize,
    count: usize,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_count: usize, config: *Config) !*Self {
        const manager = try allocator.create(Self);
        manager.* = .{
            .head = null,
            .tail = null,
            .current = null,
            .count = 0,
            .max_couont = max_count,
            .allocator = allocator,
            .mutex = .{},
        };

        // Load default messages that dispalyed at notification bar from config file
        if (config.message_config.messages == .array) {
            for (config.message_config.messages.array.items) |item| {
                if (item == .string) {
                    const data = try NotificationData.fromConfig(allocator, item.string);
                    try manager.append(data);
                }
            }
        }
        return manager;
    }

    pub fn append(self: *Self, data: *NotificationData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count >= self.max_couont) {
            self.removeOldest();
        }

        const new_node = try NotificationNode.create(self.allocator, data);

        if (self.head == null) {
            self.head = new_node;
            self.tail = new_node;
            self.current = new_node;
        } else if (self.current) |current| {
            if (self.tail == current) {
                current.next = new_node;
                new_node.prev = current;
                self.tail = new_node;
            } else {
                new_node.next = current.next;
                new_node.prev = current;
                if (current.next) |current_next| {
                    current_next.prev = new_node;
                }
                current.next = new_node;
            }
        }

        self.count += 1;
    }

    fn removeOldest(self: *Self) void {
        if (self.head) |head| {
            self.head = head.next;
            if (self.current == head) {
                self.current = self.head;
            }
            head.destroy(self.allocator);
            self.count -= 1;

            if (self.head == null) {
                self.tail = null;
                self.current = null;
            } else if (self.head) |new_head| {
                new_head.prev = null;
            }
        }
    }

    pub fn getCurrent(self: *const Self) ?*NotificationNode {
        return self.current;
    }

    /// Advance to next node and return it.
    /// If the current node is the tail, wrap around to the head.
    /// Returns null if the list is empty.
    pub fn next(self: *Self) ?*NotificationNode {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current) |old_current| {
            if (self.tail == old_current) {
                self.current = self.head;
            } else {
                self.current = old_current.next;
            }
            return self.current;
        }
        return null;
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.head) |head| {
            self.head = head.next;
            head.destroy(self.allocator);
        }
        self.tail = null;
        self.current = null;
        self.count = 0;
    }

    pub fn deinit(self: *Self) void {
        self.clear();
        self.allocator.destroy(self);
    }
};

/// GObject that manages notification state and emits signals
pub const NotificationState = extern struct {
    parent_instance: gobject.Object,

    pub const Parent = gobject.Object;

    const Private = struct {
        manager: ?*NotificationManager,
        allocator: std.mem.Allocator,

        pub var offset: c_int = 0;
    };

    const Self = @This();

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "IrohaNotificationState",
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    // Signal ID
    var signal_notification_received: c_uint = 0;

    pub fn new(allocator: std.mem.Allocator, max_count: usize, config: *Config) !*Self {
        const self = gobject.ext.newInstance(Self, .{});
        errdefer self.unref();

        const priv = self.private();
        priv.allocator = allocator;
        priv.manager = try NotificationManager.init(allocator, max_count, config);


        return self;
    }

    pub fn addNotification(self: *Self, app_name: []const u8, message: []const u8, id: u32) !void {
        const allocator = self.private().allocator;
        const data = try NotificationData.init(allocator, app_name, message, id);
        const priv = self.private();
        if (priv.manager) |manager| {
            try manager.append(data);

            const ctx = try priv.allocator.create(EmitContext);
            ctx.* = .{ .state = self, .data = data.* };
        }
    }

    pub fn getCurrent(self: *Self) ?*NotificationData {
        const priv = self.private();
        if (priv.manager) |manager| {
            if (manager.getCurrent()) |node| {
                return node.data;
            }
        }
        return null;
    }

    pub fn next(self: *Self) ?*NotificationData {
        const priv = self.private();
        if (priv.manager) |manager| {
            if (manager.next()) |node| {
                return node.data;
            }
        }
        return null;
    }

    pub fn clear(self: *Self) void {
        const priv = self.private();
        if (priv.manager) |manager| {
            manager.clear();
        }
    }

    const EmitContext = struct {
        state: *Self,
        data: NotificationData,
    };

    fn finalize(self: *Self) callconv(.c) void {
        const priv = self.private();

        if (priv.manager) |manager| {
            manager.deinit();
            priv.manager = null;
        }

        gobject.Object.virtual_methods.finalize.call(Class.parent, self.as(gobject.Object));
    }

    fn private(self: *Self) *Private {
        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(self: *Self, comptime T: type) *T {
        if (T == gobject.Object or @hasDecl(T, "parent_instance")) {
            return @ptrCast(self);
        }
        return gobject.ext.as(T, self);
    }

    pub fn ref(self: *Self) *Self {
        return gobject.ext.ref(self, Self);
    }

    pub fn unref(self: *Self) void {
        gobject.Object.unref(self.as(gobject.Object));
    }

    pub const Class = extern struct {
        parent_class: gobject.Object.Class,
        var parent: *gobject.Object.Class = undefined;

        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
        }
    };
};

/// A widget that displays messages with animations.
///
/// Shows notifications that can be cycled through with visual transitions.
pub const Notification = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Box;

    const PADDING_HORIZONTAL: c_int = 8;

    const Private = struct {
        // manager: ?*MessageManager,
        notification_state: ?*NotificationState,
        handler_id: c_ulong,

        // current_node: ?*MessageNode,
        // Currently displayed message.
        // current_message: ?[*:0]const u8, // Currently displayed message

        // Widgets for display
        main_hbox: *gtk.Box,
        scrolled_window: *gtk.ScrolledWindow, // Enables horizontal scrolling for the label content
        label_hbox: *gtk.Box,
        label: *gtk.Label, // Displays the media information string (title | artist)

        // For Animation
        scroll_tick_id: c_uint, // For scroll animation tick callback
        frame_count: c_uint, // Counter for frame-based timing
        scroll_position: f64, // Current position of label at scrolled window
        widget_width: c_int, // Width of message widget
        text_width: c_int, // Width of the message label for display

        var offset: c_int = 0;
    };

    const Self = @This();

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "IrohaNotification",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    /// Returns initialized instance
    pub fn new(notification_state: *NotificationState) *Notification {
        var notification = gobject.ext.newInstance(Notification, .{});

        const notification_style_context = gtk.Widget.getStyleContext(notification.as(gtk.Widget));
        gtk.StyleContext.addClass(notification_style_context, "notification");

        var priv = notification.private();
        priv.notification_state = notification_state;

        priv.handler_id = gobject.signalConnectData(
            notification_state.as(gobject.Object),
            "notification-received",
            @as(gobject.Callback, @ptrCast(&onNotificationReceived)),
            notification,
            null,
            .{},
        );

        if (notification_state.getCurrent()) |current_data| {
            notification.updateDisplay(current_data);
        } else {
            gtk.Label.setText(priv.label, "No notification");
        }

        notification.startAnimation();

        return notification;
    }

    /// Calculate width of available area for text animation
    fn availableWidth(self: *Notification) c_int {
        const priv = self.private();
        return priv.widget_width - PADDING_HORIZONTAL * 2;
    }

    fn updateDisplay(self: *Notification, data: *const NotificationData) void {
        var priv = self.private();

        const message_to_show = data.message orelse "nothig to show";

        gtk.Label.setText(priv.label, message_to_show);

        // Recaluculate width of widget
        var req: gtk.Requisition = undefined;
        gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
        priv.text_width = req.f_width;

        const available_width = self.availableWidth();
        priv.scroll_position = @as(f64, @floatFromInt(available_width));
    }

    fn onNotificationReceived(
        state: *NotificationState,
        notif_data: *const NotificationData,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        _ = user_data;
        // const self = @as(*Notification, @ptrCast(@alignCast(user_data.?)));
        const app_name = notif_data.app_name orelse "app_name";
        const message = notif_data.message orelse "message";
        const id = notif_data.id orelse 0;
        state.addNotification(std.mem.span(app_name), std.mem.span(message), id) catch {
            std.debug.print("error occured\n", .{});
        };
    }

    fn init(notification: *Notification, _: *Class) callconv(.c) void {
        var priv = notification.private();

        priv.notification_state = null;
        priv.handler_id = 0;
        priv.scroll_position = 0.0;
        priv.scroll_tick_id = 0;
        priv.frame_count = 0;
        priv.widget_width = 300;
        priv.text_width = 0;

        priv.main_hbox = gtk.Box.new(gtk.Orientation.horizontal, 0);
        gtk.Widget.setMarginStart(priv.main_hbox.as(gtk.Widget), PADDING_HORIZONTAL);
        gtk.Widget.setMarginEnd(priv.main_hbox.as(gtk.Widget), PADDING_HORIZONTAL);

        priv.scrolled_window = gtk.ScrolledWindow.new();
        gtk.ScrolledWindow.setPolicy(
            priv.scrolled_window,
            gtk.PolicyType.automatic,
            gtk.PolicyType.never,
        );
        // Hide horizontal scroll bar
        gtk.Widget.setVisible(gtk.ScrolledWindow.getHscrollbar(priv.scrolled_window).as(gtk.Widget), 0);
        const scroll_width = priv.widget_width - PADDING_HORIZONTAL * 2;
        gtk.Widget.setSizeRequest(priv.scrolled_window.as(gtk.Widget), scroll_width, 20);
        gtk.Widget.setOverflow(priv.scrolled_window.as(gtk.Widget), gtk.Overflow.hidden);

        priv.label_hbox = gtk.Box.new(gtk.Orientation.horizontal, 10);
        gtk.ScrolledWindow.setChild(priv.scrolled_window, priv.label_hbox.as(gtk.Widget));

        priv.label = gtk.Label.new("No message");
        gtk.Widget.setSizeRequest(priv.label.as(gtk.Widget), -1, 20);
        gtk.Label.setEllipsize(priv.label, pango.EllipsizeMode.none);
        gtk.Label.setSingleLineMode(priv.label, 1);
        gtk.Box.append(priv.label_hbox, priv.label.as(gtk.Widget));

        gtk.Box.append(priv.main_hbox, priv.scrolled_window.as(gtk.Widget));
        gtk.Box.append(notification.as(gtk.Box), priv.main_hbox.as(gtk.Widget));

        gtk.Widget.show(notification.as(gtk.Widget));
    }

    fn startAnimation(notification: *Notification) void {
        var priv = notification.private();
        // Stop existing tick callbacks
        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(notification.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }

        priv.scroll_tick_id = gtk.Widget.addTickCallback(notification.as(gtk.Widget), &animateScrollTick, notification, null);
    }

    fn animateScrollTick(widget: *gtk.Widget, frame_clock: *gdk.FrameClock, user_data: ?*anyopaque) callconv(.c) c_int {
        _ = widget;
        _ = frame_clock;

        if (user_data) |data| {
            const notification: *Notification = @ptrCast(@alignCast(data));
            var priv = notification.private();

            // Scroll to left from right.
            const scroll_speed = 0.4;
            priv.scroll_position -= scroll_speed;

            // Calculate the place where the animated text completely hides to the end.
            // const available_width = notification.availableWidth();
            const text_hidden = @as(f64, @floatFromInt(-priv.text_width));

            if (priv.scroll_position <= text_hidden) {
                if (priv.notification_state) |state| {
                    if (state.next()) |next_data| {
                        notification.updateDisplay(next_data);
                        std.posix.nanosleep(0, 900_000_000);
                    }
                }
            }

            // Offset text to the right by setting label margin
            if (priv.scroll_position > 0) {
                // In case of text start shown on display.
                gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), @as(c_int, @intFromFloat(priv.scroll_position)));
                gtk.Widget.setMarginEnd(priv.label.as(gtk.Widget), 0);
                gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), 0.0);
            } else {
                // In case of text start is at left of start of display.
                gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), 0);
                const margin_end = @as(c_int, @intFromFloat((-priv.scroll_position)));
                gtk.Widget.setMarginEnd(priv.label.as(gtk.Widget), margin_end);
                gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), -priv.scroll_position);
            }

            return 1;
        }
        return 0;
    }

    fn dispose(notification: *Notification) callconv(.c) void {
        var priv = notification.private();

        // Stop animation
        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(notification.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }

        // Remove signal connection
        //
        if (priv.notification_state) |state| {
            if (priv.handler_id != 0) {
                gobject.signalHandlerDisconnect(state.as(gobject.Object), priv.handler_id);
                priv.handler_id = 0;
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, notification.as(Parent));
    }

    fn private(self: *Notification) *Private {
        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(music: *Notification, comptime T: type) *T {
        return gobject.ext.as(T, music);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        pub const Instance = Notification;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }
    };
};
