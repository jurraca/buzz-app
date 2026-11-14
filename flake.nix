{
  description = "Buzz 1.0 desktop and web app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/867dcbc30bafe3c862ef88620f2e7a109d7d3be5";
    flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";
    fenix = {
      url = "github:nix-community/fenix/3df888be63045c349a6d322f0214f1346bb18be9";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      fenix,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          toolchain = fenix.packages.${system}.fromToolchainFile {
            file = ./rust-toolchain.toml;
            sha256 = "sha256-p8h3Sl/YRByZfZTAKXdsvF6xEenXKrXSVvpphmZENH4=";
          };
          rustPlatform = pkgs.makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
          };
          source = pkgs.lib.cleanSourceWith {
            src = self;
            filter =
              path: type:
              let
                name = baseNameOf path;
              in
              !(
                (
                  type == "directory"
                  && builtins.elem name [
                    ".git"
                    ".github"
                    ".agents"
                    ".hermit"
                    ".scratch"
                    ".buzz"
                    ".vite"
                    "artifacts"
                    "bin"
                    "coverage"
                    "dist"
                    "node_modules"
                    "playwright-report"
                    "result"
                    "target"
                    "test-results"
                    "src-tauri/gen"
                  ]
                )
                || builtins.elem name [
                  ".env"
                  ".env.local"
                  ".npmrc"
                  "flake.lock"
                  "result"
                ]
              );
          };
          buzzAppPackages = pkgs.callPackage ./nix/buzz-app.nix {
            inherit rustPlatform;
            src = source;
          };
        in
        {
          packages = {
            inherit (buzzAppPackages)
              buzz-app
              buzz-web
              buzz-cli
              goose-acp
              ;
            default = buzzAppPackages.buzz-app;
          };

          apps = {
            default = {
              type = "app";
              program = "${buzzAppPackages.buzz-app}/bin/Buzz";
              meta.description = "Run the Buzz desktop app";
            };
            buzz-web = {
              type = "app";
              program = "${pkgs.writeShellScript "buzz-web-serve" ''
                echo "Serving ${buzzAppPackages.buzz-web} on http://localhost:8080"
                exec ${pkgs.python3}/bin/python3 -m http.server 8080 --directory ${buzzAppPackages.buzz-web}
              ''}";
              meta.description = "Serve the Buzz web build on localhost:8080";
            };
          };

          checks = {
            smoke = pkgs.runCommand "buzz-app-smoke-check" { } ''
              test -x ${buzzAppPackages.buzz-app}/bin/Buzz
              ls ${buzzAppPackages.buzz-app}/share/applications/*.desktop >/dev/null
              test -x ${buzzAppPackages.buzz-app}/lib/xyz.block.buzz.desktop/resources/bin/goose-acp
              test -x ${buzzAppPackages.buzz-app}/lib/xyz.block.buzz.desktop/resources/bin/buzz-agent-command
              test -x ${buzzAppPackages.buzz-app}/lib/xyz.block.buzz.desktop/resources/bin/buzz
              test -f ${buzzAppPackages.buzz-web}/index.html
              test -x ${buzzAppPackages.buzz-cli}/bin/buzz
              test -x ${buzzAppPackages.goose-acp}/bin/goose-acp
              touch "$out"
            '';
          };

          formatter = pkgs.nixfmt;

          devShells = {
            # Keep the default shell small: the desktop's native inputs are
            # heavy and only needed for `nix build`.
            default = pkgs.mkShell {
              packages = [
                toolchain
                pkgs.nodejs_24
                pkgs.pnpm
                pkgs.just
              ];
            };
          };
        }
      );
}
