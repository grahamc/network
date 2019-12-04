{ secrets }:
{ config, lib, pkgs, ... }:
let
  internalInterfaces = [ "enp4s0" ];
  hostConfig = config;
in
{
  imports = [
    ./hardware.nix
    ./wireguard.nix
    (import ./prometheus.nix { inherit secrets; })
    ./sdr.nix
    (import ./dns.nix { inherit secrets; })
    ../../../NixOS/nixos-org-configurations/macs/host
    # possibly breaking r13y.com # (import ../../../andir/local-nix-cache/module.nix)
  ];

  macosGuest = {
    enable = true;
    network = {
      externalInterface = "enp4s0";
      sshInterface = "lo";
      interiorNetworkPrefix = "192.168.1";
    };
    guest = {
      sockets = 1;
      cores = 2;
      threads = 2;
      memoryInMegs = 4 * 1024;
      zvolName = "rpool/macos-v1";
      snapshotName = "import";
      guestConfigDir = ./mac-guest;
      ovmfCodeFile = ../../../NixOS/nixos-org-configurations/macs/dist/OVMF_CODE.fd;
      ovmfVarsFile = ../../../NixOS/nixos-org-configurations/macs/dist/OVMF_VARS-1024x768.fd;
    };
  };

  #local-nix-cache.server = {
  #  enable = true;
  #};

  systemd.tmpfiles.rules = [''
    e /tmp/nix-build-* - - - 1d -
  ''];

  nix = {
      gc = {
        automatic = true;
        dates = "8:06";

        options = let
          freedGb = 300;
        in ''--max-freed "$((${toString freedGb} * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
      };

   };

  # Select internationalisation properties.
  i18n = {
    consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "dvorak";
    defaultLocale = "en_US.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    emacs
    screen
    git # for kyle's git hosting
    borgbackup # for my backups from morbo
  ];

  services.ofborg = {
    enable = false;
    enable_evaluator = true;
    enable_builder = true;
  };


  services.netatalk = {
    enable = true;
    extraConfig = ''
      afp interfaces =  ${lib.concatStringsSep " " internalInterfaces}
      afp listen 10.5.3.105
      log level = default:debug
    '';

    volumes = {
      "emilys-time-machine" = {
        "time machine" = "yes";
        path = "/home/emilyc/timemachine/time-machine-root";
        "valid users" = "emilyc";
      };

      "grahams-time-machine" = {
        "time machine" = "yes";
        path = "/home/grahamc/timemachine/time-machine-root";
        "valid users" = "grahamc";
      };
    };
  };

  services.avahi = {
    enable = true;
    interfaces = internalInterfaces;
    nssmdns = true;

    publish = {
      enable = true;
      userServices = true;
    };
  };

  services.fail2ban = {
    enable = true;
  };

  networking.firewall.extraCommands = let
    allowPortMonitoring = port:
      ''
        iptables -A nixos-fw -p tcp -s 147.75.97.237 \
          --dport ${toString port} -j nixos-fw-accept

        ip6tables -A nixos-fw -p tcp -s 2604:1380:0:d00::1 \
          --dport ${toString port} -j nixos-fw-accept
      '';
  in lib.concatStrings [
    (lib.concatMapStrings allowPortMonitoring
      [
        # 9100 # Prometheus NodeExporter
      ])
  ];

  networking.firewall.allowedTCPPorts = [
    8083 # andir/local-nix-cache

        config.services.netatalk.port
        5353 # avahi

        # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
        3005 8324 32469 # TCP, 32400 is allowed on all interfaces
        1900 5353 32410 32412 32413 32414 # UDP

        3000 # grafana
        9090 # prometheus

    # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
    32400 3005 8324 32469
    9100 # Prometheus NodeExporter
  ];

  networking.firewall.allowedUDPPorts = [
    # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
    1900 5353 32410 32412 32413 32414 # UDP
  ];


  users = {
    groups.writemedia = {};
    extraUsers = {
      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINT2IAcpePtxrnk9XiXRRkInvvXm6X00mYFd3rpMSBNW root@Petunia"
      ];

      emilyc = {
        isNormalUser = true;
        uid = 1002;
        createHome = true;
        home = "/home/emilyc";
        hashedPassword = secrets.emilyc.password;
      };

      kchristensen = {
        isNormalUser = true;
        uid = 1003;
        extraGroups = [ "writemedia" ];
        createHome = true;
        home = "/home/kchristensen";
        openssh.authorizedKeys.keyFiles = [
          secrets.kchristensen.keys
        ];
        hashedPassword = secrets.kchristensen.password;
      };
    };
  };

  # Plex
  services.plex = {
    enable = true;
/*    package = pkgs.plex.overrideAttrs (x: let
        # see https://www.plex.tv/media-server-downloads/ for 64bit rpm
        version = "1.13.6.5339-115f087d6";
        sha1 = "7f425470387b7d6b4f31c799dc37f967cef2aae2";
      in {
        name = "plex-${version}";
        src = pkgs.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server/${version}/plexmediaserver-${version}.x86_64.rpm";
          inherit sha1;
        };
      }
    );*/
  };

  containers = lib.foldr (n: c: c // { "buildkite-builder-grahamc-${toString n}" = {
    autoStart = true;
    bindMounts.foo = {
      hostPath = "/run/keys/buildkite-token-packet";
      mountPoint = "/etc/buildkite-token-packet-bar";
    };

    bindMounts.agent-token = {
      hostPath = "/run/keys/buildkite-token-packet";
      mountPoint = "/etc/buildkite-token-packet";
    };
    bindMounts.ssh-public = {
      hostPath = "/run/keys/buildkite-ssh-public-key";
      mountPoint = "/etc/buildkite-ssh-public";
    };
    bindMounts.ssh-private = {
      hostPath = "/run/keys/buildkite-ssh-private-key";
      mountPoint = "/etc/buildkite-ssh-private";
    };
    bindMounts.r13y-ssh-private = {
      hostPath = "/run/keys/r13y-ssh-private-key";
      mountPoint = "/etc/r13y-ssh-private";
    };
    bindMounts.packet-config = {
      hostPath = "/run/keys/packet-nixos-config";
      mountPoint = "/etc/packet-nixos-config";
    };
    bindMounts.aarch64-ssh-private = {
      hostPath = "/run/keys/aarch64-ssh-private-key";
      mountPoint = "/etc/aarch64-ssh-private";
    };
    bindMounts.aarch64-build-cfg = {
      hostPath = "/run/keys/aarch64-build-cfg";
      mountPoint = "/etc/aarch64-build-cfg";
    };

    config = { pkgs, lib, ... }: {
      programs.ssh.knownHosts = [
        {
          hostNames = [ "flexo.gsc.io" "r13y.com" "147.75.105.137" ];
          publicKey = hostConfig.about.flexo.ssh_host_key;
        }
        {
          hostNames = [ "147.75.79.198" ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCo+z5d8C6SpCyvC8KAPMAcMEtd5J74tRsk+7sm2KgD";
        }
      ];
      services.openssh.enable = lib.mkForce false; # override standard module
      services.prometheus.exporters.node.enable = lib.mkForce false; # override standard module

      services.buildkite-agent = {
        meta-data = "r13y=true";
        enable = true;
        tokenPath = "/etc/buildkite-token-packet";
        openssh.privateKeyPath = "/etc/buildkite-ssh-private";
        openssh.publicKeyPath = "/etc/buildkite-ssh-public";
        runtimePackages = [ pkgs.xz pkgs.gzip pkgs.gnutar pkgs.gitAndTools.git-crypt pkgs.nix pkgs.bash ];
        hooks.environment = ''
          export PATH=$PATH:/run/wrappers/bin/
          export NIX_PATH=nixpkgs=${pkgs.path}
        '';
        #hooks.pre-command = ''
        #  sleep ${builtins.toString n} # janky packet race condition
        #'';
        extraConfig = ''git-clean-flags=-n'';
      };
    };
    };}) {} (lib.range 1 10);

  services.buildkite-agent = {
    enable = true;
    tokenPath = "/run/keys/buildkite-token";
    openssh.privateKeyPath = "/run/keys/buildkite-ssh-private-key";
    openssh.publicKeyPath = "/run/keys/buildkite-ssh-public-key";
    runtimePackages = [ pkgs.gzip pkgs.gnutar pkgs.gitAndTools.git-crypt pkgs.nix pkgs.bash ];
  };

  deployment.keys.packet-nixos-config = {
    text = builtins.readFile secrets.buildkite.packet-config;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
  deployment.keys.buildkite-token-packet = {
    text = builtins.readFile secrets.buildkite-packet.token;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };

  deployment.keys.buildkite-token = {
    text = builtins.readFile secrets.buildkite.token;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
  deployment.keys.buildkite-ssh-public-key = {
    text = builtins.readFile secrets.buildkite.openssh-public-key;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
  deployment.keys.buildkite-ssh-private-key = {
    text = builtins.readFile secrets.buildkite.openssh-private-key;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };


  deployment.keys.aarch64-build-cfg = {
    text = builtins.readFile secrets.buildkite.aarch64-build-cfg;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
  deployment.keys.aarch64-ssh-private-key = {
    text = builtins.readFile secrets.aarch64.private;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
  deployment.keys.r13y-ssh-private-key = {
    text = builtins.readFile secrets.r13y.private;
    user = config.users.extraUsers.buildkite-agent.name;
    group = "keys";
    permissions = "0600";
  };
}
