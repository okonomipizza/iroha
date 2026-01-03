const std = @import("std");
const Config = @import("config.zig");
const gtk = @import("gtk");
const gdk = @import("gdk");
const AppContext = @import("main.zig").AppContext;

pub fn generateCss(allocator: std.mem.Allocator, config: *const Config) ![:0]const u8 {
    var buffer = std.Io.Writer.Allocating.init(allocator);
    defer buffer.deinit();

    // Window style
    try buffer.writer.print(
        \\window {{
        \\  background-color: {s};
        \\  color: {s};
        \\  padding: {d}px {d}px {d}px {d}px;
        \\}}
        \\
        \\#main_box {{
        \\  min-height: {d}px;
        \\}}
        \\
    , .{
        config.theme.background,
        config.theme.foreground,
        config.bar.margin.top,
        config.bar.margin.right,
        config.bar.margin.bottom,
        config.bar.margin.left,
        config.bar.height,
    });

    // Global font settings
    try buffer.writer.print(
        \\* {{
        \\  font-family: {s};
        \\  font-size: {d}pt;
        \\}}
        \\
        \\label {{
        \\  color: {s};
        \\}}
        \\
    , .{
        config.theme.@"font-family",
        config.theme.@"font-size",
        config.theme.@"clock-color",
    });

    // Button styles (Clock, Menu buttons)
    try buffer.writer.print(
        \\button {{
        \\  padding: 0 4px;
        \\  min-height: 0;
        \\  border: none;
        \\  background: transparent;
        \\  border-radius: 4px;
        \\  color: {s};
        \\  transition: background-color 200ms ease;
        \\}}
        \\
        \\button:hover {{
        \\  background-color: rgba(255, 255, 255, 0.1);
        \\}}
        \\
    , .{
        config.theme.@"clock-color",
    });

    // Mac-style PopoverMenu
    try buffer.writer.writeAll(
        \\/* Popover container */
        \\popover.menu {
        \\  background-color: rgba(40, 40, 50, 0.95);
        \\  border-radius: 8px;
        \\  padding: 2px 6px;
        \\}
        \\
        \\/* Popover contents wrapper */
        \\popover.menu > contents {
        \\  background: transparent;
        \\  padding: 0;
        \\  box-shadow: none;
        \\  border: none;
        \\}
        \\
        \\/* Menu items */
        \\popover.menu modelbutton {
        \\  min-height: 10px;
        \\  padding: 1px 10px;
        \\  border-radius: 4px;
        \\  background: transparent;
        \\  color: #cdd6f4;
        \\  transition: all 150ms ease;
        \\  box-shadow: none;
        \\}
        \\
        \\popover.menu modelbutton:hover {
        \\ background-color: rgba(137, 180, 250, 0.2);
        \\}
        \\
    );

    try buffer.writer.print(
        \\/* Music control buttons */
        \\.music_container {{
        \\  background: {s};
        \\  border-radius: 6px;
        \\  margin: 0 4px;
        \\}}
        \\
        \\scrolledwindow.music-scroll scrollbar {{
        \\  opacity: 0;
        \\}}
        \\
    , .{
        config.theme.background_darker,
    });
    return try buffer.toOwnedSliceSentinel(0);
}

pub fn loadCss(
    allocator: std.mem.Allocator,
    config: *const Config,
    existing_provider: ?*gtk.CssProvider,
) !*gtk.CssProvider {
    if (existing_provider) |provider| {
        provider.unref();
    }

    const css = try generateCss(allocator, config);
    std.debug.print("Generated CSS:\n{s}\n", .{css});
    defer allocator.free(css);

    const provider = gtk.CssProvider.new();
    gtk.CssProvider.loadFromData(provider, css.ptr, @intCast(css.len));

    // Apply css to display
    const display = gdk.Display.getDefault();
    if (display) |d| {
        gtk.StyleContext.addProviderForDisplay(
            d,
            provider.as(gtk.StyleProvider),
            gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    return provider;
}
