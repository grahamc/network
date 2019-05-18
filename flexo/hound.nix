{ pkgs, ... }: {
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;

    logError = "syslog:server=unix:/dev/log";

    appendHttpConfig = ''
      log_format combined_host '$host $remote_addr - $remote_user [$time_local] '
                     '"$request" $status $bytes_sent '
                     '"$http_referer" "$http_user_agent" "$gzip_ratio"';

      access_log syslog:server=unix:/dev/log combined_host;
    '';

    virtualHosts."search.nix.gsc.io" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/open_search.xml".alias = "${./hound/open-search.xml}";
        "/".proxyPass = "http://127.0.0.1:6080/";
      };
    };
  };

  services.hound = {
    enable = true;
    listen = "127.0.0.1:6080";
    config = builtins.readFile ./hound/hound.json;
    package = pkgs.hound.overrideAttrs (x: {
      patches = [
        ./hound/0001-Fail-to-start-if-any-repos-fail-to-index.patch
        ./hound/0002-Custom-branch-specifier-PR-275.patch
        ./hound/0003-PR-275-p1-Replace-master-in-the-default-base-URL-with-a-rev.patch
      ];
    });
  };

  systemd.services.hound.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
}
