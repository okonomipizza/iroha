const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");

pub const Music = struct {
    allocator: std.mem.Allocator,

    // UI elements from Blueprint
    container: *gtk.Box,
    play_pause_button: *gtk.Button,
    play_pause_button_icon: *gtk.Image,
    scrolled_window: *gtk.ScrolledWindow,
    scrolled_title_box: *gtk.Box,
    title_label: *gtk.Label,

    // State
    title: ?[]u8,
    is_playing: bool,

    // Animation
    scroll_tick_id: c_uint, // For scroll animation tick callback
    update_tick_id: c_uint, // For information update tick callback
    frame_count: c_uint, // Counter for frame-based timing
    scroll_position: f64, // Current position of label at scrolled window

    // Size
    widget_width: c_int, // Width of Music container
    icon_width: c_int,
    text_width: c_int, // Width of the media information string

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        container: *gtk.Box,
        play_pause_button: *gtk.Button,
        play_pause_button_icon: *gtk.Image,
        scrolled_window: *gtk.ScrolledWindow,
        scrolled_title_box: *gtk.Box,
        scrolled_title_label: *gtk.Label,
    ) !*Music {
        const music = try allocator.create(Music);

        music.* = .{
            .allocator = allocator,
            .container = container,
            .play_pause_button = play_pause_button,
            .play_pause_button_icon = play_pause_button_icon,
            .scrolled_window = scrolled_window,
            .scrolled_title_box = scrolled_title_box,
            .title_label = scrolled_title_label,
            .title = null,
            .is_playing = false,
            .scroll_tick_id = 0,
            .update_tick_id = 0,
            .frame_count = 0,
            .scroll_position = 0.0,
            .widget_width = 0,
            .icon_width = 24,
            .text_width = 0,
        };

        gtk.Widget.setSizeRequest(music.scrolled_window.as(gtk.Widget), 200, -1);

        music.setIcon();
        music.connectSignals();
        music.updatePlaybackStatus();
        music.updateMetadata();

        return music;
    }

    pub fn deinit(self: *Self) void {
        if (self.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(self.container.as(gtk.Widget), self.scroll_tick_id);
        }
        if (self.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(self.container.as(gtk.Widget), self.update_tick_id);
        }

        if (self.title) |t| {
            self.allocator.free(t);
        }

        self.allocator.destroy(self);
    }

    pub fn updateWidgetWidth(self: *Self) void {
        var req: gtk.Requisition = undefined;
        gtk.Widget.getPreferredSize(self.scrolled_window.as(gtk.Widget), null, &req);
        self.widget_width = req.f_width;
    }

    pub fn setIcon(self: *Self) void {
        const icon_name = if (self.is_playing)
            "media-playback-pause"
        else
            "media-playback-start";
        gtk.Image.setFromIconName(self.play_pause_button_icon, icon_name);
    }

    pub fn updateIconForPlayingState(self: *Self, is_playing: bool) void {
        self.is_playing = is_playing;
        self.setIcon();
    }

    pub fn connectSignals(self: *Self) void {
        _ = gtk.Button.signals.clicked.connect(
            self.play_pause_button,
            *Self,
            &onPlayPauseClicked,
            self,
            .{},
        );
    }

    pub fn onPlayPauseClicked(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;

        const status_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "status" },
        }) catch {
            return;
        };
        defer self.allocator.free(status_result.stdout);
        defer self.allocator.free(status_result.stderr);

        if (status_result.term.Exited == 0) {
            const status = std.mem.trim(u8, status_result.stdout, "\n\r ");

            _ = std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "playerctl", "play-pause" },
            }) catch {
                return;
            };

            const was_playing = std.mem.eql(u8, status, "Playing");
            self.updateIconForPlayingState(!was_playing);
        }
    }

    pub fn updateMetadataTitle(self: *Self) bool {
        const title_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "title" },
        }) catch {
            return false;
        };
        defer self.allocator.free(title_result.stdout);
        defer self.allocator.free(title_result.stderr);

        if (title_result.term.Exited == 0 and title_result.stdout.len > 0) {
            const title = std.mem.trim(u8, title_result.stdout, "\n\r ");

            if (self.title) |old_title| {
                if (std.mem.eql(u8, old_title, title)) {
                    return false; // Nothing changed
                } else {
                    self.allocator.free(old_title);
                    self.title = self.allocator.dupe(u8, title) catch {
                        return false;
                    };
                    return true;
                }
            } else {
                self.title = self.allocator.dupe(u8, title) catch {
                    return false;
                };
                return true;
            }
        } else {
            if (self.title) |old_title| {
                self.allocator.free(old_title);
                self.title = null;
                return true;
            }
        }
        return false;
    }

    pub fn updateMetadata(self: *Self) void {
        if (self.title) |title| {
            const title_z = self.allocator.dupeZ(u8, title) catch {
                return;
            };

            gtk.Label.setText(self.title_label, title_z);

            // Get text width
            var req: gtk.Requisition = undefined;
            gtk.Widget.getPreferredSize(self.title_label.as(gtk.Widget), null, &req);
            self.text_width = req.f_width;

            // Reset scroll position
            self.scroll_position = 0.0;
        } else {
            self.setNoMusicPlaying();
        }
    }

    fn setNoMusicPlaying(self: *Self) void {
        gtk.Label.setText(self.title_label, "No music playing");
        self.text_width = 150;

        if (self.title) |t| {
            self.allocator.free(t);
            self.title = null;
        }
    }

    pub fn startAnimation(self: *Self) void {
        if (self.scroll_tick_id != 0) {
            gtk.Widget.removeTickCallback(self.container.as(gtk.Widget), self.scroll_tick_id);
            self.scroll_tick_id = 0;
        }
        if (self.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(self.container.as(gtk.Widget), self.update_tick_id);
            self.update_tick_id = 0;
        }

        self.scroll_tick_id = gtk.Widget.addTickCallback(
            self.container.as(gtk.Widget),
            &animateScrollTick,
            self,
            null,
        );
        self.update_tick_id = gtk.Widget.addTickCallback(
            self.container.as(gtk.Widget),
            &updateTitleTick,
            self,
            null,
        );
    }

    fn animateScrollTick(
        widget: *gtk.Widget,
        frame_clock: *gdk.FrameClock,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        _ = widget;
        _ = frame_clock;
        if (user_data) |data| {
            const self: *Self = @ptrCast(@alignCast(data));

            self.updateWidgetWidth();

            const available_width = self.widget_width;
            // Only scroll if text is longer than widget width
            if (self.text_width > available_width) {
                // Update scroll position
                self.scroll_position += 0.2;

                // Reset when reaching maximum scroll position
                const max_scroll = @as(f64, @floatFromInt(self.text_width - available_width + 100));
                if (self.scroll_position > max_scroll) {
                    self.scroll_position = -100.0;
                }

                // Apply scroll position
                const adjustment = gtk.ScrolledWindow.getHadjustment(self.scrolled_window);
                if (self.scroll_position >= 0) {
                    gtk.Adjustment.setValue(adjustment, self.scroll_position);
                }
            } else {
                self.scroll_position = 0.0;
                const adjustment = gtk.ScrolledWindow.getHadjustment(self.scrolled_window);
                gtk.Adjustment.setValue(adjustment, 0.0);
            }

            // Continue timer
            return 1;
        }

        return 0;
    }

    fn updateTitleTick(
        widget: *gtk.Widget,
        frame_clock: *gdk.FrameClock,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        _ = widget;
        _ = frame_clock;

        if (user_data) |data| {
            const self: *Self = @ptrCast(@alignCast(data));

            self.frame_count += 1;

            // Update per 3 seconds (60fps * 3 seconds = 180 frame)
            if (self.frame_count >= 180) {
                self.frame_count = 0;
                if (self.updateMetadataTitle()) {
                    self.updateMetadata();
                }
            }

            return 1;
        }
        return 0;
    }

    pub fn updatePlaybackStatus(self: *Self) void {
        const status_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "status" },
        }) catch {
            return;
        };
        defer self.allocator.free(status_result.stdout);
        defer self.allocator.free(status_result.stderr);

        if (status_result.term.Exited == 0 and status_result.stdout.len > 0) {
            const status = std.mem.trim(u8, status_result.stdout, "\n\r ");
            const is_playing = std.mem.eql(u8, status, "Playing");
            self.updateIconForPlayingState(is_playing);
        }
    }
};
