{ config, pkgs, ... }:
{
  imports = [
    ./standard
    ./ofborg.nix
    ./role.nix
    ./learn/service.nix
  ];
}
