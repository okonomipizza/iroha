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

    try buffer.writer.print(
        \\menubutton {{
        \\  padding: 4px 8px;
        \\  border-radius: 6px;
        \\  background: transparent;
        \\  transition: all 200ms ease;
        \\}}
        \\
        \\menubutton:hover {{
        \\  background-color: rgba(255, 255, 255, 0.1);
        \\}}
        \\
        \\menubutton:active {{
        \\  background-color: rgba(255, 255, 255, 0.15);
        \\}}
        \\
    , .{});

    // Mac-style PopoverMenu
    try buffer.writer.print(
        \\/* Popover container */
        \\popover.menu {{
        \\  background-color: {s};
        \\  border-radius: 8px;
        \\  padding: 4px;
        \\  border: none;
        \\}}
        \\
        \\/* Popover contents wrapper */
        \\popover.menu > contents {{
        \\  background: transparent;
        \\  padding: 0;
        \\  box-shadow: none;
        \\  border: none;
        \\}}
        \\
        \\/* Menu items */
        \\popover.menu modelbutton {{
        \\  min-height: 24px;
        \\  padding: 6px 12px;
        \\  border-radius: 4px;
        \\  background: transparent;
        \\  color: {s};
        \\  transition: all 150ms ease;
        \\  box-shadow: none;
        \\}}
        \\
        \\popover.menu modelbutton:hover {{
        \\  background-color: rgba(255, 255, 255, 0.12);
        \\}}
        \\
    , .{
        config.theme.background,
        config.theme.foreground,
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

    try buffer.writer.print(
        \\.launcheer-icon-button {{
        \\  padding: 0 8px;
        \\}}
        \\
        \\/* Launcheer popover */
        \\popover.launcher-popover {{
        \\  background: {s};
        \\  padding: 0;
        \\  border: none;
        \\  border-radius: 0;
        \\}}
        \\
        \\popover.launcher-popover > contents {{
        \\  background: transparent;
        \\  padding: 0;
        \\  border: none;
        \\  border-radius: 0;
        \\}}
        \\
        \\popover.launcher-popover box {{
        \\  background: {s};
        \\  border: none;
        \\}}
        \\ 
        \\popover.launcher-popover scrolledwindow {{
        \\  background: {s};
        \\  border: none;
        \\}}
        \\
        \\popover.launcher-popover scrolledwindow scrollbar {{
        \\  opacity: 0;
        \\}}
        \\
        \\popover.launcher-popover scrolledwindow undershoot.top,
        \\popover.launcher-popover scrolledwindow undershoot.bottom,
        \\popover.launcher-popover scrolledwindow undershoot.left,
        \\popover.launcher-popover scrolledwindow undershoot.right,
        \\popover.launcher-popover scrolledwindow overshoot.top,
        \\popover.launcher-popover scrolledwindow overshoot.bottom,
        \\popover.launcher-popover scrolledwindow overshoot.left,
        \\popover.launcher-popover scrolledwindow overshoot.right {{
        \\  background: none;
        \\}}
        \\
        \\popover.launcher-popover scrolledwindow > undershoot {{
        \\  background: none;
        \\}}
        \\
        \\popover.launcher-popover grid {{
        \\  background: {s};
        \\}}
        \\
        // \\/* Launcher app buttons */
        // \\.launcher-app-button {{
        // \\  padding: 8px;
        // \\  border-radius: 8px;
        // \\  background: transparent;
        // \\  transition: all 200ms ease;
        // \\}}
        // \\
        // \\.launcher-app-button:hover {{
        // \\  background-color: rgba(255, 255, 255, 0.1);
        // \\  transform: scale(1.05);
        // \\}}
        // \\
        // \\.launcher-app-button:active {{
        // \\  background-color: rgba(255, 255, 255, 0.15);
        // \\  transform: scale(0.98);
        // \\}}
        // \\
        // \\.launcher-app-button label {{
        // \\  color: {s};
        // \\  font-size: 11pt;
        // \\}}
        // \\
    , .{
        config.theme.background,
        config.theme.background,
        config.theme.background,
        config.theme.background,
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
