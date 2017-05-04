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
      };
    };
  };

  deployment = {
    targetHost = "147.75.97.237";
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

    bonds = {
      bond0 = {
        driverOptions.mode = "balance-tlb";
        interfaces = [
          "enp0s20f0" "enp0s20f1"
        ];
      };
    };

    interfaces = {
      bond0 = {
        useDHCP = true;

        ip4 = [
          {
            address = "147.75.97.237";
            prefixLength = 31;
          }
          {
            address = "10.100.5.1";
            prefixLength = 31;
          }
        ];

        ip6 = [
          {
            address = "2604:1380:0:d00::1";
            prefixLength = 127;
          }
        ];
      };
    };
  };
}
