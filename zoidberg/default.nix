{ secrets }:
let
  defaultVhostCfg = import ./default-vhost-config.nix;
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
    (import ./events.nix.nix { inherit secrets; })

    {
      users.users.nix-channel-monitor = {
        description = "Nix Channel Monitor";
        home = "/var/lib/nix-channel-monitor";
        createHome = true;
        group = "nix-channel-monitor";
        uid = 400;
      };
      users.groups.nix-channel-monitor.gid = 400;

      systemd = {
        services = {
          nix-channel-monitor = {
            after = [ "network.target" "network-online.target" ];
            wants = [ "network-online.target" ];
            path = with pkgs; [
              telnet
              git
              gawk
            ];

            serviceConfig = {
              User = "nix-channel-monitor";
              Group = "nix-channel-monitor";
              Type = "oneshot";
              PrivateTmp = true;
              WorkingDirectory = "/var/lib/nix-channel-monitor";
            };

            preStart = ''
              set -eux
              if [ ! -d /var/lib/nix-channel-monitor/git ]; then
                git clone https://github.com/nixos/nixpkgs-channels.git git
              fi

              mkdir -p /var/lib/nix-channel-monitor/webroot
            '';

            script = ''
              ${./nix-channel-monitor/changes.sh} /var/lib/nix-channel-monitor/git /var/lib/nix-channel-monitor/monitor/public
            '';
          };
        };

        timers = {
          run-nix-channel-monitor = {
            description = "Rerun the nix channel monitor";
            wantedBy = [ "timers.target" ];
            partOf = [ "nix-channel-monitor.service" ];
            enable = true;
            timerConfig = {
              OnCalendar = "*:0/5";
              Unit = "nix-channel-monitor.service";
              Persistent = "yes";
              AccuracySec = "1m";
              RandomizedDelaySec = "30s";
            };
          };
        };
      };
    }
  ];

  networking = {
    firewall = {
      allowedTCPPorts = [ 80 443 ];
    };
  };

  environment = {
    systemPackages = with pkgs; [
      git # for kylechristensen
      weechat
      screen
      tmux
      aspell
      aspellDicts.en
      emacs
      vim
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

    hound = {
      enable = true;
      listen = "127.0.0.1:6080";
      config = builtins.readFile ./hound/hound.json;
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

      virtualHosts = {
        "zoidberg.gsc.io" = defaultVhostCfg // {
          default = true;
        };

        #"zoidberg-ssl.gsc.io" = defaultVhostCfg // {
        #  default = true;
        #  enableACME = true;
        #  enableSSL = true;
        #};

        "search.nix.gsc.io" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          locations = {
            "/open_search.xml".alias = "${./hound/open-search.xml}";
            "/".proxyPass = "http://127.0.0.1:6080/";
          };
        };

        "channels.nix.gsc.io" = defaultVhostCfg // {
          root = "/var/lib/nginx/nix-channel-monitor/monitor/public";
          enableACME = true;
          forceSSL = true;
          locations."/".extraConfig = ''
            autoindex on;
          '';
        };

        "webhook.nix.gsc.io" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          locations."/nixos".alias = pkgs.writeTextDir "nixpkgs" "OK";
        };

        "gsc.io" = defaultVhostCfg // {
          #enableACME = true;
          #forceSSL = true;
          root = "/var/lib/nginx/grahamc/gsc.io/public";
        };

        "www.gsc.io" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          globalRedirect = "gsc.io";
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

          mkdir -p /var/lib/nginx/nix-channel-monitor/monitor/public
          chown nginx:nginx /var/lib/nginx/grahamc/
          chown nix-channel-monitor:nix-channel-monitor /var/lib/nginx/nix-channel-monitor/monitor
          if ! test -L /var/lib/nix-channel-monitor/monitor; then
            ln -s /var/lib/nginx/nix-channel-monitor/monitor /var/lib/nix-channel-monitor/monitor
          fi
          chown nix-channel-monitor:nix-channel-monitor /var/lib/nginx/nix-channel-monitor/monitor/public

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

      kylechristensen = {
        isNormalUser = true;
        uid = 1003;
        createHome = true;
        home = "/home/kylechristensen";
        openssh.authorizedKeys.keyFiles = [
          secrets.kylechristensen.keys
        ];
      };
    };
  };
}
