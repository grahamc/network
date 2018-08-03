{ secrets }:
{ config, lib, pkgs, ... }:
let
  internalInterfaces = [ "enp4s0" ];
in
{
  imports = [
    ./hardware.nix
  ];

  nix = {
      gc = {
        automatic = true;
        dates = "8:44";

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
        config.services.netatalk.port
        5353 # avahi

        # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
        3005 8324 32469 # TCP, 32400 is allowed on all interfaces
        1900 5353 32410 32412 32413 32414 # UDP


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
    package = pkgs.plex.overrideAttrs (x: let
        # see https://www.plex.tv/media-server-downloads/
        version = "1.13.4.5271-200287a06";
        sha1 = "0404340d1d8b929a04bc83d7d43523fc3232a5ac";
      in {
        name = "plex-${version}";
        src = pkgs.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server/${version}/plexmediaserver-${version}.x86_64.rpm";
          inherit sha1;
        };
      }
    );
  };

  services.buildkite-agent = {
    enable = true;
    tokenPath = "/run/keys/buildkite-token";
    openssh.privateKeyPath = "/run/keys/buildkite-ssh-private-key";
    openssh.publicKeyPath = "/run/keys/buildkite-ssh-public-key";
    runtimePackages = [ pkgs.gitAndTools.git-crypt pkgs.nix pkgs.bash ];
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

}
