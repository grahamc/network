{ pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;

    virtualHosts = {
      "grahamc.com" = {
        enableACME = true;
        forceSSL = true;
        root = pkgs.callPackage ../../grahamc.github.com {};
        locations."/" = {
          index = "index.html index.xml";
          tryFiles = "$uri $uri/ $uri.html $uri.xml =404";
        };
      };

      "docbook.rocks" = rec {
        enableACME = true;
        forceSSL = true;
        root = pkgs.callPackage ../../docbook.rocks {};
        locations."/" = {
          index = "index.html index.xml";
          tryFiles = "$uri $uri/ $uri.html $uri.xml =404";
        };

        extraConfig = ''
          etag off;
          add_header ETag ${builtins.replaceStrings ["/nix/store/"] [""] (builtins.toString root)};
          add_header Last-Modified "";
        '';
      };

      "www.docbook.rocks" = {
        enableACME = true;
        forceSSL = true;
        globalRedirect = "docbook.rocks";
      };

      "www.grahamc.com" = {
        enableACME = true;
        forceSSL = true;
        globalRedirect = "grahamc.com";
      };
    };
  };
}
