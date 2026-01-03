const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "glib", .module = gobject.module("glib2") },
            .{ .name = "gobject", .module = gobject.module("gobject2") },
            .{ .name = "gio", .module = gobject.module("gio2") },
            .{ .name = "cairo", .module = gobject.module("cairo1") },
            .{ .name = "pango", .module = gobject.module("pango1") },
            .{ .name = "pangocairo", .module = gobject.module("pangocairo1") },
            .{ .name = "gdk", .module = gobject.module("gdk4") },
            .{ .name = "gdkpixbuf", .module = gobject.module("gdkpixbuf2") },
            .{ .name = "gtk", .module = gobject.module("gtk4") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "iroha",
        .root_module = mod,
    });

    const zig_jsonc = b.dependency("zig_jsonc", .{});
    exe.root_module.addImport("zig_jsonc", zig_jsonc.module("zig_jsonc"));

    const blueprint_cmd = b.addSystemCommand(&.{
        "blueprint-compiler",
        "compile",
        "--output",
    });
    const ui_output = blueprint_cmd.addOutputFileArg("system-bar.ui");
    blueprint_cmd.addFileArg(b.path("src/ui/system-bar.blp"));

    // For dev
    const install_dev_ui = b.addInstallFile(ui_output, "ui/system-bar.ui");

    // For production
    const install_prod_ui = b.addInstallFile(ui_output, "share/iroha/ui/system-bar.ui");

    b.getInstallStep().dependOn(&install_dev_ui.step);
    b.getInstallStep().dependOn(&install_prod_ui.step);

    const layer_shell_flags = b.run(&.{ "pkg-config", "--cflags", "--libs", "gtk4-layer-shell-0" });
    var layer_shell_flag_iter = std.mem.splitAny(u8, std.mem.trim(u8, layer_shell_flags, " \n\r\t"), " ");
    while (layer_shell_flag_iter.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I")) {
            exe.addIncludePath(.{ .cwd_relative = flag[2..] });
        } else if (std.mem.startsWith(u8, flag, "-L")) {
            exe.addLibraryPath(.{ .cwd_relative = flag[2..] });
        } else if (std.mem.startsWith(u8, flag, "-l")) {
            exe.linkSystemLibrary(flag[2..]);
        }
    }

    b.installArtifact(exe);

    const exe_run = b.addRunArtifact(exe);
    exe_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        exe_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&exe_run.step);
}
