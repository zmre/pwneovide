{
  description = "PW's Neovide (pwneovide) with pwnvim";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.nixpkgs.follows = "nixpkgs";
    neovide-direct.url = "github:neovide/neovide";
    neovide-direct.flake = false;
    pwnvim.url = "github:zmre/pwnvim";
    pwnvim.inputs.nixpkgs.follows = "nixpkgs";

    cargo-bundle = {
      url = "github:burtonageo/cargo-bundle";
      flake = false;
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, pwnvim, neovide-direct
    , rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import rust-overlay)
            (self: super: {
              cargo-bundle = (self.makeRustPlatform {
                inherit (inputs.fenix.packages.${self.system}.minimal)
                  cargo rustc;
              }).buildRustPackage {
                name = "cargo-bundle";
                pname = "cargo-bundle";
                cargoLock = { lockFile = inputs.cargo-build + /Cargo.lock; };
                buildDependencies = [ self.glib ];
                buildInputs = [ self.pkg-config self.libiconv ]
                  ++ self.lib.optionals self.stdenv.isDarwin
                  [ self.darwin.apple_sdk.frameworks.Security ];
                src = inputs.cargo-build;
              };
            })

            # (self: super: {
            #   neovide = super.neovide.overrideAttrs (old: {
            #     postInstall = (if super.stdenv.isDarwin then ''
            #       mkdir $out/Applications
            #       cp -r bundle/osx/Neovide.app $out/Applications
            #       ln -s $out/bin $out/Applications/Neovide.app/Contents/MacOS
            #     '' else
            #       old.postInstall);
            #     nativeBuildInputs = old.nativeBuildInputs
            #       ++ [ super.cargo-bundle ];
            #     postBuild = "cargo bundle --release";
            #   });
            # })
          ];
        };
        rusttoolchain = pkgs.rust-bin.fromRustupToolchainFile neovide-direct
          + /rust-toolchain.toml;
        cargoToml =
          (builtins.fromTOML (builtins.readFile neovide-direct + /Cargo.toml));

      in rec {
        packages.pwneovide = pkgs.rustPlatform.buildRustPackage rec {
          pname = "pwneovide";
          version = cargoToml.package.version;
          # SKIA_NINJA_COMMAND = "${ninja}/bin/ninja";
          # SKIA_GN_COMMAND = "${gn}/bin/gn";
          # LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

          preConfigure = ''
            unset CC CXX
          '';

          # test needs a valid fontconfig file
          # FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ ]; };

          nativeBuildInputs = with pkgs;
            [
              inputs.cargo-bundle.packages.${system}.cargo-bundle
              pkg-config
              makeWrapper
              python2 # skia-bindings
              python3 # rust-xcb
              llvmPackages.clang # skia
              removeReferencesTo
              neovide-direct
            ] ++ lib.optionals stdenv.isDarwin [ xcbuild ];

          doCheck = false;

          buildInputs = with pkgs;
            [
              pwnvim.packages.${system}.pwnvim
              openssl
              SDL2
              (fontconfig.overrideAttrs (old: {
                propagatedBuildInputs = [
                  #   # skia is not compatible with freetype 2.11.0
                  #   (freetype.overrideAttrs (old: rec {
                  #     version = "2.10.4";
                  #     src = fetchurl {
                  #       url = "mirror://savannah/${old.pname}/${old.pname}-${version}.tar.xz";
                  #       sha256 = "112pyy215chg7f7fmp2l9374chhhpihbh8wgpj5nj6avj3c59a46";
                  #     };
                  #   }))
                ];
              }))
            ] ++ lib.optionals stdenv.isDarwin
            (with pkgs; [ Security ApplicationServices Carbon AppKit ]);

          postFixup = let
            libPath = pkgs.lib.makeLibraryPath (with pkgs;
              [
                libglvnd
                libxkbcommon
                xorg.libXcursor
                xorg.libXext
                xorg.libXrandr
                xorg.libXi
              ] ++ lib.optionals enableWayland [ wayland ]);
          in ''
            # library skia embeds the path to its sources
            # remove-references-to -t "$SKIA_SOURCE_DIR" \
              # $out/bin/neovide

            wrapProgram $out/bin/neovide \
              --prefix LD_LIBRARY_PATH : ${libPath}
          '';

          postInstall = ''
            for n in 16x16 32x32 48x48 256x256; do
              install -m444 -D "assets/neovide-$n.png" \
                "$out/share/icons/hicolor/$n/apps/neovide.png"
            done
            install -m444 -Dt $out/share/icons/hicolor/scalable/apps assets/neovide.svg
            install -m444 -Dt $out/share/applications assets/neovide.desktop
          '';

          # disallowedReferences = [ SKIA_SOURCE_DIR ];

        };

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
