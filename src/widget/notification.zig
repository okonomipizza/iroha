const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");

const NotificationNode = struct {
    message: []const u8,
    next: ?*NotificationNode,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator, message: []const u8) !*Self {
        const node = try allocator.create(Self);
        node.* = Self {
            .message = try allocator.dupe(u8, message),
            .next = null,
        };
        return node;
    }

    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        allocator.destroy(self);
    }
};

const NotificationHistory = struct {
    head: ?*NotificationNode,
    tail: ?*NotificationNode,
    current: ?*NotificationNode,
    count: usize,
    max_count: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_count: usize) !*Self {
        const history = try allocator.create(Self);
        history.* = .{
            .head = null,
            .tail = null,
            .current = null,
            .count = 0,
            .max_count = max_count,
            .allocator = allocator,
        };

        return history;
    }
    
    pub fn append(self: *Self, message: []const u8) !void {
        const new_node = try NotificationNode.create(self.allocator, message);

        if (self.tail) |tail| {
            tail.next = new_node;
            self.tail = new_node;
        } else {
            self.head = new_node;
            self.tail = new_node;
        }

        self.count += 1;

        if (self.count > self.max_count) {
            self.removeOldest();
        }
    }

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

    pub fn getCurrent(self: *const Self) ?*NotificationNode {
        return self.current;
    }

    pub fn next(self: *Self) ?*NotificationNode {
        if (self.current) |old_current| {
            self.current = old_current.next;
            return self.current;
        }
    }

    /// Clear all notifications
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

/// point
pub const Notification = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Box;
    
    const Private = struct {
        history: ?*NotificationHistory,
        current_node: ?*NotificationNode,
        current_message: ?[*:0]u8, // Concatanate string of the currently playing track
        
        main_hbox: *gtk.Box,
        icon_button: *gtk.Button,
        icon: *gtk.Image,
        scrolled_window: *gtk.ScrolledWindow, // Enables horizontal scrolling for the label content
        label_hbox: *gtk.Box,
        label: *gtk.Label, // Displays the media information string (title | artist)

        scroll_tick_id: c_uint, // For scroll animation tick callback

        frame_count: c_uint, // Counter for frame-based timing
        scroll_position: f64, // Current position of label at scrolled window
        
        widget_width: c_int, // Width of Music widget
        icon_width: c_int,
        text_width: c_int, // Width of the media information string
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
    pub fn new(allocator: std.mem.Allocator) !*Notification {
        var notification = gobject.ext.newInstance(Notification, .{});
        const notification_style_context = gtk.Widget.getStyleContext(notification.as(gtk.Widget));
        gtk.StyleContext.addClass(notification_style_context, "notification");

        var priv = notification.private();
        priv.history = try NotificationHistory.init(allocator, 10);
        if (priv.history) |history| {
            const initial_message = "この世でハッピーに生きるコツは、無知で馬鹿のまま生きること"; 
            try history.append(initial_message);

            const c_message = allocator.dupeZ(u8, initial_message) catch {
                std.debug.print("Memory allocation failed\n", .{});
                return error.MemoryAllocationFailed;
            };
            priv.current_message = c_message.ptr;
        }

        priv.allocator = allocator;
        notification.setIcon();

        if (priv.current_message) |t| {
            gtk.Label.setText(priv.label, t);
        }

        var req: gtk.Requisition = undefined;
        gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);

        const available_width = priv.widget_width - priv.icon_width - 8;

        priv.scroll_position = @as(f64, @floatFromInt(-available_width));

        priv.text_width = req.f_width;

        notification.initializeWithAllocator();
        return notification;
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
        
        priv.label = gtk.Label.new("No music playing");
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

                const available_width = priv.widget_width - priv.icon_width - 8;
                
                    // 右から左へスクロール
                    priv.scroll_position -= 0.5;
                    
                    const complete_disappear_position = @as(f64, @floatFromInt(-priv.text_width - available_width));
                    
                    if (priv.scroll_position <= complete_disappear_position) {
                        // 右端から再開
                        priv.scroll_position = @as(f64, @floatFromInt(available_width + 50));
                    }
                    
                    // ラベルにマージンを設定してテキストを右にオフセット
                    if (priv.scroll_position > 0) {
                        // 正の値の場合：右側のマージンでテキストを右に移動
                        gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), @as(c_int, @intFromFloat(priv.scroll_position)));
                        gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), 0.0);
                    } else {
                        // 負の値の場合：スクロール位置で左に移動
                        gtk.Widget.setMarginStart(priv.label.as(gtk.Widget), 0);
                        
                        const margin_end = @as(c_int, @intFromFloat((-priv.scroll_position)));
                        gtk.Widget.setMarginEnd(priv.label.as(gtk.Widget), margin_end);

                        gtk.Adjustment.setValue(gtk.ScrolledWindow.getHadjustment(priv.scrolled_window), -priv.scroll_position);
                    }
                
                return 1;
            }
            
            return 0;
    }

    // fn updateTitleTick(widget: *gtk.Widget, frame_clock: *gdk.FrameClock, user_data: ?*anyopaque) callconv(.c) c_int {
    //     _ = widget;
    //     _ = frame_clock;
    //
    //     if (user_data) |data| {
    //         const music: *Notification = @ptrCast(@alignCast(data));
    //         const priv = music.private();
    //
    //         priv.frame_count += 1;
    //
    //         // Now supports 60 fps 3 seconds
    //         if (priv.frame_count >= 120) {
    //             priv.frame_count = 0;
    //
    //             const available_width = priv.widget_width - 8;
    //             if (priv.text_width > available_width) {
    //                 const max_scroll = @as(f64, @floatFromInt(priv.text_width - priv.widget_width + 100));
    //                 if (priv.scroll_position < max_scroll) {
    //                     return 1;
    //                 }
    //             }
    //         }
    //
    //         return 1;
    //     }
    //     return 0;
    // }
    
    fn dispose(music: *Notification) callconv(.c) void {
        var priv = music.private();
        
        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }
        
        // メモリを解放
        if (priv.current_message) |ta| {
            if (priv.allocator) |allocator| {
                allocator.free(std.mem.span(ta));
            }
        }
        
        // 親クラスのdisposeを呼び出し
        gobject.Object.virtual_methods.dispose.call(Class.parent, music.as(Parent));
    }
    
    fn private(music: *Notification) *Private {
        return gobject.ext.impl_helpers.getPrivate(music, Private, Private.offset);
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
