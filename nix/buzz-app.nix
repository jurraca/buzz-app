{
  lib,
  rustPlatform,
  fetchPnpmDeps,
  fetchurl,
  fetchFromGitHub,
  runCommand,
  cmake,
  cargo-tauri,
  nodejs,
  pnpm,
  pnpmConfigHook,
  pkg-config,
  perl,
  autoPatchelfHook,
  wrapGAppsHook3,
  gst_all_1,
  glib-networking,
  bzip2,
  openssl,
  webkitgtk_4_1,
  alsa-lib,
  libopus,
  dbus,
  glib,
  gtk3,
  libayatana-appindicator,
  libsoup_3,
  librsvg,
  libiconv,
  stdenv,
  src,
}:

let
  versions = import ./versions.nix;

  tauriConf = builtins.fromJSON (builtins.readFile (src + "/src-tauri/tauri.conf.json"));
  appVersion = tauriConf.version;

  # The bundled `buzz` CLI is built from the block/buzz revision pinned as the
  # buzz-audio-client git dependency (see scripts/build-buzz-cli.mjs).
  cargoToml = builtins.readFile (src + "/src-tauri/Cargo.toml");
  buzzCliRevMatch = builtins.match ".*buzz-audio-client = [{][^}]*rev = \"([0-9a-f]{40})\".*" cargoToml;
  buzzCliRev =
    if buzzCliRevMatch == null then
      throw "src-tauri/Cargo.toml has no buzz-audio-client git revision to build buzz from"
    else
      builtins.head buzzCliRevMatch;

  goosePin = builtins.fromJSON (builtins.readFile (src + "/runtime/goose-acp.json"));
  gooseTriple =
    {
      "x86_64-linux" = "x86_64-unknown-linux-gnu";
      "aarch64-linux" = "aarch64-unknown-linux-gnu";
      "x86_64-darwin" = "x86_64-apple-darwin";
      "aarch64-darwin" = "aarch64-apple-darwin";
    }
    .${stdenv.hostPlatform.system} or (throw "Unsupported platform for goose-acp: ${stdenv.hostPlatform.system}");

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    name = "buzz-app-cargo-deps";
    hash = versions.cargoHash;
  };

  pnpmDeps = fetchPnpmDeps {
    pname = "buzz-app";
    version = appVersion;
    inherit src pnpm;
    fetcherVersion = 4;
    hash = versions.pnpmHash;
  };

  buzzCliSrc = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    rev = buzzCliRev;
    hash = versions.buzzCliSrcHash;
  };

  buzzCliCargoDeps = rustPlatform.fetchCargoVendor {
    src = buzzCliSrc;
    name = "buzz-cli-pin-cargo-deps";
    hash = versions.buzzCliCargoHash;
  };

  buzzCli = rustPlatform.buildRustPackage {
    pname = "buzz-cli";
    version = builtins.substring 0 12 buzzCliRev;
    src = buzzCliSrc;
    cargoDeps = buzzCliCargoDeps;
    cargoBuildFlags = [
      "-p"
      "buzz-cli"
      "--locked"
    ];
    doCheck = false;
    nativeBuildInputs = [
      cmake
      pkg-config
    ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openssl ];
    meta = with lib; {
      description = "Command-line client for Buzz relays (pinned block/buzz revision)";
      homepage = "https://github.com/block/buzz";
      license = licenses.asl20;
      mainProgram = "buzz";
    };
  };

  gooseAcp = runCommand "goose-acp-${goosePin.version}" {
    archive = fetchurl {
      url = goosePin.assets.${gooseTriple}.url;
      sha256 = goosePin.assets.${gooseTriple}.sha256;
    };
  } ''
    mkdir -p "$out/bin"
    tar -xOf "$archive" goose-acp > "$out/bin/goose-acp"
    chmod 0755 "$out/bin/goose-acp"
  '';

  buzzWeb = stdenv.mkDerivation {
    pname = "buzz-web";
    version = appVersion;
    inherit src;
    pnpmDeps = pnpmDeps;
    nativeBuildInputs = [
      nodejs
      pnpm
      pnpmConfigHook
    ];
    buildPhase = ''
      runHook preBuild
      ./node_modules/.bin/tsc --noEmit
      ./node_modules/.bin/vite build
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r dist/. "$out/"
      runHook postInstall
    '';
    meta = with lib; {
      description = "Buzz web frontend build (static files)";
      homepage = "https://buzz.ai";
      license = licenses.asl20;
    };
  };
in
{
  buzz-cli = buzzCli;
  goose-acp = gooseAcp;
  buzz-web = buzzWeb;

  buzz-app = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "buzz-app";
    version = appVersion;
    inherit src;

    cargoRoot = "src-tauri";
    buildAndTestSubdir = "src-tauri";

    # The workspace lockfile lives at the repo root, not beside src-tauri;
    # cargoSetupHook expects it at cargoRoot for vendor consistency checks.
    postPatch = ''
      cp Cargo.lock src-tauri/Cargo.lock
    '';

    cargoDeps = cargoDeps;

    doCheck = false;

    AWS_LC_SYS_CMAKE_BUILDER = 1;

    pnpmDeps = pnpmDeps;

    # The upstream beforeBuildCommand downloads goose-acp and clones
    # block/buzz; both are staged from Nix derivations in preBuild instead, and
    # the frontend is built directly below, so replace beforeBuildCommand with
    # a no-op via a --config merge (TAURI_CONFIG env is only read at compile
    # time by tauri-build, not for beforeBuildCommand).
    tauriBuildFlags = [
      "--config"
      ''{"build":{"beforeBuildCommand":"true"}}''
    ];

    preBuild = ''
      export CARGO_TARGET_DIR="$PWD/target"
      cargo build --locked --offline -p buzz-agent-command --release
      mkdir -p src-tauri/resources/bin
      install -m0755 target/release/buzz-agent-command src-tauri/resources/bin/buzz-agent-command
      install -m0755 ${gooseAcp}/bin/goose-acp src-tauri/resources/bin/goose-acp
      install -m0755 ${buzzCli}/bin/buzz src-tauri/resources/bin/buzz
      ./node_modules/.bin/tsc --noEmit
      ./node_modules/.bin/vite build
    '';

    nativeBuildInputs = [
      cmake
      cargo-tauri.hook
      nodejs
      perl
      pnpm
      pnpmConfigHook
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
      wrapGAppsHook3
    ];

    buildInputs =
      lib.optionals stdenv.hostPlatform.isLinux [
        alsa-lib
        bzip2
        dbus
        glib
        glib-networking
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gtk3
        libayatana-appindicator
        libopus
        librsvg
        libsoup_3
        openssl
        webkitgtk_4_1
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

    passthru = {
      inherit buzzCli gooseAcp;
    };

    meta = with lib; {
      description = "Buzz desktop app";
      homepage = "https://buzz.ai";
      license = licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      mainProgram = "Buzz";
    };
  });
}
