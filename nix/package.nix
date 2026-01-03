{
  lib,
  stdenv,
  zig,
  gtk4,
  gtk4-layer-shell,
  pkg-config,
  fetchurl,
  fetchFromGitHub,
  gobject-introspection,
  glib,
  libadwaita,
  zstd,
  wayland,
  wrapGAppsHook4,
  wayland-protocols,
  wayland-scanner,
  autoPatchelfHook,
  blueprint-compiler,
  revision ? "dirty",
  optimize ? "Debug",
}: let
  zig-gobject-bindings = fetchurl {
    name = "bindings-gnome46.tar.zst";
    url = "https://github.com/ianprime0509/zig-gobject/releases/download/v0.3.0/bindings-gnome46.tar.zst";
    sha256 = "sha256-OLAXyMv6GgsTGdDLEACO/wynuxbD6sobfzqDloYTrys=";
  };

  zig_jsonc = fetchFromGitHub {
    owner = "okonomipizza";
    repo = "zig_jsonc";
    rev = "e0ebeef0035ecc661efbdbb9c7223fdc3b9df9d0";
    sha256 = "sha256-5wnI5vmafxYo0qwzsqhtQ4dhdazGVVblHQkpgPR6cuE=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "iroha";
    version = "0.2.3-${revision}";

    src = lib.cleanSource ../.;

    nativeBuildInputs = [
      zig
      pkg-config
      gobject-introspection
      wrapGAppsHook4
      zstd
      wayland-scanner
      wayland-protocols
      autoPatchelfHook
      blueprint-compiler
    ];

    buildInputs = [
      glib
      gtk4
      gtk4-layer-shell
      libadwaita
      wayland
      stdenv.cc.cc.lib
    ];

    dontWrapGApps = true;

    ZIG_GLOBAL_CACHE_DIR = "$TMPDIR/zig-cache";
    XDG_CACHE_HOME = "$TMPDIR/cache";

    configurePhase = ''
      runHook preConfigure

      export HOME=$TMPDIR
      mkdir -p $ZIG_GLOBAL_CACHE_DIR
      mkdir -p $XDG_CACHE_HOME

      # Extract zig-gobject bindings
      mkdir -p zig-out
      cd zig-out
      ${zstd}/bin/zstd -d < ${zig-gobject-bindings} | tar -xf -
      cd ..

      # Setup dependencies directory
      mkdir -p ./deps
      cp -r ${zig_jsonc} ./deps/zig_jsonc
      chmod -R +w ./deps/zig_jsonc

      # Create modified build.zig.zon for Nix build
      cat > build.zig.zon <<'ZON_EOF'
.{
    .name = .iroha,
    .version = "0.1.0",
    .fingerprint = 0x472cb64aa2c7ec1c,
    .minimum_zig_version = "0.15.1",
    .dependencies = .{
        .gobject = .{
            .path = "./zig-out/bindings",
        },
        .zig_jsonc = .{
            .path = "./deps/zig_jsonc",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
ZON_EOF

      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild

      zig build \
        --prefix $TMPDIR/install \
        -Doptimize=${optimize} \
        --verbose

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      if [ -f "$TMPDIR/install/bin/iroha" ]; then
        cp $TMPDIR/install/bin/iroha $out/bin/iroha
        chmod +x $out/bin/iroha
      else
        echo "Error: Binary not found at $TMPDIR/install/bin/iroha"
        exit 1
      fi

      runHook postInstall
    '';

    meta = {
      description = "GTK4 Layer Shell status bar application written in Zig";
      homepage = "https://github.com/okonomipizza/iroha";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "iroha";
    };
  })
