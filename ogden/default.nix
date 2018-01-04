{ secrets }:
{ config, lib, pkgs, ... }:
let
  internalInterfaces = [ "enp4s0" ];
in
{
  imports = [
    ./hardware.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

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
  ];

  services.ofborg = {
    enable = true;
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

  services.prometheus.nodeExporter.listenAddress = "[::]";

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
  networking.firewall.allowedTCPPorts = [ 9100 ];

  users = {
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
        createHome = true;
        home = "/home/kchristensen";
        openssh.authorizedKeys.keyFiles = [
          secrets.kchristensen.keys
        ];
      };
    };
  };

  # Plex
  services.plex = {
    enable = true;
    package = pkgs.plex.overrideAttrs (x: {
      src = pkgs.fetchurl {
        url = let
        version = "1.10.1.4602";
        vsnHash = "f54242b6b";

      in "https://downloads.plex.tv/plex-media-server/${version}-${vsnHash}/plexmediaserver-${version}-${vsnHash}.x86_64.rpm";
      sha256 = "0f7yh8pqjv9ib4191mg0ydlb44ls9xc1ybv10v1iy75s9w00c0vd";
      };
    });
  };
}
