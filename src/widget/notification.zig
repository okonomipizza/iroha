const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");

/// A node in a doubly linked list that stores a message string.
const MessageNode = struct {
    message: [*:0]const u8,
    prev: ?*MessageNode,
    next: ?*MessageNode,

    const Self = @This();

    /// Creates a new MessageNode with the given message.
    /// The message is duplicated and owned by the node.
    ///
    /// Returns an error if allocation fails.
    pub fn create(allocator: std.mem.Allocator, message: []const u8) !*Self {
        const node = try allocator.create(Self);
        const c_message = try allocator.dupeZ(u8, message);
        node.* = Self{
            // .message = try allocator.dupe(u8, message),
            .message = c_message.ptr,
            .prev = null,
            .next = null,
        };
        return node;
    }

    /// Frees the memory used by this node, including its message.
    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(std.mem.span(self.message));
        allocator.destroy(self);
    }
};

/// Manages a doubly linked list of messages for display in a Notification widget.
///
/// Messages can be navigated forward and backward, with a maximum capacity limit.
const MessageManager = struct {
    /// First node in the message list (null if empty).
    head: ?*MessageNode,
    /// Last node in the message list (null if empty).
    tail: ?*MessageNode,
    /// Currently displayed/selected message node (null if empty).
    current: ?*MessageNode,

    /// Maximum capacity lilmit.
    max_count: usize,
    /// Number of nodes currently stored in list.
    count: usize,

    allocator: std.mem.Allocator,

    const Self = @This();

    /// Creates a new MessageManager with the specified maximum message capacity.
    ///
    /// Caller must call `deinit()` when done to free all resources.
    /// The allcoator should typically be an ArenaAllocator.allocator() for automatic cleanup.
    /// When using ArenaAllocator, calling `deinit()` is optional as all memory will be
    /// freed when the parent arena is deinitialized.
    pub fn init(allocator: std.mem.Allocator, max_count: usize) !*Self {
        const manager = try allocator.create(Self);
        manager.* = .{
            .head = null,
            .tail = null,
            .current = null,
            .count = 0,
            .max_count = max_count,
            .allocator = allocator,
        };

        return manager;
    }

    /// Create a new MessageNode to the end of the list
    /// If the list exceeds `max_count`, the oldest message is automatically removed.
    /// The message string is duplicated internally.
    pub fn append(self: *Self, message: []const u8) !void {
        if (self.count >= self.max_count) {
            self.removeOldest();
        }

        const new_node = try MessageNode.create(self.allocator, message);

        if (self.tail) |tail| {
            tail.next = new_node;
            new_node.prev = tail;
            self.tail = new_node;
        } else {
            self.head = new_node;
            self.tail = new_node;
        }

        self.count += 1;
    }

    /// Remove oldest node from the list.
    fn removeOldest(self: *Self) void {
        if (self.head) |head| {
            self.head = head.next;
            head.destroy(self.allocator);
            self.count -= 1;

            if (self.head == null) {
                self.tail = null;
            }
        }
    }

    /// Returns current Node
    pub fn getCurrentNode(self: *const Self) ?*MessageNode {
        return self.current;
    }

    /// Advances to the next messages in the list and returns it.
    ///
    /// The list wraps around: after the last message, it returns to the first.
    /// Returns null if the list is empty.
    pub fn next(self: *Self) ?*MessageNode {
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

    /// Clear all nodes
    pub fn clear(self: *Self) void {
        while (self.head) |head| {
            self.head = head.next;
            head.destroy(self.allocator);
        }
        self.tail = null;
        self.count = 0;
    }

    /// Deinitializes the MessageManager.
    ///
    /// This is a no-op when using ArenaAllocator, as all memory is freed when the parent
    /// arena is deinitialized. This method exists for API consistency and to avoid confusion
    /// for users expecting a deinit() counterpart to init().
    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// A widget that displays messages with animations.
///
/// Shows notifications that can be cycled through with visual transitions.
pub const Notification = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Box;

    const PADDING_HORIZONTAL: c_int = 8;

    const Private = struct {
        manager: ?*MessageManager,
        current_node: ?*MessageNode,
        // Currently displayed message.
        current_message: ?[*:0]const u8, // Currently displayed message

        main_hbox: *gtk.Box,
        scrolled_window: *gtk.ScrolledWindow, // Enables horizontal scrolling for the label content
        label_hbox: *gtk.Box,
        label: *gtk.Label, // Displays the media information string (title | artist)

        scroll_tick_id: c_uint, // For scroll animation tick callback
        frame_count: c_uint, // Counter for frame-based timing
        scroll_position: f64, // Current position of label at scrolled window

        widget_width: c_int, // Width of message widget
        // icon_width: c_int,
        text_width: c_int, // Width of the message label for display
        // 
        arena: std.heap.ArenaAllocator,

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
    pub fn new(child_allocator: std.mem.Allocator, config: ?*std.json.Value) !*Notification {
        var notification = gobject.ext.newInstance(Notification, .{});

        // Add CSS class
        const notification_style_context = gtk.Widget.getStyleContext(notification.as(gtk.Widget));
        gtk.StyleContext.addClass(notification_style_context, "notification");

        // Reference to rivate fields
        var priv = notification.private();

        priv.arena = std.heap.ArenaAllocator.init(child_allocator);
        const allocator = priv.arena.allocator();

        priv.manager = try MessageManager.init(allocator, 10);

        if (priv.manager) |manager| {
            if (config) |cfg| {
                if (cfg.* == .array) {
                    for (cfg.array.items) |item| {
                        try manager.append(item.string);
                    }
                }
            }
            manager.current = manager.head;
            priv.current_node = manager.current;

            if (priv.current_node) |cn| {
                priv.current_message = cn.message;
            } else {
                try manager.append("No message");
                manager.current = manager.head;
                if (manager.current) |cn| {
                    priv.current_message = cn.message;
                    priv.current_node = cn;
                }
            }

            if (priv.current_message) |t| {
                gtk.Label.setText(priv.label, t);
            }
        }

        var req: gtk.Requisition = undefined;
        gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
        priv.text_width = req.f_width;

        const available_width = notification.availableWidth();
        priv.scroll_position = @as(f64, @floatFromInt(available_width));

        notification.initializeWithAllocator();

        return notification;
    }

    /// Calculate width of available area for text animation
    fn availableWidth(self: *Notification) c_int {
        const priv = self.private();
        return priv.widget_width - PADDING_HORIZONTAL * 2;
    }

    fn setDisplayedMessage(notification: *Notification, allocator: std.mem.Allocator, msg: []const u8) !void {
        var priv = notification.private();
        if (priv.current_message) |curr_msg| {
            allocator.free(std.mem.span(curr_msg));
        }
        const c_message = try allocator.dupeZ(u8, msg);
        priv.current_message = c_message.ptr;
    }

    fn initializeWithAllocator(notification: *Notification) void {
        startAnimation(notification);
    }

    fn init(notification: *Notification, _: *Class) callconv(.c) void {
        var priv = notification.private();

        priv.current_message = null;
        priv.scroll_position = 0.0;
        priv.scroll_tick_id = 0;
        priv.frame_count = 0;
        priv.widget_width = 300;
        priv.text_width = 0;
        priv.arena = undefined;

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
            const available_width = notification.availableWidth();
            const text_hidden = @as(f64, @floatFromInt(-priv.text_width));

            if (priv.scroll_position <= text_hidden) {
                // Change displayed message to next.
                priv.scroll_position = @as(f64, @floatFromInt(available_width));
                if (priv.manager) |manager| {
                    if (manager.next()) |next_node| {
                        gtk.Label.setText(priv.label, next_node.message);

                        gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), 0);
                        gtk.Widget.setMarginEnd(priv.label.as(gtk.Widget), 0);
                        gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), 0.0);

                        priv.current_message = next_node.message;

                        var req: gtk.Requisition = undefined;
                        gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
                        priv.text_width = req.f_width;
                        priv.scroll_position = @as(f64, @floatFromInt(available_width));

                        std.posix.nanosleep(0, 900);
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

    fn dispose(music: *Notification) callconv(.c) void {
        var priv = music.private();

        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }

        priv.arena.deinit();
        priv.manager = null;

        gobject.Object.virtual_methods.dispose.call(Class.parent, music.as(Parent));
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
