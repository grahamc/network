{
  enableACME = false;
  forceSSL = false;

  extraConfig = ''
    error_log syslog:server=unix:/dev/log;
    access_log syslog:server=unix:/dev/log combined_host;
  '';# combined_host;
}
