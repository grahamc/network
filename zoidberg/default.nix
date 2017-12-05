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
    ./gcofborg.nix
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
    fail2ban = {
      enable = true;
    };

    mysql = {
      enable = true;
      package = pkgs.mysql55;
    };

    hound = {
      enable = true;
      listen = "127.0.0.1:6080";
      config = builtins.readFile ./hound/hound.json;
      package = pkgs.hound.overrideAttrs (x: {
        patches = [
          ./hound/0001-Fail-to-start-if-any-repos-fail-to-index.patch
        ];
      });
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

        "nix.gsc.io" = defaultVhostCfg // {
          root = ./nix/webroot;
          enableACME = true;
          forceSSL = true;
          locations."/".extraConfig = ''
            autoindex on;
          '';
        };

        "webhook.nix.gsc.io" = defaultVhostCfg // (let
          src  = import ./gcofborgpkg.nix;
        in {
          root = "${src.ofborg.php}/web";
          enableACME = true;
          forceSSL = true;

          extraConfig = ''
            rewrite  ^/(\d+)$ index.php?n=$1 last;
          '';

          locations = (vhostPHPLocations pkgs "${src.ofborg.php}/web");
        });

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

  systemd = {
    services = {
      hound = {
        serviceConfig = {
          Restart = "always";
          RestartSec = 5;
        };
      };

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
        '';
      };
    };
  };

  users = {
    extraUsers = {
    };
  };
}
