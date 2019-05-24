{ lib, pkgs, ... }:
let
  learn = pkgs.callPackage ./. {};
in {
  options.about = lib.mkOption {
    description = "";
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
        };

        ssh_host_key = lib.mkOption {
          type = lib.types.str;
        };

        ssh_root_key = lib.mkOption {
          type = lib.types.str;
        };

        wireguard_public_keys = lib.mkOption {
          type = (lib.types.attrsOf lib.types.str);
          default = {};
        };
      };
    }));
  };

  config = {
    systemd.services.learn = {
      description = "Intake learning data collection";
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ wireguard ];

      script = ''
        ${learn}/bin/learn | ${pkgs.moreutils}/bin/sponge /run/about.json
      '';

      serviceConfig = {
        Type = "oneshot";
      };
    };
  };
}
