{
    mkShell,
    zig,
    system,
    gtk4,
    gtk4-layer-shell,
    pkg-config,
    pkgs,
    fetchurl,
    gobject-introspection,
    glib,
    cairo,
    pango,
    gdk-pixbuf,
    libadwaita,
    adwaita-icon-theme,
    hicolor-icon-theme,
    zstd,
    zls,
    blueprint-compiler,
    
}: let
    wayland-protocols-path = "${pkgs.wayland-protocols}/share/wayland-protocols";
    wlr-protocols-path = "${pkgs.wlr-protocols}/share/wlr-protocols";
    zig-gobject-bindings = fetchurl {
        name = "bindings-gnome46.tar.zst";
        url = "https://github.com/ianprime0509/zig-gobject/releases/download/v0.3.0/bindings-gnome46.tar.zst";
        sha256 = "sha256-OLAXyMv6GgsTGdDLEACO/wynuxbD6sobfzqDloYTrys=";
    };
  in
    mkShell {
      name = "gtk-zig-dev";
      packages =
        [
          zig
          zls
          gtk4
          gtk4-layer-shell
          pkg-config
          
          gobject-introspection
          glib
          cairo
          pango
          gdk-pixbuf
          libadwaita
          zstd
          blueprint-compiler
          adwaita-icon-theme

      pkgs.wayland
      pkgs.wayland-protocols
      pkgs.wlr-protocols
      pkgs.wayland-scanner
      pkgs.pkg-config
      pkgs.libxkbcommon
        ];

      shellHook = ''
        echo "Development environment loaded!"
        echo ""
        echo "  Zig: $(zig version)"
        echo "  GTK4: $(pkg-config --modversion gtk4)"
        echo "  GTK4 Layer Shell: $(pkg-config --modversion gtk4-layer-shell-0 2>/dev/null || echo "available")"
        echo "  GObject Introspection: $(pkg-config --modversion gobject-introspection-1.0)"
              echo "Protocol paths:"
              echo "  WAYLAND_PROTOCOLS: ${wayland-protocols-path}"
              echo "  WLR_PROTOCOLS: ${wlr-protocols-path}"
              echo ""
                export WAYLAND_PROTOCOLS_DIR="${wayland-protocols-path}"
                export WLR_PROTOCOLS_DIR="${wlr-protocols-path}"
              echo "Ready for development!!"
        echo ""

        if [ ! -d "zig-out/bindings" ]; then
            echo "Setting up zig-gobject bindings..."
            mkdir -p zig-out
            cd zig-out
            zstd -d < ${zig-gobject-bindings} | tar -xf -
            cd ..
            echo "  ✓ Bindings extracted to zig-out/bindings/"
        else
            echo "  ✓ zig-gobject bindings already available"
        fi

        # GIR/TypeLib path
          export GI_TYPELIB_PATH="${pkgs.gtk4}/lib/girepository-1.0:${pkgs.libadwaita}/lib/girepository-1.0:${pkgs.glib}/lib/girepository-1.0:${pkgs.cairo}/lib/girepository-1.0:${pkgs.pango}/lib/girepository-1.0:${pkgs.gdk-pixbuf}/lib/girepository-1.0:$GI_TYPELIB_PATH"
          export XDG_DATA_DIRS="${pkgs.gtk4}/share:${pkgs.libadwaita}/share:${pkgs.glib}/share:$XDG_DATA_DIRS"
          export XDG_DATA_DIRS=$XDG_DATA_DIRS:${hicolor-icon-theme}/share:${adwaita-icon-theme}/share
      
        
        echo "Ready for development!!"
      '';
      PKG_CONFIG_PATH = "${pkgs.gtk4}/lib/pkgconfig:${pkgs.gtk4-layer-shell}/lib/pkgconfig:${pkgs.libadwaita}/lib/pkgconfig:${pkgs.glib}/lib/pkgconfig:${pkgs.cairo}/lib/pkgconfig:${pkgs.pango}/lib/pkgconfig";
    }
