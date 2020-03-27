{ secrets }:
{ pkgs, ... }:
{
  deployment.keys.dns-update-secrets = {
    text = ''
      AWS_ACCESS_KEY_ID="${secrets.awsdns.key}"
      AWS_SECRET_ACCESS_KEY="${secrets.awsdns.secret}"
      ZONEID="${secrets.awsdns.zone}"
      RECORDSET="${secrets.awsdns.record}"
    '';
    user = "dns-update";
    group = "keys";
    permissions = "0600";
  };

  users.users.dns-update.uid = 405;

  systemd.services.dns-update = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
    after  = [ "network.target" ];
    startAt = "*:0/5";
    serviceConfig = {
      User = "dns-update";
      Group = "keys";
      EnvironmentFile = "/run/keys/dns-update-secrets";
      ProtectHome = true;
      PrivateTmp = true;
    };
    path = with pkgs; [ awscli dnsutils bash nettools iproute jq curl ];
    script = "${./dns.sh}";
  };
}
