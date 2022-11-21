{
  description = "PW's Neovide (pwneovide) with pwnvim";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    pwnvim.url = "github:zmre/pwnvim";
    pwnvim.inputs.nixpkgs.follows = "nixpkgs";

    cargo-bundle = {
      url = "github:burtonageo/cargo-bundle";
      flake = false;
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, pwnvim, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (self: super: rec {
              cargo-bundle = self.rustPlatform.buildRustPackage {
                name = "cargo-bundle";
                pname = "cargo-bundle";
                cargoLock = { lockFile = inputs.cargo-bundle + /Cargo.lock; };
                buildDependencies = [ self.glib ];
                buildInputs = [ self.pkg-config self.libiconv ]
                  ++ self.lib.optionals self.stdenv.isDarwin
                  (with self.darwin.apple_sdk.frameworks; [
                    Security
                    CoreGraphics
                    CoreVideo
                    AppKit
                  ]);
                src = inputs.cargo-bundle;
              };
            })
            (self: super: {
              # neovide = super.callPackage
              #   (nixpkgs + /pkgs/applications/editors/neovim/neovide) {
              #     AppKit = self.darwin.apple_sdk.frameworks.AppKit;
              #     Security = self.darwin.apple_sdk.frameworks.Security;
              #     Carbon = self.darwin.apple_sdk.frameworks.Carbon;
              #     ApplicationServices =
              #       self.darwin.apple_sdk.frameworks.ApplicationServices;
              #     rustPlatform = super.rustPlatform // {
              #       buildRustPackage = args:
              #         super.rustPlatform.buildRustPackage (args // {
              #           # Can override args to buildRustPackage here
              #           postInstall = (if super.stdenv.isDarwin then
              #             args.postInstall + ''
              #               mkdir $out/Applications
              #               pwd
              #               ls
              #               echo out: $out
              #               cp -r ./target/release-tmp/bundle/osx/Neovide.app $out/Applications
              #             ''
              #           else
              #             args.postInstall);
              #           nativeBuildInputs = args.nativeBuildInputs
              #             ++ [ self.cargo-bundle ];
              #           buildInputs = args.buildInputs
              #             ++ [ pwnvim.packages.${system}.pwnvim ];
              #           postBuild = ''
              #             cargo bundle --release

              #             target=${
              #               super.rust.toRustTargetSpec
              #               super.stdenv.hostPlatform
              #             }

              #             releaseDir=target/$target/release
              #             tmpDir="$releaseDir-tmp";

              #             mkdir -p $tmpDir
              #             cp -r target/release/bundle $tmpDir/
              #           '';
              #         });
              #     };
              #   };
              neovide = super.neovide.overrideAttrs (old: {
                nativeBuildInputs = old.nativeBuildInputs
                  ++ [ self.cargo-bundle ];
                buildInputs = old.buildInputs
                  ++ [ pwnvim.packages.${system}.pwnvim ];
                postBuild = (if super.stdenv.isDarwin then ''
                  cargo bundle --release

                  target=${
                    super.rust.toRustTargetSpec super.stdenv.hostPlatform
                  }

                  releaseDir=target/$target/release
                  tmpDir="$releaseDir-tmp";

                  mkdir -p $tmpDir
                  cp -r target/release/bundle $tmpDir/
                '' else
                  old.postBuild);
                postInstall = (if super.stdenv.isDarwin then ''
                  mkdir $out/Applications
                  pwd
                  ls
                  echo out: $out
                  cp -r ./target/release-tmp/bundle/osx/Neovide.app $out/Applications
                  # mkdir $out/Applications
                  # pwd
                  # ls
                  # echo out: $out
                  # cp -r ./target/release/bundle/osx/Neovide.app $out/Applications
                  # ln -s $out/bin $out/Applications/Neovide.app/Contents/MacOS
                '' else
                  old.postInstall);
              });
            })

          ];
        };

      in rec {
        packages.pwneovide = pkgs.neovide;

        apps.pwneovide = flake-utils.lib.mkApp {
          drv = packages.pwneovide;
          name = "pwneovide";
          exePath = "/bin/neovide";
        };
        packages.default = packages.pwneovide;
        apps.default = apps.pwneovide;
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [ packages.pwneovide ] ++ dependencies;
        };
      });

}
