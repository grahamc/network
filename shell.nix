let
  pkgs = import <nixpkgs> {};

  inherit (pkgs) stdenv;

in stdenv.mkDerivation rec {
  name = "nixops-personal";
  version = "0.1";

  src = builtins.toString ./.;

  buildInputs = [
    pkgs.packet
    (if true then pkgs.nixops else (import ./nixops/release.nix {}).build.x86_64-linux)
    pkgs.jq
  ];

  phases = [ "donotbuild" ];
  donotbuild = ''
    printf "\n\n\nDon't nix-build ${src}! It is a dev environment\n\n\n\n"
    exit 1
  '';

  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  NIXOS_EXTRA_MODULE_PATH = "${src}/modules/default.nix";
  NIXOPS_DEPLOYMENT = "personal";
  HISTFILE = "${src}/.bash_hist";
  NIX_PATH="nixpkgs=https://nixos.org/channels/nixos-18.09/nixexprs.tar.xz";
}
