{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.standard;
  secrets = import ../../secrets.nix;
in {
  options = {
    services.standard = {
      s3_bucket = mkOption {
        type = types.string;
        default = "prsnixgscio";
      };

      public_key_file = mkOption {
        type = types.path;
        default = secrets.cache_public_key_file;
      };

    };
  };

  config = {
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
