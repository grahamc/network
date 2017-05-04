{ secrets }:
let
  defaultVhostCfg = {
    enableACME = false;
    forceSSL = false;

    extraConfig = ''
      error_log syslog:server=unix:/dev/log;
      access_log syslog:server=unix:/dev/log combined_host;
    '';# combined_host;
  };
  vhostPHPLocations = pkgs: root: {
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

in { pkgs, ... }: {
  imports = [
    ./packet-type-0.nix
  ];

  networking = {
    firewall = {
      allowedTCPPorts = [ 80 443 ];
    };
  };

  environment = {
    systemPackages = with pkgs; [
      ledger # for matthewturland.com
      weechat
      screen
      tmux
    ];
  };

  services = {
    bitlbee = {
      enable = true;
      authMode = "Closed";
      extraSettings = ''
        AuthPassword = ${secrets.bitlbee.authPassword}
        OperPassword = ${secrets.bitlbee.operPassword}
      '';
    };

    mysql = {
      enable = true;
      package = pkgs.mysql55;
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      commonHttpConfig = ''
        log_format combined_host '$host $remote_addr - $remote_user [$time_local] '
                     '"$request" $status $bytes_sent '
                     '"$http_referer" "$http_user_agent" "$gzip_ratio"';
      '';

      virtualHosts = let
        rootname = "next.gsc.io";
      in {
        "zoidberg.gsc.io" = defaultVhostCfg // {
          default = true;
        };

        "zoidberg-ssl.gsc.io" = defaultVhostCfg // {
          default = true;
          enableACME = true;
          enableSSL = true;
        };

        "${rootname}" = defaultVhostCfg // {
          enableACME = true;
          # forceSSL = true;
          root = "/var/lib/nginx/grahamc/gsc.io/public";
        };
        "www.${rootname}" = defaultVhostCfg // {
          globalRedirect = rootname;
        };

        "u.gsc.io" = defaultVhostCfg // {
          root = ./url-shortener-root;
          enableACME = true;
          forceSSL = true;

          extraConfig = ''
            rewrite  ^/(\d+)$ index.php?n=$1 last;
          '';

          locations = (vhostPHPLocations pkgs ./url-shortener-root);
        };

        "matthewturland.com" = defaultVhostCfg // rec {
          enableACME = true;
          forceSSL = true;
          root = "/var/lib/nginx/mturland/matthewturland.com/public";
          locations = (vhostPHPLocations pkgs root) // {
            "~* /(?:uploads|files)/.*\.php$".extraConfig =  ''
              deny all;
            '';
          };
        };
        "www.matthewturland.com" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          globalRedirect = "matthewturland.com";
        };
      };
    };

    phpfpm.pools.main = {
      listen = "/run/php-fpm.sock";
      extraConfig = ''
        php_admin_value[error_log] = php://stderr
        php_admin_flag[log_errors] = on
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
      '';
    };
  };

  systemd = {
    services = {
      urlsdir = {
        wantedBy = [ "multi-user.target" ];
        before = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /var/lib/url-shortener
          chown -R nginx:nginx /var/lib/url-shortener

          mkdir -p /var/lib/nginx
          chown nginx:nginx /var/lib/nginx

          mkdir -p /var/lib/nginx/grahamc/gsc.io/public
          chown nginx:nginx /var/lib/nginx/grahamc/
          chown grahamc:users /var/lib/nginx/grahamc/gsc.io
          chown grahamc:users /var/lib/nginx/grahamc/gsc.io/public
          if ! test -L /home/grahamc/gsc.io; then
            ln -s /var/lib/nginx/grahamc/gsc.io /home/grahamc/gsc.io
          fi

          mkdir -p /var/lib/nginx/mturland/matthewturland.com/public
          chown nginx:nginx /var/lib/nginx/mturland/
          chown mturland:users /var/lib/nginx/mturland/matthewturland.com
          chown mturland:users /var/lib/nginx/mturland/matthewturland.com/public
          if ! test -L /home/mturland/matthewturland.com; then
            ln -s /var/lib/nginx/mturland/matthewturland.com /home/mturland/matthewturland.com
          fi

        '';
      };
    };
  };

  users = {
    extraUsers = {
      mturland = {
        isNormalUser = true;
        uid = 1001;
        createHome = true;
        home = "/home/mturland";
        openssh.authorizedKeys.keyFiles = [
          secrets.mturland.keys
        ];
      };
    };
  };
}
