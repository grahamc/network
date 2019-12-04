{ secrets }:
{ config, lib, pkgs, ... }:
let
  prometheus-surfboard-exporter = pkgs.callPackage ({ stdenv, buildGoPackage, fetchFromGitHub }:
    buildGoPackage rec {
      name = "surfboard_exporter-${version}";
      version = "2.0.0";

      goPackagePath = "github.com/ipstatic/surfboard_exporter";

      src = fetchFromGitHub {
        rev = version;
        owner = "ipstatic";
        repo = "surfboard_exporter";
        sha256 = "11qms26648nwlwslnaflinxcr5rnp55s908rm1qpnbz0jnxf5ipw";
      };

      meta = with stdenv.lib; {
        description = "Arris Surfboard signal metrics exporter";
        homepage = https://github.com/ipstatic/surfboard_exporter;
        license = licenses.mit;
        maintainers = with maintainers; [ disassembler ];
        platforms = platforms.unix;
      };
    }) {};

  externalInterface = "enp1s0";

vlans = {
  nougat = {
    id = 1; # this was commented, and set to 40
    name = "enp2s0";
    interface = "enp2s0";
    firstoctets = "10.5.3";
    subnet = 24;
  };

  admin-wifi = {
    id = 10;
    name = "adminwifi";
    interface = "enp3s0";
    firstoctets = "10.5.5"; # TODO: Validate ends in no dot
    subnet = 24;
  };

  nougat-wifi = {
    id = 41;
    name = "nougatwifi";
    interface = "enp3s0";
    firstoctets = "10.5.4"; # TODO: Validate ends in no dot
    subnet = 24;
  };

  ofborg = {
    id = 50;
    name = "ofborg";
    interface = "enp3s0";
    firstoctets = "10.88.88";
    subnet = 24;
  };

  target = {
    id = 54;
    name = "target";
    interface = "enp3s0";
    firstoctets = "10.54.54";
    subnet = 24;
  };

  hue = {
    id = 80;
    name = "hue";
    interface = "enp3s0";
    firstoctets = "10.80.80";
    subnet = 24;
  };

  roku = {
    id = 81;
    name = "roku";
    interface = "enp3s0";
    firstoctets = "10.80.81";
    subnet = 24;
  };
};

in {
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;

    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "net.ipv6.conf.${externalInterface}.accept_ra" = 2;
  };

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

    refusePortOnInterfaceHighPriority = port: interface:
      ''
        ip46tables -I nixos-fw -i ${interface} -p tcp \
          --dport ${toString port} -j nixos-fw-log-refuse
        ip46tables -I nixos-fw -i ${interface} -p udp \
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
        [vlans.nougat.name vlans.nougat-wifi.name vlans.admin-wifi.name];

    publiclyRejectPort = port:
      refusePortOnInterface port externalInterface;

    allowPortOnlyPrivately = port:
      ''
        ${privatelyAcceptPort port}
        ${publiclyRejectPort port}
      '';

    # IPv6 flat forwarding. For ipv4, see nat.forwardPorts
    forwardPortToHost = port: interface: proto: host:
      ''
        ip6tables -A FORWARD -i ${interface} \
          -p ${proto} -d ${host} \
          --dport ${toString port} -j ACCEPT
      '';
