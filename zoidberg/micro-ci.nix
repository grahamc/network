{ secrets }:
{ pkgs, config, ... }:
let
  defaultVhostCfg = import ./default-vhost-config.nix;
in {
  services.nginx.virtualHosts = {
    "ci.nix.gsc.io" = defaultVhostCfg // {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/".proxyPass = "http://127.0.0.1:8080/";
      };
    };
  };

  users = {
    users.microci = {
      description = "MicroCI";
      home = "/var/lib/microci";
      createHome = true;
      group = "microci";
      uid = 401;
    };

    groups.microci.gid = 401;
  };


  systemd.services.microci = {
    enable = true;
    after = [ "network.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "nginx.service" ];
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ git nix ];

    serviceConfig = {
      User = "microci";
      Group = "microci";
      PrivateTmp = true;
      WorkingDirectory = "/var/lib/microci";
    };

    preStart = ''
      rm -f config.dhall
      cp ${./config.dhall} ./config.dhall
    '';

    script = ''
      . /etc/profile
      ${(import ./micro-ci/ci.nix).micro-ci}/bin/micro-ci
    '';
  };
}
