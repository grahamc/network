{ secrets }:
{
  boot = {
    kernel.sysctl = {
      "net.ipv4.forwarding" = 1; # BGP ^.^
    };

    initrd = {
      availableKernelModules = [
        "ehci_pci" "ahci" "usbhid" "sd_mod"
      ];
    };
    kernelModules = [ "kvm-intel" ];
    kernelParams =  [ "console=ttyS1,115200n8" ];
    extraModulePackages = [ ];
    loader = {
      grub = {
        devices = [ "/dev/sda" ];
        enable = true;
        version = 2;
        extraConfig = ''
          serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
          terminal_output serial console
          terminal_input serial console
        '';
      };
    };
  };

  deployment = {
      targetHost =  "147.75.97.237"; # "2604:1380:0:d00::1";
      # targetPort = 443;
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };

  hardware = {
    enableAllFirmware = true;
  };

  nix = {
    maxJobs = 4;
  };

  services.openssh.enable = true;
  services.bird = {
    enable = true;
    config = ''
      filter packetdns {
        # IPs to announce (the elastic ip in our case)
        # Doesn't have to be /32. Can be lower
        if net = 147.75.96.102/32 then accept;
      }

      # your (Private) bond0 IP below here
      router id 10.100.5.1;
      protocol direct {
        interface "lo"; # Restrict network interfaces it works with
      }
      protocol kernel {
        # learn; # Learn all alien routes from the kernel
        persist; # Don't remove routes on bird shutdown
        scan time 20; # Scan kernel routing table every 20 seconds
        import all; # Default is import all
        export all; # Default is export none
        # kernel table 5; # Kernel table to synchronize with (default: main)
      }

      # This pseudo-protocol watches all interface up/down events.
      protocol device {
        scan time 10; # Scan interfaces every 10 seconds
      }

      # your default gateway IP below here
      protocol bgp {
        export filter packetdns;
        local as 65000;
        neighbor 10.100.5.0 as 65530;
        password "${secrets.zoidberg_bgp_password}";
      }
    '';
  };

  networking = {
    hostId = "7a13df42";
    hostName = "zoidberg";
    dhcpcd.enable = false;

    nameservers = [ "4.2.2.1" "4.2.2.2" "2001:4860:4860::8888" ];

    bonds = {
      bond0 = {
        driverOptions.mode = "balance-tlb";
        interfaces = [
          "enp0s20f0" "enp0s20f1"
        ];
      };
    };

    defaultGateway = {
        address = "147.75.97.236";
        interface = "bond0";
    };

    defaultGateway6 = {
        address = "2604:1380:0:d00::";
        interface = "bond0";
    };

    interfaces = {
      lo = {
        useDHCP = false;

        ipv4.addresses = [
          {
            # BGP ^.^
            address = "147.75.96.102";
            prefixLength = 32;
          }
        ];
      };
      bond0 = {
        useDHCP = true;

        ipv4 = {
          routes = [
            {
              address = "10.0.0.0";
              prefixLength = 8;
              via = "10.100.5.0";
            }
          ];
          addresses = [
            {
              address = "147.75.97.237";
              prefixLength = 31;
            }
            {
              address = "10.100.5.1";
              prefixLength = 31;
            }
          ];
        };

        ipv6 = {
          addresses = [
            {
              address = "2604:1380:0:d00::1";
              prefixLength = 127;
            }
          ];
        };
      };
    };
  };
}
