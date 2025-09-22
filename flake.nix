{
  outputs = { ... }: {
    lib = {
      makeOutputs = ({ self, nixpkgs, ... }: callbackFn:
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

      importPnpmLock = ({ lib, pkgs, pnpmRoot }:
        let
          fetchNpmPackage = ({ name, version, hash }: pkgs.fetchurl {
            # https://registry.npmjs.org/@sveltejs/vite-plugin-svelte-inspector/-/vite-plugin-svelte-inspector-5.0.1.tgz
            inherit hash;
            url =
              let
                split = lib.strings.splitString "/" name;
                shortName = lib.lists.last split;
              in
              "https://registry.npmjs.org/${name}/-/${shortName}-${version}.tgz";
          });

          importYAML = (file:
            builtins.fromJSON (
              builtins.readFile (
                pkgs.runCommandNoCC "yaml.json" { } ''
                  ${lib.getExe pkgs.yj} < "${file}" > "$out"
                ''
              )
            )
          );

          pnpmLockOriginal = importYAML "${pnpmRoot}/pnpm-lock.yaml";
          pnpmLock = pnpmLockOriginal // {
            packages = lib.mapAttrs
              (nameWithVersion: package:
                let
                  # @sveltejs/vite-plugin-svelte-inspector@5.0.1
                  split = lib.strings.splitStringBy
                    (prev: curr:
                      curr == "@" && prev != ""
                    )
                    false
                    nameWithVersion;
                  name = lib.lists.head split;
                  version = lib.lists.last split;
                  hash = package.resolution.integrity;

                  path = fetchNpmPackage {
                    inherit name version hash;
                  };
                in
                package // {
                  # execa@file:../../../../nix/store/...-execa-9.6.0.tgz:
                  #   resolution: {integrity: sha512-..., tarball: file:../../../../nix/store/...-execa-9.6.0.tgz}
                  #   version: 9.6.0
                  resolution = package.resolution // {
                    tarball = "file:${path}";
                  };
                }
              )
              (pnpmLockOriginal.packages or { });
          };
        in
        pkgs.runCommandNoCC "pnpm-modules"
          {
            passAsFile = [
              "pnpmLock"
            ];

            pnpmLock = builtins.toJSON pnpmLock;

            nativeBuildInputs = with pkgs; [
              nodejs
              pnpm
            ];
          }
          ''
            mkdir $out
            cd $out
            cp ${pnpmRoot}/package.json package.json
            cp "$pnpmLockPath" pnpm-lock.yaml
            pnpm install
          ''
      );
    };
  };
}
