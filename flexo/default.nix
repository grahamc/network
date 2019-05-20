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
  };
}
