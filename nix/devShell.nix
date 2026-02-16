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
        if [ -f .env ]; then
            set -a
            source .env
            set +a
        fi

        echo "Development environment loaded!"
        echo ""
        echo "  Zig: $(zig version)"
      '';
    }
