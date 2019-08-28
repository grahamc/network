{ config, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d ${config.services.nginx.virtualHosts."gsc.io".root} 0755 grahamc nginx"
    "L ${config.users.users.grahamc.home}/gsc.io - - - - ${config.services.nginx.virtualHosts."gsc.io".root}"
  ];

  services.nginx.virtualHosts = {
    "gsc.io" = {
      root = "/var/lib/nginx/grahamc/gsc.io";
      #enableACME = true;
      #forceSSL = true;
    };

    "www.gsc.io" = {
      #enableACME = true;
      #forceSSL = true;
      globalRedirect = "gsc.io";
    };
  };
}
