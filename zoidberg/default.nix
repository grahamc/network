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
    (import ./events.nix.nix { inherit secrets; })
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

        "nix.gsc.io" = defaultVhostCfg // {
          root = ./nix/webroot;
          enableACME = true;
          forceSSL = true;
          locations."/".extraConfig = ''
            autoindex on;
          '';
        };

        "gsc.io" = defaultVhostCfg // {
          #enableACME = true;
          #forceSSL = true;
          root = "/var/lib/nginx/grahamc/gsc.io/public";
        };

        #"ihavenoideawhatimdoing.dog" = defaultVhostCfg // rec {
        #  enableACME = true;
        #  forceSSL = true;
        #  root = pkgs.callPackage ../../ihavenoideawhatimdoing.dog {};
        #  locations = (vhostPHPLocations pkgs root);
        #};

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
        '';
      };
    };
  };

  users = {
    extraUsers = {
    };
  };
}
