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
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, pwnvim, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (self: super: {
              neovide = super.neovide.overrideAttrs (old: rec {
                nativeBuildInputs = old.nativeBuildInputs ++ [ super.gnused ];
                buildInputs = old.buildInputs ++ (with super; [
                  pwnvim.packages.${system}.pwnvim
                  bat
                  fd
                  fzy
                  git
                  ripgrep
                  zsh
                  zoxide
                ]);
                # We are deliberately allowing existing env to leak in by prefixing path
                # instead of setting it.
                postFixup =
                  builtins.replaceStrings [ "--prefix LD_LIBRARY_PATH" ] [
                    ("--add-flags --notabs " + (if super.stdenv.isDarwin then
                      "--add-flags --novsync --set NEOVIDE_FRAME buttonless --set NEOVIDE_MULTIGRID true "
                    else
                      "") + "--set NEOVIM_BIN ${
                        pwnvim.packages.${system}.pwnvim + "/bin/neovim"
                      } --prefix PATH : ${
                        super.lib.makeBinPath buildInputs
                      } --prefix LD_LIBRARY_PATH")
                  ] old.postFixup;
                # Note: need to update Info.plist with updated versions and such; TODO: should
                # probably automate that with some kind of search/replace instead of copying
                postInstall = (if super.stdenv.isDarwin then ''
                  mkdir -p $out/Applications/Neovide.app/Contents/Resources
                  mkdir -p $out/Applications/Neovide.app/Contents/MacOS
                  cp ${
                    ./extras/Info.plist
                  } $out/Applications/Neovide.app/Contents/Info.plist
                  cp ${
                    ./extras/Neovide.icns
                  } $out/Applications/Neovide.app/Contents/Resources/Neovide.icns
                  ln -s $out/bin/neovide $out/Applications/Neovide.app/Contents/MacOS/neovide
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
