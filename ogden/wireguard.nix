{ pkgs, config, ... }:
let
  privatekey = config.networking.wireguard.interfaces.wg0.privateKeyFile;
  publickey = "${dirOf privatekey}/public";
in {
  networking.firewall.allowedUDPPorts = [ 41741 ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.2.15/24" ];
    privateKeyFile = "/etc/wireguard/private";
    listenPort = 41741;

    peers = [
      {
        # petunia
        publicKey = "iRqkVDUccM1duRrG02a9IraBgR9zew6SqAclqUaLoyI=";
        allowedIPs = [ "10.10.2.10/32" ];
      }
      {
        # zoidberg
        publicKey = "BQ7+bGuKVat/I8b1s75eKlRAE3PwD9DTTbOJ4yUEAzo=";
        allowedIPs = [ "10.10.2.5/32" ];
        endpoint = "gsc.io:51820";
        persistentKeepalive = 25;
      }
      {
        # flexo
        publicKey = config.about.flexo.wireguard_public_keys.wg0;
        allowedIPs = [ "10.10.2.25/32" ];
        endpoint = "flexo.gsc.io:51820";
        persistentKeepalive = 25;
      }
      {
        # elzar
        publicKey = "/5HDPKbtNvC/KxqBrUCnPfLVme8scxLJn9Zs2quXLl0=";
        allowedIPs = ["10.10.2.50/32" ];
        persistentKeepalive = 25;
      }
    ];
  };
}
