const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const zig_jsonc = b.dependency("zig_jsonc", .{});

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

    exe.root_module.addImport("zig_jsonc", zig_jsonc.module("zig_jsonc"));

    // const ui_dir_path = b.pathJoin(&.{ b.cache_root.path.?, "ui" });
    // const ui_cache_path = b.pathJoin(&.{ ui_dir_path, "system-bar.ui" });

    // const mkdir_ui = b.addSystemCommand(&.{ "mkdir", "-p", ui_dir_path });

    const blueprint_compile = b.addSystemCommand(&.{
        "sh",
        "-c",
        "mkdir -p .zig-cache/ui && blueprint-compiler compile --output .zig-cache/ui/system-bar.ui src/ui/system-bar.blp",
    });

    exe.step.dependOn(&blueprint_compile.step);

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
