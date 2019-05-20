{ secrets }:
{ lib, ... }:
{
  imports = [
    ./ircbot.nix
    ./hardware.nix
    ./hound.nix
    ./grahams-websites.nix
    (import ./rabbitmq.nix { inherit secrets; })
    ./wireguard.nix
    ./github-webhook.nix
    (import ./nix-channel-monitor { inherit secrets; })
  ];

  options.security.acme.certs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      config.email = lib.mkDefault "graham@grahamc.com";
    });
  };

  config = {
    services.nginx = {
      logError = "syslog:server=unix:/dev/log";

      appendHttpConfig = ''
        log_format combined_host '$host $remote_addr - $remote_user [$time_local] '
                     '"$request" $status $bytes_sent '
                     '"$http_referer" "$http_user_agent" "$gzip_ratio"';

        access_log syslog:server=unix:/dev/log combined_host;
      '';
    };

    services.phpfpm.pools.main = {
      listen = "/run/php-fpm.sock";
      extraConfig = ''
        listen.owner = nginx
        listen.group = nginx
        listen.mode = 0600
        user = nginx
        pm = dynamic
        pm.max_children = 75
        pm.start_servers = 10
        pm.min_spare_servers = 5
        pm.max_spare_servers = 20
        pm.max_requests = 500
        catch_workers_output = yes
      '';
    };

  };
}
