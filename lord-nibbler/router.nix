{ secrets }:
{ config, lib, ... }:
let
  externalInterface = "enp1s0";
  internalWiredInterface = "enp2s0";


  internalInterfaces = [ internalWiredInterface ];

  firstoctets = "10.5.3";

  internalSegregatedInterface = "enp3s0";
  segregatedFirstoctets = "10.99.99";
in {
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;

    "net.ipv6.conf.all.forwarding" = true;
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

    allowPortMonitoring = port:
      ''
        iptables -A nixos-fw -p tcp -s 147.75.97.237 \
          --dport ${toString port} -j nixos-fw-accept

        ip6tables -A nixos-fw -p tcp -s 2604:1380:0:d00::1 \
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

    # IPv6 flat forwarding. For ipv4, see nat.forwardPorts
    forwardPortToHost = port: interface: proto: host:
      ''
        ip6tables -A FORWARD -i ${interface} \
          -p ${proto} -d ${host} \
          --dport ${toString port} -j ACCEPT
      '';
in lib.concatStrings [
    (refusePortOnInterfaceHighPriority 22 internalSegregatedInterface)
    (lib.concatMapStrings allowPortMonitoring
      [
        9100 # Prometheus NodeExporter
      ])
    #(forwardPortToHost 9100 externalInterface "tcp"
    #  "2604:6000:e6c2:f501:8e89:a5ff:fe10:53f0/128") # ogden
    ''
      ip6tables -A FORWARD -i ${externalInterface} -o ${internalWiredInterface} -p tcp --dport 9100 -j ACCEPT
    ''
    (lib.concatMapStrings allowPortOnlyPrivately
    [
        53 # knot dns resolver
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
      ''
        # Don't allow segregated nodes to talk to the squishy nodes
        ip46tables -I FORWARD -i ${internalWiredInterface} -o ${internalSegregatedInterface} -j DROP
        ip46tables -I FORWARD -i ${internalSegregatedInterface} -o ${internalWiredInterface} -j DROP

        # allow from trusted interfaces
        ip46tables -A FORWARD -m state --state NEW -i ${internalWiredInterface} -o ${externalInterface} -j ACCEPT
        ip46tables -A FORWARD -m state --state NEW -i ${internalSegregatedInterface} -o ${externalInterface} -j ACCEPT
        # allow traffic with existing state
        ip46tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        # block forwarding from external interface
        ip6tables -A FORWARD -i ${externalInterface} -j DROP
      ''
  ];
  networking.firewall.allowedTCPPorts = [ 32400 ]; # Plex
  networking.firewall.allowPing = true;
  networking.interfaces."${internalWiredInterface}" = {
    ipv4.addresses = [{
      address = "${firstoctets}.1";
      prefixLength = 24;
    }];
  };
  networking.interfaces."${internalSegregatedInterface}" = {
    ipv4.addresses = [{
      address = "${segregatedFirstoctets}.1";
      prefixLength = 24;
    }];
  };

  services.kresd = {
    enable = true;
    interfaces = [ "::1" "127.0.0.1" "${firstoctets}.1" ];
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

  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = internalInterfaces ++ [internalSegregatedInterface];
    internalIPs = [
      "${firstoctets}.0/24" "${segregatedFirstoctets}.0/24"
    ];

    forwardPorts = [
      { destination = "10.5.3.105:32400"; proto = "tcp"; sourcePort = 32400; }
      { destination = "10.5.3.105:22"; proto = "tcp"; sourcePort = 22; }
    ];
  };

  services.radvd = {
    enable = true;
    config = ''
      interface ${internalWiredInterface}
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
    interface ${externalInterface}
    ia_na 1
    ia_pd 2/::/56 ${internalWiredInterface}/1
  '';


  services.dhcpd4 = {
    enable = true;
    interfaces = internalInterfaces ++ [internalSegregatedInterface];
    extraConfig = ''
      subnet ${firstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${firstoctets}.255;
        option routers ${firstoctets}.1;
        option domain-name-servers ${firstoctets}.1;
        option domain-name "${secrets.router.domainname}";
        if exists user-class and option user-class = "iPXE" {
          filename "http://${firstoctets}.1/nixos/netboot.ipxe";
        } else {
          filename "ipxe/undionly.kpxe";
        }

        next-server ${firstoctets}.1;
        range ${firstoctets}.100 ${firstoctets}.200;

        host ndndx-wifi {
          hardware ethernet 78:31:c1:bc:8a:dc;
          fixed-address ${firstoctets}.61;
        }

        host ndndx-wired {
          hardware ethernet 98:5a:eb:d5:cc:50;
          fixed-address ${firstoctets}.51;
        }

        host odroid-c2-wired-bootp {
          hardware ethernet 00:1e:06:33:1c:28;
          fixed-address ${firstoctets}.11;
        }
      }

      subnet ${segregatedFirstoctets}.0 netmask 255.255.255.0 {
        option subnet-mask 255.255.255.0;
        option broadcast-address ${segregatedFirstoctets}.255;
        option routers ${segregatedFirstoctets}.1;
        option domain-name-servers 8.8.8.8;
        range ${segregatedFirstoctets}.100 ${segregatedFirstoctets}.200;
      }
    '';
  };

  services.unifi = {
    enable = true;
    openPorts = false;
  };

}
