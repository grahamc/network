{
  boot = {
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
