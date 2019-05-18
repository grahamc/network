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
    ./wireguard.nix
    ./everyaws.nix
    (import ./packet-type-0.nix { inherit secrets; })
    ./ircbot.nix
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
              curl
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

            script = let
              src = pkgs.runCommand "queue-monitor-src" {}
              ''
                mkdir queue-monitor
                cp ${./nix-channel-monitor/changes.sh} ./changes.sh
                sed -i 's#AMQPAPI#${secrets.rabbitmq.nixchannelmonitor}#' ./changes.sh
                cp -r ./changes.sh $out
              '';
          in ''
              ${src} /var/lib/nix-channel-monitor/git /var/lib/nix-channel-monitor/monitor/public
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

    {
      users.users.r13y = {
        description = "Reproducibility";
        home = "/var/lib/r13y";
        createHome = true;
        group = "r13y";
        uid = 404;
        openssh.authorizedKeys.keyFiles = [ secrets.r13y.public ];
        shell = pkgs.bash;
      };
      users.groups.r13y.gid = 404;
    }

  ];

  networking = {
    firewall = {
      allowedTCPPorts = [ 80 443 587 ];
    };
  };

  environment = {
    systemPackages = with pkgs; [
      git # for kylechristensen
      (weechat.override {
        configure = { availablePlugins, ... }: {
          plugins = [
            (availablePlugins.python.withPackages (ps: [
              (ps.potr.overridePythonAttrs (oldAttrs:
                {
                  propagatedBuildInputs = [
                    (ps.buildPythonPackage rec {
                      name = "pycrypto-${version}";
                      version = "2.6.1";

                      src = pkgs.fetchurl {
                        url = "mirror://pypi/p/pycrypto/${name}.tar.gz";
                        sha256 = "0g0ayql5b9mkjam8hym6zyg6bv77lbh66rv1fyvgqb17kfc1xkpj";
                      };

                      patches = pkgs.stdenv.lib.singleton (pkgs.fetchpatch {
                        name = "CVE-2013-7459.patch";
                        url = "https://anonscm.debian.org/cgit/collab-maint/python-crypto.git"
                          + "/plain/debian/patches/CVE-2013-7459.patch?h=debian/2.6.1-7";
                        sha256 = "01r7aghnchc1bpxgdv58qyi2085gh34bxini973xhy3ks7fq3ir9";
                      });

                      buildInputs = [ pkgs.gmp ];

                      preConfigure = ''
                        sed -i 's,/usr/include,/no-such-dir,' configure
                        sed -i "s!,'/usr/include/'!!" setup.py
                      '';
                    })
                  ];
                }
              ))
            ]))
          ];
        };
      })
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

        "r13y.com" = defaultVhostCfg // {
          root = "/var/lib/nginx/r13y/r13y.com";
          enableACME = true;
          forceSSL = true;
        };

        "www.r13y.com" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          globalRedirect = "r13y.com";
        };


        "monitoring.nix.gsc.io" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          locations = {
            "/".proxyPass = "http://127.0.0.1:3000/";
          };
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

        "ihavenoideawhatimdoing.dog" = defaultVhostCfg // rec {
          enableACME = true;
          forceSSL = true;
          root = pkgs.callPackage ../../ihavenoideawhatimdoing.dog {};
          locations = (vhostPHPLocations pkgs root);
        };

        "grahamc.com" = defaultVhostCfg // rec {
          enableACME = true;
          forceSSL = true;
          root = pkgs.callPackage ../../grahamc.github.com {};
          locations."/" = {
            index = "index.html index.xml";
            tryFiles = "$uri $uri/ $uri.html $uri.xml =404";
          };
        };

        "docbook.rocks" = defaultVhostCfg // rec {
          enableACME = true;
          forceSSL = true;
          root = pkgs.callPackage ../../docbook.rocks {};
          locations."/" = {
            index = "index.html index.xml";
            tryFiles = "$uri $uri/ $uri.html $uri.xml =404";
          };

          extraConfig = ''
            error_log syslog:server=unix:/dev/log;
            access_log syslog:server=unix:/dev/log combined_host;

            etag off;
            add_header ETag ${builtins.replaceStrings ["/nix/store/"] [""] (builtins.toString root)};
            add_header Last-Modified "";
          '';
        };


        "www.docbook.rocks" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          globalRedirect = "docbook.rocks";
        };

        "www.grahamc.com" = defaultVhostCfg // {
          enableACME = true;
          forceSSL = true;
          globalRedirect = "grahamc.com";
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

          mkdir -p /var/lib/nginx/grahamc/r13y.com
          chown nginx:nginx /var/lib/nginx/grahamc/
          chown grahamc:users /var/lib/nginx/grahamc/r13y.com
          if ! test -L /home/grahamc/r13y.com; then
            ln -s /var/lib/nginx/grahamc/r13y.com /home/grahamc/r13y.com
          fi


          mkdir -p /var/lib/nginx/r13y/r13y.com
          chown nginx:nginx /var/lib/nginx/r13y/
          chown r13y:users /var/lib/nginx/r13y/r13y.com
          if ! test -L /var/lib/r13y/r13y.com; then
            ln -s /var/lib/nginx/r13y/r13y.com /var/lib/r13y/r13y.com
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