in lib.concatStrings [
    # (refusePortOnInterfaceHighPriority 22 vlans.target.name)
    (lib.concatMapStrings allowPortOnlyPrivately
    [

        53 # knot dns resolver
        80 # nginx for tftp handoff
        67 # DHCP?
        68 # DHCP?
        69 # tftp
        config.services.netatalk.port
        5353 # avahi

        9100 # node exporter
        9130 # unifi exporter
        9239 # surfboard exporter

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
        3005 8324 32469 # TCP, 32400 is allowed on all interfaces
        1900 5353 32410 32412 32413 32414 # UDP
      ])
    (lib.concatMapStrings dropPortNoLog
      [
        23   # Common from public internet
        143  # Common from public internet
        139  # From RT AP
        515  # From RT AP
        # 9100 # From RT AP
      ])
      (let
        crossblock = builtins.attrNames vlans;
        allowDirectional = [
          ["nougat"      "nougat-wifi"]
          ["nougat-wifi" "nougat"]
          ["nougat-wifi" "ofborg"]
          ["roku" "nougat"]
          ["nougat" "roku"]
        ];
      in lib.concatStrings (lib.flatten (builtins.map
        (src:
          builtins.map
            (dest:
            if builtins.elem [src dest] allowDirectional then ""
              else if src == dest then ""
              else "ip46tables -I FORWARD -i ${vlans."${src}".name} -o ${vlans."${dest}".name} -j DROP\n"
            )
            crossblock
        )
        crossblock)))
      ''
        # allow from trusted interfaces
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.admin-wifi.name} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.nougat-wifi.name} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.nougat.name} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.ofborg.name} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.target.name} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${vlans.roku.name} -o ${externalInterface} -j ACCEPT

        # allow traffic with existing state
        ip46tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        # block forwarding from external interface
        ip6tables -A FORWARD -i ${externalInterface} -j DROP
      ''
  ];
  networking.firewall.allowedTCPPorts = [
    32400 # plex
    2200 # turner's SSH port
  ];
  networking.firewall.allowedUDPPorts = [ 41741 ]; # Wireguard on ogden
  networking.firewall.allowPing = true;
  networking.interfaces."${vlans.nougat.name}" = {
    ipv4.addresses = [{
      address = "${vlans.nougat.firstoctets}.1";
      prefixLength = vlans.nougat.subnet;
    }];
  };

  networking.interfaces."${vlans.admin-wifi.name}" = {
    ipv4.addresses = [{
      address = "${vlans.admin-wifi.firstoctets}.1";
      prefixLength = vlans.admin-wifi.subnet;
    }];
  };

  networking.interfaces."${vlans.nougat-wifi.name}" = {
    ipv4.addresses = [{
      address = "${vlans.nougat-wifi.firstoctets}.1";
      prefixLength = vlans.nougat-wifi.subnet;
    }];
  };

  networking.interfaces."${vlans.ofborg.name}" = {
    ipv4.addresses = [{
      address = "${vlans.ofborg.firstoctets}.1";
      prefixLength = vlans.ofborg.subnet;
    }];
  };

  networking.interfaces."${vlans.target.name}" = {
    ipv4.addresses = [{
      address = "${vlans.target.firstoctets}.1";
      prefixLength = vlans.target.subnet;
    }];
  };

  networking.interfaces."${vlans.hue.name}" = {
    ipv4.addresses = [{
      address = "${vlans.hue.firstoctets}.1";
      prefixLength = vlans.hue.subnet;
    }];
  };

  networking.interfaces."${vlans.roku.name}" = {
    ipv4.addresses = [{
      address = "${vlans.roku.firstoctets}.1";
      prefixLength = vlans.roku.subnet;
    }];
  };

  services.kresd = {
    enable = true;
    interfaces = [ "::1" "127.0.0.1" "${vlans.nougat.firstoctets}.1" "${vlans.nougat-wifi.firstoctets}.1" ];
    extraConfig = if true then ''
      modules = {
      	'policy',   -- Block queries to local zones/bad sites
      	'stats',    -- Track internal statistics
      	'predict',  -- Prefetch expiring/frequent records
      }

      -- Smaller cache size
      cache.size = 10 * MB
    '' else ''
      modules = {
        http = {
                host = 'localhost',
                port = 8053,
                -- geoip = 'GeoLite2-City.mmdb' -- Optional, see
                -- e.g. https://dev.maxmind.com/geoip/geoip2/geolite2/
                -- and install mmdblua library
        }
      }
    '';
  };

  networking.vlans = {
    # !!! Make nougat actually a vlan
    #"${vlans.nougat.name}" = {
    #  interface = vlans.nougat.interface;
    #  id = vlans.nougat.id;
    #};

    "${vlans.admin-wifi.name}" = {
      interface = vlans.admin-wifi.interface;
      id = vlans.admin-wifi.id;
    };

    "${vlans.nougat-wifi.name}" = {
      interface = vlans.nougat-wifi.interface;
      id = vlans.nougat-wifi.id;
    };

    "${vlans.ofborg.name}" = {
      interface = vlans.ofborg.interface;
      id = vlans.ofborg.id;
    };

    "${vlans.target.name}" = {
      interface = vlans.target.interface;
      id = vlans.target.id;
    };

    "${vlans.hue.name}" = {
      interface = vlans.hue.interface;
      id = vlans.hue.id;
    };

    "${vlans.roku.name}" = {
      interface = vlans.roku.interface;
      id = vlans.roku.id;
    };

  };
  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = [
      vlans.admin-wifi.name
      vlans.nougat.name
      vlans.nougat-wifi.name
      vlans.ofborg.name
      vlans.target.name
      vlans.hue.name
      vlans.roku.name
    ];
    internalIPs = [
      "${vlans.admin-wifi.firstoctets}.0/${toString vlans.admin-wifi.subnet}"
      "${vlans.nougat.firstoctets}.0/${toString vlans.nougat.subnet}"
      "${vlans.nougat-wifi.firstoctets}.0/${toString vlans.nougat-wifi.subnet}"
      "${vlans.ofborg.firstoctets}.0/${toString vlans.ofborg.subnet}"
      "${vlans.target.firstoctets}.0/${toString vlans.target.subnet}"
      "${vlans.hue.firstoctets}.0/${toString vlans.hue.subnet}"
      "${vlans.roku.firstoctets}.0/${toString vlans.roku.subnet}"
    ];

    forwardPorts = [
      { destination = "10.5.3.105:32400"; proto = "tcp"; sourcePort = 32400; }
      { destination = "10.5.3.105:22"; proto = "tcp"; sourcePort = 22; }
      { destination = "10.5.3.105:41741"; proto = "udp"; sourcePort = 41741; }
      { destination = "10.5.4.50:22"; proto = "tcp"; sourcePort = 2200; } # turner
    ];
  };

  services.radvd = {
    enable = false; # ipv6 is just ... broken, man.
    config = ''
      interface ${vlans.nougat.name}
      {
         AdvSendAdvert on;
         prefix ::/64
         {
         };
      };

      interface ${vlans.nougat-wifi.name}
      {
         AdvSendAdvert on;
         prefix ::/64
         {
         };
      };
    '';
  };

  networking.dhcpcd.extraConfig = ''
    xidhwaddr
    noipv6rs
    debug
    interface enp1s0
      #ipv6rs
      iaid 10
      ia_na 1
      ia_pd 2/::/56 enp2s0/2 nougatwifi/3
  '';

  services.dhcpd4 = {
    enable = true;
    interfaces = [
      vlans.admin-wifi.name
      vlans.nougat.name
      vlans.nougat-wifi.name
      vlans.ofborg.name
      vlans.target.name
      vlans.hue.name
      vlans.roku.name
    ];
    extraConfig = ''
      max-lease-time 604800;
      default-lease-time 604800;

      subnet ${vlans.nougat.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.nougat.firstoctets}.255;
        option routers ${vlans.nougat.firstoctets}.1;
        option domain-name-servers ${vlans.nougat.firstoctets}.1;
        # option domain-name "${secrets.router.domainname}";
        if exists user-class and option user-class = "iPXE" {
          filename "http://${vlans.nougat.firstoctets}.1/nixos/netboot.ipxe";
        } else {
          filename "ipxe/undionly.kpxe";
        }

        next-server ${vlans.nougat.firstoctets}.1;
        range ${vlans.nougat.firstoctets}.100 ${vlans.nougat.firstoctets}.200;
      }

      subnet ${vlans.admin-wifi.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.admin-wifi.firstoctets}.255;
        option routers ${vlans.admin-wifi.firstoctets}.1;
        option domain-name-servers ${vlans.admin-wifi.firstoctets}.1;
        range ${vlans.admin-wifi.firstoctets}.100 ${vlans.admin-wifi.firstoctets}.200;
      }


      subnet ${vlans.nougat-wifi.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.nougat-wifi.firstoctets}.255;
        option routers ${vlans.nougat-wifi.firstoctets}.1;
        option domain-name-servers ${vlans.nougat-wifi.firstoctets}.1;
        range ${vlans.nougat-wifi.firstoctets}.100 ${vlans.nougat-wifi.firstoctets}.200;

        group {
          host turner  { # garage door opener lol
            hardware ethernet b8:27:eb:9b:4a:23;
            fixed-address 10.5.4.50;
          }
        }
      }

      subnet ${vlans.ofborg.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.ofborg.firstoctets}.255;
        option routers ${vlans.ofborg.firstoctets}.1;
        option domain-name-servers 8.8.8.8;
        range ${vlans.ofborg.firstoctets}.100 ${vlans.ofborg.firstoctets}.200;
      }

      subnet ${vlans.target.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.target.firstoctets}.255;
        option routers ${vlans.target.firstoctets}.1;
        option domain-name-servers 8.8.8.8;
        range ${vlans.target.firstoctets}.100 ${vlans.target.firstoctets}.200;
      }

      subnet ${vlans.hue.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.hue.firstoctets}.255;
        option routers ${vlans.hue.firstoctets}.1;
        range ${vlans.hue.firstoctets}.100 ${vlans.hue.firstoctets}.200;
      }

      subnet ${vlans.roku.firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${vlans.roku.firstoctets}.255;
        option routers ${vlans.roku.firstoctets}.1;
        range ${vlans.roku.firstoctets}.100 ${vlans.roku.firstoctets}.200;
      }
    '';
  };

  services.unifi = {
    enable = true;
    openPorts = false;
    # unifiPackage = pkgs.unifiStable;
  };

  services.prometheus.exporters.unifi = {
    enable = true;
    inherit (secrets.unifi_exporter_opts) unifiAddress unifiInsecure
      unifiUsername unifiPassword;
  };


  systemd.services.prometheus-surfboard-exporter = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Restart = "always";
      PrivateTmp =  true;
      WorkingDirectory = "/tmp";
      ExecStart = ''
        ${prometheus-surfboard-exporter}/bin/surfboard_exporter \
          --web.listen-address 0.0.0.0:9239 \
          --modem-address 192.168.100.1 \
          --timeout 15s
      '';
    };
  };

  services.avahi.enable = true;

  systemd.services.forward-hairpin-2200-to-turner-22 = {
    wantedBy = [ "multi-user.target" ];
    script = ''
      set -euxo pipefail
      exec ${pkgs.socat}/bin/socat TCP-LISTEN:2200,fork TCP:10.5.4.50:22
    '';
  };

}
