{ pkgs, config, ... }:
let
  privatekey = config.networking.wireguard.interfaces.wg0.privateKeyFile;
  publickey = "${dirOf privatekey}/public";
in {
  networking.extraHosts = ''
    10.10.2.10 petunia
    10.10.2.5  zoidberg
  '';

  networking.firewall.allowedUDPPorts = [ 51820 ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.2.25/24" ];
    privateKeyFile = "/etc/wireguard/private";
    listenPort = 51820;

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
        endpoint = "zoidberg.gsc.io:5820";
        persistentKeepalive = 25;
      }
    ];
  };

  systemd.services.wireguard-wg0-key = {
    enable = true;
    wantedBy = [ "wireguard-wg0.service" ];
    path = with pkgs; [ wireguard ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      mkdir --mode 0644 -p "${dirOf privatekey}"
      if [ ! -f "${privatekey}" ]; then
        touch "${privatekey}"
        chmod 0600 "${privatekey}"
        wg genkey > "${privatekey}"
        chmod 0400 "${privatekey}"

        touch "${publickey}"
        chmod 0600 "${publickey}"
        wg pubkey < "${privatekey}" > "${publickey}"
        chmod 0444 "${publickey}"
      fi
    '';
  };
  systemd.paths."wireguard-wg0" = {
    pathConfig = {
      PathExists = privatekey;
    };
  };
}
