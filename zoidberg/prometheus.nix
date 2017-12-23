{ pkgs, ... }:
{
  services.prometheus = {
    enable = true;
  };
}
