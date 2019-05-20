{ secrets }:
{ config, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d ${config.services.nginx.virtualHosts."r13y.com".root} 0755 r13y nginx"
  ];

  users.users.r13y = {
    description = "Reproducibility";
    group = "r13y";
    uid = 404;
    openssh.authorizedKeys.keyFiles = [ secrets.r13y.public ];
    shell = pkgs.bash;
  };
  users.groups.r13y.gid = 404;

  services.nginx.virtualHosts = {
    "r13y.com" = {
      root = "/var/lib/nginx/r13y/r13y.com";
      enableACME = true;
      forceSSL = true;
    };

    "www.r13y.com" = {
      enableACME = true;
      forceSSL = true;
      globalRedirect = "r13y.com";
    };
  };
}
