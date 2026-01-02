const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");
const pango = @import("pango");

pub const Music = struct {
    music_button: *gtk.MenuButton,
    music_popover: *gtk.Popover,
    album_art: *gtk.Image,
    title_label: *gtk.Label,
    artist_label: *gtk.Label,
    prev_button: *gtk.Button,
    play_pause_button: *gtk.Button,
    next_button: *gtk.Button,

    title: ?[*:0]u8,
    artist: ?[*:0]u8,
    is_playing: bool,
    update_tick_id: c_uint,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        music_button: *gtk.MenuButton,
        music_popover: *gtk.Popover,
        album_art: *gtk.Image,
        title_label: *gtk.Label,
        artist_label: *gtk.Label,
        prev_button: *gtk.Button,
        play_pause_button: *gtk.Button,
        next_button: *gtk.Button,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .music_button = music_button,
            .music_popover = music_popover,
            .album_art = album_art,
            .title_label = title_label,
            .artist_label = artist_label,
            .prev_button = prev_button,
            .play_pause_button = play_pause_button,
            .next_button = next_button,
            .title = null,
            .artist = null,
            .is_playing = false,
            .update_tick_id = 0,
            .allocator = allocator,
        };

        return self;
    }

    pub fn connectSignals(self: *Self) void {
        _ = gtk.Button.signals.clicked.connect(
            self.prev_button,
            *Self,
            &onPrevClicked,
            self,
            .{},
        );

        _ = gtk.Button.signals.clicked.connect(
            self.play_pause_button,
            *Self,
            &onPlayPauseClicked,
            self,
            .{},
        );

        _ = gtk.Button.signals.clicked.connect(
            self.next_button,
            *Self,
            &onNextClicked,
            self,
            .{},
        );
    }

    pub fn start(self: *Self) void {
        self.updatePlaybackStatus();
        self.updateMetadata();
        self.startUpdateTimer();
    }

    fn updatePlayPauseButton(self: *Self) void {
        const icon_name = if (self.is_playing)
            "media-playback-pause"
        else
            "media-playback-start";

        gtk.Button.setIconName(self.play_pause_button, icon_name);
    }

    fn updateMetadata(self: *Self) void {
        const title_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "title" },
        }) catch |err| {
            std.debug.print("Failed to get title: {}\n", .{err});
            return;
        };
        defer self.allocator.free(title_result.stdout);
        defer self.allocator.free(title_result.stderr);

        const artist_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "artist" },
        }) catch |err| {
            std.debug.print("Failed to get artist: {}\n", .{err});
            return;
        };
        defer self.allocator.free(artist_result.stdout);
        defer self.allocator.free(artist_result.stderr);

        const art_result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "metadata", "mpris:artUrl" },
        }) catch |err| {
            std.debug.print("Failed to get album art: {}\n", .{err});
            return;
        };
        defer self.allocator.free(art_result.stdout);
        defer self.allocator.free(art_result.stderr);

        if (title_result.term.Exited == 0 and title_result.stdout.len > 0) {
            const title = std.mem.trim(u8, title_result.stdout, "\n\r ");
            const c_title = self.allocator.dupeZ(u8, title) catch {
                std.debug.print("Failed to allocate title\n", .{});
                return;
            };

            if (self.title) |old| {
                self.allocator.free(std.mem.span(old));
            }
            self.title = c_title.ptr;
            gtk.Label.setText(self.title_label, c_title.ptr);
        } else {
            gtk.Label.setText(self.title_label, "No music playing");
        }

        if (artist_result.term.Exited == 0 and artist_result.stdout.len > 0) {
            const artist = std.mem.trim(u8, artist_result.stdout, "\n\r ");
            const c_artist = self.allocator.dupeZ(u8, artist) catch {
                std.debug.print("Failed to allocate artist\n", .{});
                return;
            };

            if (self.artist) |old| {
                self.allocator.free(std.mem.span(old));
            }
            self.artist = c_artist.ptr;
            gtk.Label.setText(self.artist_label, c_artist.ptr);
        } else {
            gtk.Label.setText(self.artist_label, "");
        }

        if (art_result.term.Exited == 0 and art_result.stdout.len > 0) {
            const art_url = std.mem.trim(u8, art_result.stdout, "\n\r ");
            if (std.mem.startsWith(u8, art_url, "file://")) {
                const path = art_url[7..]; // Remove "file://"
                const c_path = self.allocator.dupeZ(u8, path) catch return;
                defer self.allocator.free(c_path);
                gtk.Image.setFromFile(self.album_art, c_path.ptr);
            } else {
                gtk.Image.setFromIconName(self.album_art, "audio-x-generic");
            }
        } else {
            gtk.Image.setFromIconName(self.album_art, "audio-x-generic");
        }
    }

    fn onPlayPauseClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "play-pause" },
        }) catch {
            std.debug.print("Failed to toggle playback\n", .{});
            return;
        };

        self.is_playing = !self.is_playing;
        // self.updateIcon();
        self.updatePlayPauseButton();
    }

    fn onPrevClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "previous" },
        }) catch {
            std.debug.print("Failed to skip to previous\n", .{});
            return;
        };

        self.updateMetadata();
    }

    fn onNextClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "playerctl", "next" },
        }) catch {
            std.debug.print("Failed to skip to next\n", .{});
            return;
        };

        self.updateMetadata();
    }

    fn updatePlaybackStatus(self: *Self) void {
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
            self.is_playing = std.mem.eql(u8, status, "Playing");
            // self.updateIcon();
            self.updatePlayPauseButton();
        }
    }

    fn startUpdateTimer(self: *Self) void {
        if (self.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(
                self.music_button.as(gtk.Widget),
                self.update_tick_id,
            );
        }

        self.update_tick_id = gtk.Widget.addTickCallback(
            self.music_button.as(gtk.Widget),
            &updateTick,
            self,
            null,
        );
    }

    fn updateTick(
        _: *gtk.Widget,
        _: *gdk.FrameClock,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        if (user_data) |data| {
            const self: *Self = @ptrCast(@alignCast(data));
            self.updatePlaybackStatus();
            self.updateMetadata();
        }
        return 1; // Continue
    }

    pub fn deinit(self: *Self) void {
        if (self.update_tick_id != 0) {
            gtk.Widget.removeTickCallback(
                self.music_button.as(gtk.Widget),
                self.update_tick_id,
            );
        }

        if (self.title) |t| {
            self.allocator.free(std.mem.span(t));
        }
        if (self.artist) |a| {
            self.allocator.free(std.mem.span(a));
        }

        self.allocator.destroy(self);
    }
};
