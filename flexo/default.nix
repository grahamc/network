{ secrets }:
{ config, lib, ... }:
{
  imports = [
    ./ircbot.nix
    ./everyaws.nix
    ./periodic-reminders.nix
    ./hardware.nix
    ./hound.nix
    ./grahams-websites.nix
    (import ./rabbitmq.nix { inherit secrets; })
    ./wireguard.nix
    ./github-webhook.nix
    (import ./nix-channel-monitor { inherit secrets; })
    (import ./r13y.nix { inherit secrets; })
    (import ./aarch64-netboot.nix { inherit secrets; })
    ./irc.nix
    ./gsc.io.nix
    (import ./bgp.nix { inherit secrets; })
    ./weather.nix
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
      user = "nginx";
      group = "nginx";
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

    services.znapzend = {
      enable = true;
      autoCreation = true;
      pure = true;
      zetup.npool = {
        enable = true;
        plan = "15min=>5min,4hour=>15min,2day=>1hour,4day=>1day,3week=>1week";
        recursive = true;
        timestampFormat = "%Y-%m-%d--%H%M%SZ";
        destinations.ogden = {
          plan = "1hour=>5min,4day=>1hour,1week=>1day,1year=>1week,10year=>1month";
          host = "ogden";
          dataset = "mass/${config.networking.hostName}";
        };
      };
    };
  };
}
