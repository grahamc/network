{ secrets }:
let

in { pkgs, ... }: {
  imports = [
    ./hardware.nix
  ];

  networking.firewall.allowedTCPPorts = [ 9100 ];

  services = {
    ofborg = {
      enable = true;
      enable_evaluator = true;
    };
  };

    nix = {
      gc = {
        automatic = true;
        dates = "8:44";

        options = let
          freedGb = 60;
        in ''--max-freed "$((${toString freedGb} * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
      };

   };

}
