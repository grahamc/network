{ secrets }:
{ config, lib, pkgs, ... }:
let
        externalInterface = "enp9s0";
        wirelessInterface = "wlp8s0";
        internalWiredInterfaces = [
#         "enp3s0"
          "enp4s0"
#         "enp6s0"
        ];

        internalInterfaces = [wirelessInterface ] ++ internalWiredInterfaces;
in
{
  imports = [
    ./hardware.nix
  ];

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = 1;
    "net.ipv4.conf.default.forwarding" = 1;
  };

  networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

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

  # List services that you want to enable:


  networking.interfaces."${wirelessInterface}" = {
    ip4 = [{
      address = "10.5.2.1";
      prefixLength = 24;
    }];
  };
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
      "10.5.2.0/24"
      "10.5.3.0/24"
    ];
  };

  services.hostapd = {
    enable = true;
    wpa = false;
    ssid = secrets.router.ssid;
    channel = 2; # Was 9, but 0 means search for best, and 36 seems best by Apple... 2 was best for 2.4ghz
    interface = wirelessInterface;
    hwMode = "g"; # was "g" but "a" for 5GHz?
    extraConfig = ''
      auth_algs=1
      wpa=2
      wpa_passphrase=${secrets.router.passphrase}
      wpa_key_mgmt=WPA-PSK
      rsn_pairwise=CCMP

      channel=0
      wpa_pairwise=TKIP CCMP
      ieee80211d=1
      ieee80211h=1
      ieee80211n=1
      ieee80211ac=1
      country_code=US
    '';
    #  channel=0
    #  ieee80211d=1
    #  country_code=US
    #  ieee80211n=1
    #  ieee80211ac=1

  };

  services.dhcpd4 = {
    enable = true;
    interfaces = internalInterfaces;
    extraConfig = ''
      option subnet-mask 255.255.255.0;
      option broadcast-address 10.5.2.255;
      option routers 10.5.2.1;
      option domain-name-servers 4.2.2.1, 4.2.2.2, 4.2.2.3;
      option domain-name "${secrets.router.domainname}";
      subnet 10.5.2.0 netmask 255.255.255.0 {
        range 10.5.2.100 10.5.2.200;
      }
      subnet 10.5.3.0 netmask 255.255.255.0 {
        range 10.5.3.100 10.5.3.200;
      }

    '';
  };
}
