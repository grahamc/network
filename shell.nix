let
  pkgs = import <nixpkgs> {};

  inherit (pkgs) stdenv;

in stdenv.mkDerivation rec {
  name = "nixops-personal";
  version = "0.1";

  src = "./";

  buildInputs = [
    pkgs.packet
    (if true then pkgs.nixops else (import ./nixops/release.nix {}).build.x86_64-linux)
    pkgs.jq
  ];

  shellHook = ''
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export NIXOS_EXTRA_MODULE_PATH=${builtins.toString ./.}/modules/default.nix
    export NIXOPS_DEPLOYMENT="personal"
    export HISTFILE="${builtins.toString ./.}/.bash_hist"
  '';
}
