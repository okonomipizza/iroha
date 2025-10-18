const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const ClockMode = enum(c_int) {
    time_only, // HH:MM:SS
    date_time, // YYYY-MM-DD HH:MM:SS
    time_12h,
    date_time_12h,
};

pub const Clock = extern struct {
    parent_instance: Parent,
    pub const Parent = gtk.Button;

    const Private = struct {
        mode: ClockMode,
        timezone_offset_hours: c_int,
        timeout_id: c_uint,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "IrohaClock",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(timezone_offset_hours: c_int) *Clock {
        var clock = gobject.ext.newInstance(Clock, .{});
        clock.private().timezone_offset_hours = timezone_offset_hours;
        return clock;
    }

    pub fn as(clock: *Clock, comptime T: type) *T {
        return gobject.ext.as(T, clock);
    }

    fn init(clock: *Clock, _: *Class) callconv(.c) void {
        clock.private().mode = ClockMode.time_only;
        clock.private().timeout_id = 0;

        _ = gtk.Button.signals.clicked.connect(clock, ?*anyopaque, &handleClicked, null, .{});
        clock.updateLabel();

        clock.private().timeout_id = glib.timeoutAdd(1000, &timerCallback, clock);
    }

    fn handleClicked(clock: *Clock, _: ?*anyopaque) callconv(.c) void {
        const current_mode = clock.private().mode;
        clock.private().mode = switch (current_mode) {
            .time_only => .date_time,
            .date_time => .time_12h,
            .time_12h => .date_time_12h,
            .date_time_12h => .time_only,
        };

        clock.updateLabel();
    }

    fn timerCallback(user_data: ?*anyopaque) callconv(.c) c_int {
        if (user_data) |data| {
            const clock: *Clock = @ptrCast(@alignCast(data));
            clock.updateLabel();
        }
        return 1; // Continue timer
    }

    fn updateLabel(clock: *Clock) void {
        var buffer: [32]u8 = undefined;
        const time_str = clock.getFormattedTime(&buffer);
        gtk.Button.setLabel(clock.as(gtk.Button), time_str);
    }

    fn getFormattedTime(clock: *Clock, buffer: []u8) [*:0]const u8 {
        const timestamp = std.time.timestamp();
        const jst_offset = 9 * 3600;
        const epoch_seconds = @as(u64, @intCast(timestamp + jst_offset));
        const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const epoch_day = epoch.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch.getDaySeconds();

        const year: u16 = @intCast(year_day.year);
        const month: u8 = @intCast(month_day.month.numeric());
        const day: u8 = @intCast(month_day.day_index + 1);
        const hours: u8 = @intCast(day_seconds.getHoursIntoDay());
        const minutes: u8 = @intCast(day_seconds.getMinutesIntoHour());
        const seconds: u8 = @intCast(day_seconds.getSecondsIntoMinute());

        const formatted = switch (clock.private().mode) {
            .time_only => std.fmt.bufPrintZ(buffer, "{:0>2}:{:0>2}:{:0>2}", .{ hours, minutes, seconds }),
            .date_time => std.fmt.bufPrintZ(buffer, "{:0>4}-{:0>2}-{:0>2} {:0>2}:{:0>2}:{:0>2}", .{ year, month, day, hours, minutes, seconds }),
            .time_12h => blk: {
                const is_pm = hours >= 12;
                const display_hour = if (hours == 0) 12 else if (hours > 12) hours - 12 else hours;
                const period = if (is_pm) "PM" else "AM";
                break :blk std.fmt.bufPrintZ(buffer, "{:0>2}:{:0>2}:{:0>2} {s}", .{ display_hour, minutes, seconds, period });
            },
            .date_time_12h => blk: {
                const is_pm = hours >= 12;
                const display_hour = if (hours == 0) 12 else if (hours > 12) hours - 12 else hours;
                const period = if (is_pm) "PM" else "AM";
                break :blk std.fmt.bufPrintZ(buffer, "{:0>4}-{:0>2}-{:0>2} {:0>2}:{:0>2}:{:0>2} {s}", .{ year, month, day, display_hour, minutes, seconds, period });
            },
        } catch {
            return std.fmt.bufPrintZ(buffer, "00:00:00", .{}) catch unreachable;
        };

        return formatted.ptr;
    }

    fn dispose(clock: *Clock) callconv(.c) void {
        // Clean up timer
        if (clock.private().timeout_id != 0) {
            _ = glib.Source.remove(clock.private().timeout_id);
            clock.private().timeout_id = 0;
        }
        // Call parent dispose
        gobject.Object.virtual_methods.dispose.call(Class.parent, clock.as(Parent));
    }

    fn private(clock: *Clock) *Private {
        return gobject.ext.impl_helpers.getPrivate(clock, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = Clock;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }
    };

    const Self = @This();
};
