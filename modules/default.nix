{ config, pkgs, ... }:
{
  imports = [
    ./standard
    ./ofborg.nix
    ./role.nix
  ];
}
