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
            .{ .name = "gtk", .module = gobject.module("gtk4") },
        },
    });

    // const mod = b.addModule("iroha", .{
    //     // The root source file is the "entry point" of this module. Users of
    //     // this module will only be able to access public declarations contained
    //     // in this file, which means that if you have declarations that you
    //     // intend to expose to consumers that were defined in other files part
    //     // of this module, you will have to make sure to re-export them from
    //     // the root file.
    //     .root_source_file = b.path("src/root.zig"),
    //     // Later on we'll use this module as the root module of a test executable
    //     // which requires us to specify a target.
    //     .target = target,
    // });

    const exe = b.addExecutable(.{
        .name = "iroha",
        .root_module = mod,
        // .root_module = b.createModule(.{
        //     // b.createModule defines a new module just like b.addModule but,
        //     // unlike b.addModule, it does not expose the module to consumers of
        //     // this package, which is why in this case we don't have to give it a name.
        //     .root_source_file = b.path("src/main.zig"),
        //     // Target and optimization levels must be explicitly wired in when
        //     // defining an executable or library (in the root module), and you
        //     // can also hardcode a specific target for an executable or library
        //     // definition if desireable (e.g. firmware for embedded devices).
        //     .target = target,
        //     .optimize = optimize,
        //     // List of modules available for import in source files part of the
        //     // root module.
        //     .imports = &.{
        //         // Here "iroha" is the name you will use in your source code to
        //         // import this module (e.g. `@import("iroha")`). The name is
        //         // repeated because you are allowed to rename your imports, which
        //         // can be extremely useful in case of collisions (which can happen
        //         // importing modules from different packages).
        //         .{ .name = "iroha", .module = mod },
        //     },
        // }),
    });

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
    exe.linkLibC();

    b.installArtifact(exe);

    const copy_assets = b.addInstallFile(b.path("src/play.svg"), "bin/play.svg");
    b.getInstallStep().dependOn(&copy_assets.step);

    const exe_run = b.addRunArtifact(exe);
    exe_run.step.dependOn(b.getInstallStep());
    //
    //
    // const run_step = b.step("run", "Run the app");
    //
    // const run_cmd = b.addRunArtifact(exe);
    // run_step.dependOn(&run_cmd.step);
    //
    // // By making the run step depend on the default step, it will be run from the
    // // installation directory rather than directly from within the cache directory.
    // run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        exe_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the example launcher");
    run_step.dependOn(&exe_run.step);
    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    // const mod_tests = b.addTest(.{
    //     .root_module = mod,
    // });
    //
    // // A run step that will run the test executable.
    // const run_mod_tests = b.addRunArtifact(mod_tests);
    //
    // // Creates an executable that will run `test` blocks from the executable's
    // // root module. Note that test executables only test one module at a time,
    // // hence why we have to create two separate ones.
    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });
    //
    // // A run step that will run the second test executable.
    // const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
