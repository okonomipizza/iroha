const gtk = @import("gtk");

pub fn getWidget(comptime T: type, builder: *gtk.Builder, name: [*:0]const u8) !*T {
    const obj = gtk.Builder.getObject(builder, name) orelse
        return error.WidgetNotFound;
    return @ptrCast(obj);
}
