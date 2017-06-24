{ secrets }:
{ config, lib, pkgs, ... }:
let
        externalInterface = "enp8s0";
        internalWiredInterfaces = [
#         "enp3s0"
          "enp4s0"
#         "enp6s0"
        ];

        internalInterfaces = [ ] ++ internalWiredInterfaces;
in
{
  imports = [
    ./hardware.nix
  ];

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;
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
  ];

  # Basically, we want to allow some ports only locally and refuse
  # them externally.
  #
  # We don't make a distinction between udp and tcp, since hopefully
  # we won't have that complex of a configuration.
  networking.firewall.extraCommands = let
    dropPortNoLog = port:
      ''
        ip46tables -A nixos-fw -p tcp \
          --dport ${toString port} -j nixos-fw-refuse
        ip46tables -A nixos-fw -p udp \
          --dport ${toString port} -j nixos-fw-refuse
      '';

    refusePortOnInterface = port: interface:
      ''
        ip46tables -A nixos-fw -i ${interface} -p tcp \
          --dport ${toString port} -j nixos-fw-log-refuse
        ip46tables -A nixos-fw -i ${interface} -p udp \
          --dport ${toString port} -j nixos-fw-log-refuse
      '';
    acceptPortOnInterface = port: interface:
      ''
        ip46tables -A nixos-fw -i ${interface} -p tcp \
          --dport ${toString port} -j nixos-fw-accept
        ip46tables -A nixos-fw -i ${interface} -p udp \
          --dport ${toString port} -j nixos-fw-accept
      '';

    privatelyAcceptPort = port:
      lib.concatMapStrings
        (interface: acceptPortOnInterface port interface)
        internalInterfaces;

    publiclyRejectPort = port:
      refusePortOnInterface port externalInterface;

    allowPortOnlyPrivately = port:
      ''
        ${privatelyAcceptPort port}
        ${publiclyRejectPort port}
      '';
  in lib.concatStrings [
    (lib.concatMapStrings allowPortOnlyPrivately
      [
        config.services.netatalk.port
        5353 # avahi

        # https://help.ubnt.com/hc/en-us/articles/204910084-UniFi-Change-Default-Ports-for-Controller-and-UAPs
        # TCP:
        6789  # Port for throughput tests
        8080  # Port for UAP to inform controller.
        8880  # Port for HTTP portal redirect, if guest portal is enabled.
        8843  # Port for HTTPS portal redirect, ditto.
        8443  # Port for HTTPS portal redirect, ditto.
        #UDP:
        3478  # UDP port used for STUN.
        10001 # UDP port used for device discovery.
      ])
    (lib.concatMapStrings dropPortNoLog
      [
        23   # Common from public internet
        143  # Common from public internet
        139  # From RT AP
        515  # From RT AP
        9100 # From RT AP
      ])
  ];

  networking.interfaces."enp4s0" = {
    ip4 = [{
      address = "10.5.3.1";
      prefixLength = 24;
    }];
  };

  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = internalInterfaces;
    internalIPs = [
      "10.5.3.0/24"
    ];
  };

  services.dhcpd4 = {
    enable = true;
    interfaces = internalInterfaces;
    extraConfig = ''
      option subnet-mask 255.255.255.0;
      option broadcast-address 10.5.3.255;
      option routers 10.5.3.1;
      option domain-name-servers 4.2.2.1, 4.2.2.2, 4.2.2.3;
      option domain-name "${secrets.router.domainname}";
      subnet 10.5.3.0 netmask 255.255.255.0 {
        range 10.5.3.100 10.5.3.200;
      }

    '';
  };

  services.unifi = {
    enable = true;
    openPorts = false;
  };

  services.netatalk = {
    enable = true;
    extraConfig = ''
      afp interfaces =  ${lib.concatStringsSep " " internalInterfaces}
      log level = default:info
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
  users = {
    extraUsers = {
      emilyc = {
        isNormalUser = true;
        uid = 1002;
        createHome = true;
        home = "/home/emilyc";
        hashedPassword = secrets.emilyc.password;
      };
    };
  };
}
