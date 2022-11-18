self: super: {
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
}
