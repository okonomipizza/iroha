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
  version,
}: let
  zig_clap = fetchFromGitHub {
    owner = "Hejsil";
    repo = "zig-clap";
    rev = "27621cb7207643f914bae7b01902b22a8b5916e7";
    sha256 = "sha256-jqzzo1ma78M8lfLfdXHyzEsr6PEPQSigrF3Nx2EJ/LI=";
  };
  zig_jsonc = fetchFromGitHub {
    owner = "okonomipizza";
    repo = "zig-jsonc";
    rev = "7c23a50aff684e559f176c19f1ba6a2d0f51d1ad";
    sha256 = "sha256-Qs82YFZ/bKj8WK7yf7rnCBtC2hkncXehGw89HZaSEJM=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "iroha";
    version = "${version}-${revision}";
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
      cp -r ${zig_jsonc} ./deps/zig_jsonc
      chmod -R +w ./deps/zig_jsonc

      # Create modified build.zig.zon for Nix build
      cat > build.zig.zon <<'ZON_EOF'
.{
    .name = .iroha,
    .version = "${version}",
    .fingerprint = 0x472cb64af18edb93,
    .minimum_zig_version = "0.16.0-dev.2623+27eec9bd6",
    .dependencies = .{
        .clap = .{
            .path = "./deps/zig_clap",
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
