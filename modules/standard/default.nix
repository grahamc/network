{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.standard;
  secrets = import ../../secrets.nix;
in {
  config = {
    nixpkgs.config.allowUnfree = true;
    services.openssh = {
      enable = true;
      passwordAuthentication = false;
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };

    users = {
      mutableUsers = false;
      users = {
        root.openssh.authorizedKeys.keyFiles = [
          secrets.root.keys
        ];

        grahamc = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "wheel" ];
          createHome = true;
          home = "/home/grahamc";
          hashedPassword = secrets.grahamc.password;
          openssh.authorizedKeys.keyFiles = [
            secrets.grahamc.keys
          ];
        };
      };
    };

    nix = {
      useSandbox = true;
    };
  };
}
