{ secrets }:
{ config, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d ${config.services.nginx.virtualHosts."netboot.gsc.io".root} 0755 netboot nginx"
  ];

  networking.firewall.allowedTCPPorts = [ 61616 ]; # nc/openssl recv

  users.users.netboot = {
    description = "Netboot";
    group = "netboot";
    uid = 406;
    openssh.authorizedKeys.keyFiles = [ secrets.aarch64.public ];
    shell = pkgs.bash;
  };
  users.groups.netboot.gid = 406;

  services.nginx.virtualHosts = {
    "netboot.gsc.io" = {
      root = "/var/lib/nginx/netboot/netboot.gsc.io";
      #enableACME = true;
      #forceSSL = true;
    };
  };
}
