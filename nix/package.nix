{
  lib,
  stdenv,
  zig,
  pkg-config,
  fetchFromGitHub,
  curl,
  autoPatchelfHook,
  revision ? "dirty",
  optimize ? "Debug",
}: let
  zig_clap = fetchFromGitHub {
    owner = "Hejsil";
    repo = "zig-clap";
    rev = "27621cb7207643f914bae7b01902b22a8b5916e7";
    sha256 = "sha256-jqzzo1ma78M8lfLfdXHyzEsr6PEPQSigrF3Nx2EJ/LI=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "iroha";
    version = "0.1.0-${revision}";
    src = lib.cleanSource ../.;

    nativeBuildInputs = [
      zig
      pkg-config
      autoPatchelfHook
    ];

    buildInputs = [
      curl
    ];

    ZIG_GLOBAL_CACHE_DIR = "$TMPDIR/zig-cache";

    configurePhase = ''
      runHook preConfigure
      export HOME=$TMPDIR
      mkdir -p $ZIG_GLOBAL_CACHE_DIR

      # Setup dependencies directory
      mkdir -p .zig-cache/p

      # Setup dependencies directory
      mkdir -p ./deps
      cp -r ${zig_clap} ./deps/zig_clap
      chmod -R +w ./deps/zig_clap

      # Create modified build.zig.zon for Nix build
      cat > build.zig.zon <<'ZON_EOF'
.{
    .name = .iroha,
    .version = "0.0.1",
    .fingerprint = 0x472cb64af18edb93,
    .minimum_zig_version = "0.16.0-dev.2623+27eec9bd6",
    .dependencies = .{
        .clap = .{
            .path = "./deps/zig_clap",
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
        --prefix $out \
        -Doptimize=${optimize} \

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      if [ ! -f "$out/bin/iroha" ]; then
        echo "Error: binary not found"
        find $out -type f
        exit 1
      fi
      runHook postInstall
    '';

    meta = {
      description = "Pipe to AI - CLI tool to pipe input to Claude API";
      homepage = "https://github.com/okonomipizza/iroha";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "iroha";
    };
  })
