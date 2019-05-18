{ secrets }:
{ ... }:
{
  imports = [
    ./hardware.nix
    ./hound.nix
    ./grahams-websites.nix
  ];

  services.nginx = {
    logError = "syslog:server=unix:/dev/log";

    appendHttpConfig = ''
      log_format combined_host '$host $remote_addr - $remote_user [$time_local] '
                     '"$request" $status $bytes_sent '
                     '"$http_referer" "$http_user_agent" "$gzip_ratio"';

      access_log syslog:server=unix:/dev/log combined_host;
    '';
  };
}
