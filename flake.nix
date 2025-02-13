{
  outputs = { ... }: {
    lib.makeOutputs = ({ self, nixpkgs, ... }: callbackFn:
      let
        inherit (nixpkgs) lib;

        revSuffix = lib.optionalString (self ? shortRev || self ? dirtyShortRev)
          "-${self.shortRev or self.dirtyShortRev}";


        makePackages = ({ system, dev }:
          let
            pkgs = import nixpkgs {
              inherit system;
            };

            makeRustPackageArgs = (args:
              let
                rustManifest = lib.importTOML "${args.src}/Cargo.toml";
              in
              (args // rec {
                pname = args.pname or rustManifest.package.name;
                version = args.version or rustManifest.package.version + revSuffix;

                src =
                  if builtins.isPath args.src
                  then
                    lib.sourceByRegex args.src [
                      "^\.cargo(/.*)?$"
                      "^build\.rs$"
                      "^Cargo\.(lock|toml)$"
                      "^src(/.*)?$"
                    ]
                  else args.src;

                cargoLock = args.cargoLock or {
                  lockFile = "${args.src}/Cargo.lock";
                  outputHashes = { };
                  allowBuiltinFetchGit = true;
                };

                nativeBuildInputs = (args.nativeBuildInputs or [ ])
                  ++ lib.lists.optionals dev (with pkgs; [
                  (rustfmt.override { asNightly = true; })
                  clippy
                  rust-analyzer
                ]);

                meta.mainProgram = args.meta.mainProgram or pname;
              })
            );

            makeRustPackage = (pkgs: argsOrFn:
              pkgs.rustPlatform.buildRustPackage (if builtins.isFunction argsOrFn
              then
                let
                  args = makeRustPackageArgs (argsOrFn args);
                in
                args
              else
                makeRustPackageArgs argsOrFn
              )
            );
          in
          callbackFn {
            inherit lib pkgs system dev makeRustPackage;
          }
        );
      in
      builtins.foldl' lib.recursiveUpdate { } (
        lib.trivial.flip builtins.map lib.systems.flakeExposed (system: {
          devShells.${system} = makePackages { inherit system; dev = true; };
          packages.${system} = makePackages { inherit system; dev = false; };
        })
      )
    );
  };
}
