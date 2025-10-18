const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");

/// point
pub const Music = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Box;

    const Private = struct {
        title_artist: ?[*:0]u8, // Concatanate string of the currently playing track
        title: ?[*:0]u8, // Title of the currently playing track
        is_playing: bool, // Playback status indicating whether media is currently playing

        main_hbox: *gtk.Box,
        icon_button: *gtk.Button,
        icon: *gtk.Image,
        scrolled_window: *gtk.ScrolledWindow, // Enables horizontal scrolling for the label content
        label_hbox: *gtk.Box,
        label: *gtk.Label, // Displays the media information string (title | artist)

        scroll_tick_id: c_uint, // For scroll animation tick callback
        update_tick_id: c_uint, // For title update tick callback
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
        .name = "IrohaMusic",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    /// Returns initialized instance
    pub fn new(allocator: std.mem.Allocator) *Music {
        var music = gobject.ext.newInstance(Music, .{});
        const music_style_context = gtk.Widget.getStyleContext(music.as(gtk.Widget));
        gtk.StyleContext.addClass(music_style_context, "music");

        var priv = music.private();
        priv.allocator = allocator;
        music.setIcon();
        music.initializeWithAllocator();
        return music;
    }

    fn setIcon(music: *Music) void {
        const priv = music.private();
        if (priv.is_playing) {
            gtk.Image.setFromIconName(priv.icon, "media-playback-pause");
        } else {
            gtk.Image.setFromIconName(priv.icon, "media-playback-start");
        }
        return;
    }

    fn updateIconForPlayingState(music: *Music, is_playing: bool) void {
        const priv = music.private();
        priv.is_playing = is_playing;
        music.setIcon();
    }

    fn initializeWithAllocator(music: *Music) void {
        const priv = music.private();
        if (priv.allocator == null) {
            std.debug.print("Warning: allocator not set\n", .{});
            return;
        }
        updateMetadata(music);
        startAnimation(music);
    }

    fn init(music: *Music, _: *Class) callconv(.c) void {
        var priv = music.private();

        priv.title = null;
        priv.is_playing = false;
        priv.scroll_position = 0.0;
        priv.scroll_tick_id = 0;
        priv.update_tick_id = 0;
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
        gtk.StyleContext.addClass(button_style_context, "music-icon-button");
        const icon_style_context = gtk.Widget.getStyleContext(priv.icon.as(gtk.Widget));
        gtk.StyleContext.addClass(icon_style_context, "music-icon");

        _ = gtk.Button.signals.clicked.connect(priv.icon_button, *Music, &onIconButtonClicked, music, .{});

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
        gtk.Box.append(music.as(gtk.Box), priv.main_hbox.as(gtk.Widget));

        gtk.Widget.show(music.as(gtk.Widget));
    }

    /// Control audio playback state
    fn onIconButtonClicked(button: *gtk.Button, music: *Music) callconv(.c) void {
        _ = button;
        const priv = music.private();

        const allocator = priv.allocator orelse {
            std.debug.print("Allocator not available for button click\n", .{});
            return;
        };

        // Retrieve currently playing media metadata using playctl
        const status_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "playerctl", "status" },
        }) catch |err| {
            std.debug.print("Failed to get player status: {}\n", .{err});
            return;
        };
        defer allocator.free(status_result.stdout);
        defer allocator.free(status_result.stderr);

        if (status_result.term.Exited == 0) {
            const status = std.mem.trim(u8, status_result.stdout, "\n\r ");

            const toggle_result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ "playerctl", "play-pause" },
            }) catch |err| {
                std.debug.print("Failed to toggle playback: {}\n", .{err});
                return;
            };
            defer allocator.free(toggle_result.stdout);
            defer allocator.free(toggle_result.stderr);

            const was_playing = std.mem.eql(u8, status, "Playing");
            music.updateIconForPlayingState(!was_playing);

            std.debug.print("Toggled playback. Was playing: {}, Now playing: {}\n", .{ was_playing, !was_playing });
        } else {
            std.debug.print("No active player found\n", .{});
        }
    }

    fn updateMetadataTitle(music: *Music) bool {
        var priv = music.private();

        const allocator = priv.allocator orelse {
            std.debug.print("Warning: allocator not available for updateTitle\n", .{});
            return false;
        };

        const title_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "title" },
        }) catch |err| {
            std.debug.print("Command execution failed: {}\n", .{err});
            return false;
        };
        defer allocator.free(title_result.stdout);
        defer allocator.free(title_result.stderr);

        if (title_result.term.Exited == 0 and title_result.stdout.len > 0) {
            const title = std.mem.trim(u8, title_result.stdout, "\n\r ");

            if (priv.title) |old_title| {
                const old_title_slice = std.mem.span(old_title);
                if (std.mem.eql(u8, old_title_slice, title)) {
                    return false;
                } else {
                    allocator.free(std.mem.span(old_title));
                    const c_title = allocator.dupeZ(u8, title) catch {
                        std.debug.print("Memory allocation failed\n", .{});
                        return false;
                    };
                    priv.title = c_title.ptr;
                    return true;
                }
            } else {
                const c_title = allocator.dupeZ(u8, title) catch {
                    std.debug.print("Memory allocation failed\n", .{});
                    return false;
                };
                priv.title = c_title.ptr;
                return true;
            }
        } else {
            if (priv.title) |old_title| {
                allocator.free(std.mem.span(old_title));
                priv.title = null;
                return true;
            }
        }
        return false;
    }

    /// Update matadata of playing
    fn updateMetadata(music: *Music) void {
        var priv = music.private();

        const allocator = priv.allocator orelse {
            std.debug.print("Warning: allocator not available for updateTitle\n", .{});
            return;
        };

        // Get title using playerctl
        const title_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "title" },
        }) catch |err| {
            std.debug.print("Command execution failed: {}\n", .{err});
            return;
        };
        defer allocator.free(title_result.stdout);
        defer allocator.free(title_result.stderr);

        // Get artist using playerctl
        const artist_result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "artist" },
        }) catch |err| {
            std.debug.print("Command execution failed: {}\n", .{err});
            return;
        };
        defer allocator.free(artist_result.stdout);
        defer allocator.free(artist_result.stderr);

        if (title_result.term.Exited == 0 and title_result.stdout.len > 0) {
            const title = std.mem.trim(u8, title_result.stdout, "\n\r ");
            const artist = blk: {
                if (artist_result.term.Exited == 0 and artist_result.stdout.len > 0) {
                    break :blk std.mem.trim(u8, artist_result.stdout, "\n\r");
                } else {
                    break :blk "";
                }
            };

            const display_text = if (artist.len > 0)
                std.fmt.allocPrint(allocator, "   {s} || {s}    ", .{ title, artist }) catch {
                    std.debug.print("Memory allocation failed for display text\n", .{});
                    return;
                }
            else
                allocator.dupe(u8, title) catch {
                    std.debug.print("Memory allocation failed for title\n", .{});
                    return;
                };
            defer allocator.free(display_text);

            if (priv.title_artist) |old| {
                allocator.free(std.mem.span(old));
            }

            const c_title = allocator.dupeZ(u8, display_text) catch {
                std.debug.print("Memory allocation failed\n", .{});
                return;
            };

            priv.title_artist = c_title.ptr;

            if (priv.title_artist) |t| {
                gtk.Label.setText(priv.label, t);
            }

            // Get text width
            var req: gtk.Requisition = undefined;
            gtk.Widget.getPreferredSize(priv.label.as(gtk.Widget), null, &req);
            priv.text_width = req.f_width;

            // Reset scroll position
            priv.scroll_position = 0.0;
        } else {
            gtk.Label.setText(priv.label, "No music playing");
            priv.text_width = 150;
        }
    }

    fn startAnimation(music: *Music) void {
        var priv = music.private();
        // Stop existing tick callbacks
        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }
        if (priv.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.update_tick_id);
            priv.update_tick_id = 0;
        }

        priv.scroll_tick_id = gtk.Widget.addTickCallback(music.as(gtk.Widget), &animateScrollTick, music, null);
        priv.update_tick_id = gtk.Widget.addTickCallback(music.as(gtk.Widget), &updateTitleTick, music, null);
    }

    fn animateScrollTick(widget: *gtk.Widget, frame_clock: *gdk.FrameClock, user_data: ?*anyopaque) callconv(.c) c_int {
        _ = widget;
        _ = frame_clock;

        if (user_data) |data| {
            const music: *Music = @ptrCast(@alignCast(data));
            var priv = music.private();

            const available_width = priv.widget_width - 8;

            // Only scroll if text is longer than widget width
            if (priv.text_width > available_width) {
                // Update scroll position
                priv.scroll_position += 0.2;

                // Reset when reaching maximum scroll position
                const max_scroll = @as(f64, @floatFromInt(priv.text_width - available_width + 100));
                if (priv.scroll_position > max_scroll) {
                    priv.scroll_position = -100.0;
                }

                // Apply scroll position
                const adjustment = gtk.ScrolledWindow.getHadjustment(priv.scrolled_window);
                if (priv.scroll_position >= 0) {
                    gtk.Adjustment.setValue(adjustment, priv.scroll_position);
                }
            }

            // Continue timer
            return 1;
        }

        return 0;
    }

    fn updateTitleTick(widget: *gtk.Widget, frame_clock: *gdk.FrameClock, user_data: ?*anyopaque) callconv(.c) c_int {
        _ = widget;
        _ = frame_clock;

        if (user_data) |data| {
            const music: *Music = @ptrCast(@alignCast(data));
            const priv = music.private();

            priv.frame_count += 1;

            // Now supports 60 fps 3 seconds
            if (priv.frame_count >= 120) {
                priv.frame_count = 0;

                if (updateMetadataTitle(music)) {
                    updateMetadata(music);
                    return 1;
                }

                const available_width = priv.widget_width - 8;
                if (priv.text_width > available_width) {
                    const max_scroll = @as(f64, @floatFromInt(priv.text_width - priv.widget_width + 100));
                    if (priv.scroll_position < max_scroll) {
                        return 1;
                    }
                }
            }

            return 1;
        }
        return 0;
    }

    fn dispose(music: *Music) callconv(.c) void {
        var priv = music.private();

        if (priv.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.scroll_tick_id);
            priv.scroll_tick_id = 0;
        }
        if (priv.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(music.as(gtk.Widget), priv.update_tick_id);
            priv.update_tick_id = 0;
        }

        // メモリを解放
        if (priv.title_artist) |ta| {
            if (priv.allocator) |allocator| {
                allocator.free(std.mem.span(ta));
            }
        }
        if (priv.title) |title| {
            if (priv.allocator) |allocator| {
                allocator.free(std.mem.span(title));
            }
        }

        // 親クラスのdisposeを呼び出し
        gobject.Object.virtual_methods.dispose.call(Class.parent, music.as(Parent));
    }

    fn private(music: *Music) *Private {
        return gobject.ext.impl_helpers.getPrivate(music, Private, Private.offset);
    }

    pub fn as(music: *Music, comptime T: type) *T {
        return gobject.ext.as(T, music);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        pub const Instance = Music;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }
    };
};
