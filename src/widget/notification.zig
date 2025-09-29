const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");
const JsonValue = @import("jsonpico").JsonValue;

/// A node in a doubly linked list that stores a message string.
const MessageNode = struct {
    message: []const u8,
    prev: ?*MessageNode,
    next: ?*MessageNode,

    const Self = @This();

    /// Creates a new MessageNode with the given message.
    /// The message is duplicated and owned by the node.
    ///
    /// Returns an error if allocation fails.
    pub fn create(allocator: std.mem.Allocator, message: []const u8) !*Self {
        const node = try allocator.create(Self);
        node.* = Self {
            .message = try allocator.dupe(u8, message),
            .prev = null,
            .next = null,
        };
        return node;
    }

    /// Frees the memory used by this node, including its message.
    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
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

    pub fn deinit(self: *Self) void {
        self.clear();
        self.allocator.destroy(self);
    }


};

/// A widget that displays messages with animations.
///
/// Shows notifications that can be cycled through with visual transitions.
pub const Notification = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Box;
    
    const Private = struct {
        manager: ?*MessageManager,
        current_node: ?*MessageNode,
        // Currently displayed message.
        //
        current_message: ?[*:0]u8, // Currently displayed message
        
        main_hbox: *gtk.Box,
        icon_button: *gtk.Button,
        icon: *gtk.Image,
        scrolled_window: *gtk.ScrolledWindow, // Enables horizontal scrolling for the label content
        label_hbox: *gtk.Box,
        label: *gtk.Label, // Displays the media information string (title | artist)

        scroll_tick_id: c_uint, // For scroll animation tick callback
        frame_count: c_uint, // Counter for frame-based timing
        scroll_position: f64, // Current position of label at scrolled window
        
        widget_width: c_int, // Width of message widget
        icon_width: c_int,
        text_width: c_int, // Width of the message label for display
        allocator: ?std.mem.Allocator,
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
    pub fn new(allocator: std.mem.Allocator, config: ?*JsonValue) !*Notification {
        var notification = gobject.ext.newInstance(Notification, .{});
        const notification_style_context = gtk.Widget.getStyleContext(notification.as(gtk.Widget));
        gtk.StyleContext.addClass(notification_style_context, "notification");
        notification.setIcon();

        var priv = notification.private();
        priv.manager = try MessageManager.init(allocator, 10);
        if (priv.manager) |manager| {
            if (config) |cfg| {
                if (cfg.* == .object) {
                    if (cfg.object.value.get("messages")) |messages| {
                        if (messages == .array) {
                             for (messages.array.value.items) |item| {
                                try manager.append(item.string.value.items);
                            }
                        }
                    }
                }
            }
            manager.current = manager.head;

            // Set the message to be displayed.
            if (manager.current) |cur_node| {
                try setDisplayedMessage(notification, allocator, cur_node.message);
            } else {
                const template = "No message";
                try setDisplayedMessage(notification, allocator, template);
            }
            if (priv.current_message) |t| {
                gtk.Label.setText(priv.label, t);
            }
        }

        var req: gtk.Requisition = undefined;
        gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
        priv.text_width = req.f_width;

        priv.allocator = allocator;

        const available_width = notification.availableWidth();
        priv.scroll_position = @as(f64, @floatFromInt(available_width));

        notification.initializeWithAllocator();
        return notification;
    }

    /// Calculate width of available area for text animation
    fn availableWidth(self: *Notification) c_int {
        const priv = self.private();
        return priv.widget_width - priv.icon_width - 8; // 8 is a padding width
    }

    fn setDisplayedMessage(notification: *Notification, allocator: std.mem.Allocator, msg: []const u8) !void {
        var priv = notification.private();
        if (priv.current_message) |curr_msg| {
            allocator.free(std.mem.span(curr_msg));
        }
        const c_message = try allocator.dupeZ(u8, msg);
        priv.current_message = c_message.ptr;
    }

    fn setIcon(music: *Notification) void {
        const priv = music.private();
        gtk.Image.setFromIconName(priv.icon, "view-list");
        return;
    }

    fn updateIconForPlayingState(music: *Notification, is_playing: bool) void {
        const priv = music.private();
        priv.is_playing = is_playing;
        music.setIcon();
    }

    fn initializeWithAllocator(notification: *Notification) void {
        const priv = notification.private();
        if (priv.allocator == null) {
            std.debug.print("Warning: allocator not set\n", .{});
            return;
        }
        startAnimation(notification);
    }
    
    fn init(notification: *Notification, _: *Class) callconv(.c) void {
        var priv = notification.private();
        
        priv.current_message = null;
        priv.scroll_position = 0.0;
        priv.scroll_tick_id = 0;
        priv.frame_count = 0;
        priv.widget_width = 300;
        priv.icon_width = 24;
        priv.text_width = 0;
        priv.allocator = null;

        priv.main_hbox = gtk.Box.new(gtk.Orientation.horizontal, 8);
        priv.icon_button = gtk.Button.new();
        priv.icon = gtk.Image.new();

        // Icon button configuration
        gtk.Button.setChild(priv.icon_button, priv.icon.as(gtk.Widget));
        gtk.Widget.setSizeRequest(priv.icon_button.as(gtk.Widget), priv.icon_width, 20);
        gtk.Widget.setHalign(priv.icon_button.as(gtk.Widget), gtk.Align.start);
        gtk.Widget.setValign(priv.icon_button.as(gtk.Widget), gtk.Align.center);
        // Apply CSS styling to icon button and icon
        const button_style_context = gtk.Widget.getStyleContext(priv.icon_button.as(gtk.Widget));
        gtk.StyleContext.addClass(button_style_context, "notification-icon-button");
        const icon_style_context = gtk.Widget.getStyleContext(priv.icon.as(gtk.Widget));
        gtk.StyleContext.addClass(icon_style_context, "notification-icon");

        _ = gtk.Button.signals.clicked.connect(priv.icon_button, *Notification, &onIconButtonClicked, notification, .{});

        gtk.Box.append(priv.main_hbox, priv.icon_button.as(gtk.Widget));

        priv.scrolled_window = gtk.ScrolledWindow.new();
        gtk.ScrolledWindow.setPolicy(
            priv.scrolled_window, 
            gtk.PolicyType.automatic, 
            gtk.PolicyType.never,
        );
        // Hide horizontal scroll bar
        gtk.Widget.setVisible(gtk.ScrolledWindow.getHscrollbar(priv.scrolled_window).as(gtk.Widget), 0);
        const scroll_width = priv.widget_width - priv.icon_width - 8; // 8 is a padding left value
        gtk.Widget.setSizeRequest(priv.scrolled_window.as(gtk.Widget), scroll_width, 20);

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

    /// Control audio playback state
    fn onIconButtonClicked(button: *gtk.Button, notification: *Notification) callconv(.c) void {
        _ = button;
        _ = notification;

        // const priv = music.private();
        //
        // const allocator = priv.allocator orelse {
        //     std.debug.print("Allocator not available for button click\n", .{});
        //     return;
        // };
        //
        // // Retrieve currently playing media metadata using playctl
        // const status_result = std.process.Child.run(.{
        //     .allocator = allocator,
        //     .argv = &[_][]const u8{ "playerctl", "status" },
        // }) catch |err| {
        //     std.debug.print("Failed to get player status: {}\n", .{err});
        //     return;
        // };
        // defer allocator.free(status_result.stdout);
        // defer allocator.free(status_result.stderr);
        //
        // if (status_result.term.Exited == 0) {
        //     const status = std.mem.trim(u8, status_result.stdout, "\n\r ");
        //
        //     const toggle_result = std.process.Child.run(.{
        //         .allocator = allocator,
        //         .argv = &[_][]const u8{ "playerctl", "play-pause" },
        //     }) catch |err| {
        //         std.debug.print("Failed to toggle playback: {}\n", .{err});
        //         return;
        //     };
        //     defer allocator.free(toggle_result.stdout);
        //     defer allocator.free(toggle_result.stderr);
        //
        //     const was_playing = std.mem.eql(u8, status, "Playing");
        //     music.updateIconForPlayingState(!was_playing);
        //
        //     std.debug.print("Toggled playback. Was playing: {}, Now playing: {}\n", .{ was_playing, !was_playing });
        // } else {
        //     std.debug.print("No active player found\n", .{});
        // }
    }
    
    /// Update matadata of playing
    // fn updateMetadata(music: *Notification) void {
    //     var priv = music.private();
    //
    //     const allocator = priv.allocator orelse {
    //         std.debug.print("Warning: allocator not available for updateTitle\n", .{});
    //         return;
    //     };
    //
    //     // Get title using playerctl
    //     const title_result = std.process.Child.run(.{
    //         .allocator = allocator,
    //         .argv = &[_][]const u8{ "playerctl", "metadata", "title"},
    //     }) catch |err| {
    //         std.debug.print("Command execution failed: {}\n", .{err});
    //         return;
    //     };
    //     defer allocator.free(title_result.stdout);
    //     defer allocator.free(title_result.stderr);
    //
    //     // Get artist using playerctl
    //     const artist_result = std.process.Child.run(.{
    //         .allocator = allocator,
    //         .argv = &[_][]const u8{ "playerctl", "metadata", "artist"},
    //     }) catch |err| {
    //         std.debug.print("Command execution failed: {}\n", .{err});
    //         return;
    //     };
    //     defer allocator.free(artist_result.stdout);
    //     defer allocator.free(artist_result.stderr);
    //
    //     if (title_result.term.Exited == 0 and title_result.stdout.len > 0) {
    //         const title = std.mem.trim(u8, title_result.stdout, "\n\r ");
    //         const artist = blk: {
    //             if (artist_result.term.Exited == 0 and artist_result.stdout.len > 0) {
    //                 break :blk std.mem.trim(u8, artist_result.stdout, "\n\r");
    //             } else {
    //                 break :blk "";
    //             }
    //         };
    //
    //         const display_text = if (artist.len > 0)
    //             std.fmt.allocPrint(allocator, "   {s} || {s}    ", .{ title, artist }) catch {
    //                 std.debug.print("Memory allocation failed for display text\n", .{});
    //                 return;
    //             }
    //         else
    //             allocator.dupe(u8, title) catch {
    //                 std.debug.print("Memory allocation failed for title\n", .{});
    //                 return;
    //             };
    //         defer allocator.free(display_text);
    //
    //         if (priv.title_artist) |old| {
    //             allocator.free(std.mem.span(old));
    //         }
    //
    //         const c_title = allocator.dupeZ(u8, display_text) catch {
    //             std.debug.print("Memory allocation failed\n", .{});
    //             return;
    //         };
    //
    //         priv.title_artist = c_title.ptr;
    //
    //         if (priv.title_artist) |t| {
    //             gtk.Label.setText(priv.label, t);
    //         }
    //
    //         // Get text width
    //         var req: gtk.Requisition = undefined;
    //         gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
    //         priv.text_width = req.f_width;
    //
    //         // Reset scroll position
    //         priv.scroll_position = 0.0;
    //     } else {
    //         gtk.Label.setText(priv.label, "No music playing");
    //         priv.text_width = 150;
    //     }
    // }
    
    fn startAnimation(notification: *Notification) void {
        var priv = notification.private();
        // Stop existing tick callbacks
        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(notification.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }
         
        priv.scroll_tick_id = gtk.Widget.addTickCallback(
            notification.as(gtk.Widget),
            &animateScrollTick,
            notification,
            null
        );
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
                            const allocator = priv.allocator orelse return 0;
                            const temp_cstr = allocator.dupeZ(u8, next_node.message) catch return 0;

                            gtk.Label.setText(priv.label, temp_cstr.ptr);

                            gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), 0);
                            gtk.Widget.setMarginEnd(priv.label.as(gtk.Widget), 0);
                            gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), 0.0);

                            if (priv.current_message) |old_msg| {
                                allocator.free(std.mem.span(old_msg));
                            }
                            priv.current_message = temp_cstr.ptr;
                            
                            var req: gtk.Requisition = undefined;
                            gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
                            priv.text_width = req.f_width;
                            priv.scroll_position = @as(f64, @floatFromInt(available_width));
                            
                            std.posix.nanosleep(0, 900);
                        }
                    }
                }
                
                // ラベルにマージンを設定してテキストを右にオフセット
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
        
        if (priv.current_message) |ta| {
            if (priv.allocator) |allocator| {
                allocator.free(std.mem.span(ta));
            }
        }
        
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
