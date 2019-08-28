{ secrets }:
{
  boot.kernel.sysctl."net.ipv4.forwarding" = 1;
  networking.interfaces.lo.ipv4.addresses = [ {
    # BGP ^.^
    address = "147.75.96.102";
    prefixLength = 32;
  } ];
  services.bird = {
    enable = true;
    config = ''
      filter packetdns {
        # IPs to announce (the elastic ip in our case)
        # Doesn't have to be /32. Can be lower
        if net = 147.75.96.102/32 then accept;
      }

      # your (Private) bond0 IP below here
      router id 10.100.5.3;
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
        neighbor 10.100.5.2 as 65530;
        password "${secrets.zoidberg_bgp_password}";
      }
    '';
  };

}
