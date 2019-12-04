{ lib , ... }: {

  services.openssh.enable = true;

  boot.loader.grub.devices = [ "/dev/sda" ];
    boot.loader.grub.extraConfig = ''
    serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
    terminal_output serial console
    terminal_input serial console
  '';

  networking.hostId = "ffa10674";

  nixpkgs.config.allowUnfree = true;

  boot.initrd.availableKernelModules = [
    "ehci_pci" "ahci" "usbhid" "sd_mod"
  ];

  boot.kernelModules = [ "dm_multipath" "dm_round_robin" "ipmi_watchdog" "kvm-intel" ];
  boot.kernelParams =  [ "console=ttyS1,115200n8" ];
  boot.extraModulePackages = [ ];

  networking.hostName = "flexo.gsc.io";
  networking.domain = "gsc.io";
  networking.dhcpcd.enable = false;
  networking.defaultGateway = {
    address =  "147.75.105.136";
    interface = "bond0";
  };
  networking.defaultGateway6 = {
    address = "2604:1380:0:d00::2";
    interface = "bond0";
  };
  networking.nameservers = [
    "147.75.207.207"
    "147.75.207.208"
  ];

  networking.bonds.bond0 = {
    driverOptions = {
      mode = "balance-tlb";
      xmit_hash_policy = "layer3+4";
      downdelay = "200";
      updelay = "200";
      miimon = "100";
    };

    interfaces = [
      "enp0s20f0" "enp0s20f1"
    ];
  };
  networking.interfaces.bond0 = {
    useDHCP = false;

    ipv4 = {
      routes = [
        {
          address = "10.0.0.0";
          prefixLength = 8;
          via = "10.100.5.2";
        }
      ];
      addresses = [
        {
          address = "147.75.105.137";
          prefixLength = 31;
        }
        {
          address = "10.100.5.3";
          prefixLength = 31;
        }
      ];
    };

    ipv6 = {
      addresses = [
        {
          address = "2604:1380:0:d00::3";
          prefixLength = 127;
        }
      ];
    };
  };
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  system.stateVersion = "19.03"; # Did you read the comment?


  fileSystems."/" = {
    device = "npool/root";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "npool/home";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "npool/nix";
    fsType = "zfs";
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/7ea56025-7807-4241-831c-87972e180778"; }
  ];

  nix.maxJobs = lib.mkDefault 4;
}
