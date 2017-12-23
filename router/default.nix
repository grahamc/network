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

    "net.ipv6.conf.all.forwarding" = true;
    "net.ipv6.conf.enp8s0.accept_ra" = 2;
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
        80 # nginx for tftp handoff
        69 # tftp
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

        # Plex: Found at https://github.com/NixOS/nixpkgs/blob/release-17.03/nixos/modules/services/misc/plex.nix#L156
        32400 3005 8324 32469 # TCP
        1900 5353 32410 32412 32413 32414 # UDP
      ])
    (lib.concatMapStrings dropPortNoLog
      [
        23   # Common from public internet
        143  # Common from public internet
        139  # From RT AP
        515  # From RT AP
        9100 # From RT AP
      ])
      ''
        # allow from trusted interfaces
        ip46tables -A FORWARD -m state --state NEW -i enp4s0 -o enp8s0 -j ACCEPT
        # allow traffic with existing state
        ip46tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        # block forwarding from external interface
        ip6tables -A FORWARD -i enp8s0 -j DROP
      ''
  ];
  networking.firewall.allowedTCPPorts = [ 32400 ]; # Plex

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

  services.radvd = {
    enable = true;
    config = ''
      interface enp4s0
      {
         AdvSendAdvert on;
         prefix ::/64
         {
              AdvOnLink on;
              AdvAutonomous on;
         };
      };
    '';
  };

  networking.dhcpcd.extraConfig = ''
    noipv6rs
    interface enp8s0
    ia_na 1
    ia_pd 2/::/56 enp4s0/1
  '';

  services.dhcpd4 = {
    enable = true;
    interfaces = internalInterfaces;
    extraConfig = ''
      option subnet-mask 255.255.255.0;
      option broadcast-address 10.5.3.255;
      option routers 10.5.3.1;
      option domain-name-servers 8.8.8.8;
      option domain-name "${secrets.router.domainname}";
      subnet 10.5.3.0 netmask 255.255.255.0 {
        if exists user-class and option user-class = "iPXE" {
          filename "http://10.5.3.1/nixos/netboot.ipxe";
        } else {
          filename "ipxe/undionly.kpxe";
        }

        next-server 10.5.3.1;
        range 10.5.3.100 10.5.3.200;

        host ndndx-wifi {
          hardware ethernet 78:31:c1:bc:8a:dc;
          fixed-address 10.5.3.61;
        }

        host ndndx-wired {
          hardware ethernet 98:5a:eb:d5:cc:50;
          fixed-address 10.5.3.51;
        }
      }

    '';
  };

  services.nginx = {
    enable = true;
    virtualHosts.default = {
      default = true;
      root = config.services.tftpd.path;
    };

  };

  services.tftpd = let
    netboot = (import <nixpkgs/nixos/release.nix> {}).netboot.x86_64-linux;
  in {
    enable = true;
    path = pkgs.runCommand "dhcp-pxe-root" {}
      ''
        mkdir $out
        ln -s ${netboot} $out/nixos
        ln -s ${pkgs.ipxe} $out/ipxe
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
      afp listen 10.5.3.1
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
