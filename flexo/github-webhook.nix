{ pkgs, ... }:
let
  vhostPHPLocations = root: {
    "/" = {
      index = "index.php index.html";

      extraConfig = ''
        try_files $uri $uri/ /index.php$is_args$args;
      '';
    };

    "~ \.php$" = {
      extraConfig = ''
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME ${root}/$fastcgi_script_name;
        include ${pkgs.nginx}/conf/fastcgi_params;
      '';
    };
  };
in {
  services.nginx.enable = true;
  services.nginx.virtualHosts."webhook.nix.gsc.io" = let
    src = import ./../../ircbot/ofborg {};
  in {
    root = "${src.ofborg.php}/web";
    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      rewrite  ^/(\d+)$ index.php?n=$1 last;
    '';

    locations = (vhostPHPLocations "${src.ofborg.php}/web");
  };
}
