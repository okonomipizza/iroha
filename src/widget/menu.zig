const gtk = @import("gtk");
const getWidget = @import("helpers.zig").getWidget;

pub fn setupMenuPopover(builder: *gtk.Builder) !void {
    const menu_popover = try getWidget(gtk.Popover, builder, "menu_popover");
    gtk.Popover.setHasArrow(menu_popover, 0);
}
