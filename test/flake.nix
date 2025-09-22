{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "path:../";
  };

  outputs = inputs@{ flake-utils, ... }:
    flake-utils.lib.makeOutputs inputs
      ({ lib, pkgs, makeRustPackage, dev, ... }: {
        default = makeRustPackage pkgs (self: rec {
          src = ./.;

          buildInputs = with pkgs; [
            libpcap
            openssl
          ];

          nativeBuildInputs = with pkgs; [
            makeWrapper
            pkg-config
          ] ++ (lib.optionals dev runtimeInputs);

          nativeCheckInputs = runtimeInputs;
          useNextest = true;
          dontUseCargoParallelTests = true;

          runtimeInputs = with pkgs; [
            nftables
            wireguard-tools
          ];

          postFixup = ''
            wrapProgram $out/bin/${self.meta.mainProgram} \
              --prefix PATH : ${lib.makeBinPath runtimeInputs}
          '';
        });
      });
}
