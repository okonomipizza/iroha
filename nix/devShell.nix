{
    mkShell,
    zig,
    zls,
    curl,
}: let
  in
    mkShell {
      name = "gtk-zig-dev";
      packages =
        [
          zig
          zls
          curl
        ];

      shellHook = ''
        echo "Development environment loaded!"
        echo ""
        echo "  Zig: $(zig version)"
      '';
    }
