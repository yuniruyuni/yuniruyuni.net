# Management traffic uses the yunirun frontend. Agents mount only the directory
# containing this socket; the two backends expose the ingestion-only listener.
{ pkgs, ... }:
let
  configFile = pkgs.writeText "yuniview-ingest.cfg" ''
    defaults
      mode http
      timeout connect 2s
      timeout client 30s
      timeout server 30s
    frontend ingest
      bind /run/yuniview-ingest/http.sock mode 666
      http-request deny deny_status 404 unless METH_POST { path /api/agent/v1/batches }
      default_backend collectors
    backend collectors
      server blue 127.0.0.1:18271 check
      server green 127.0.0.1:18272 check
  '';
  dropin = port: {
    text = ''
      [Container]
      PublishPort=127.0.0.1:${toString port}:3001
    '';
  };
in {
  environment.etc."containers/systemd/users/6007/yuniview-blue.container.d/ingest.conf" = dropin 18271;
  environment.etc."containers/systemd/users/6007/yuniview-green.container.d/ingest.conf" = dropin 18272;

  systemd.services.yuniview-ingest = {
    description = "yuniview agent ingestion socket";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      RuntimeDirectory = "yuniview-ingest";
      RuntimeDirectoryMode = "0755";
      ExecStart = "${pkgs.haproxy}/bin/haproxy -W -db -f ${configFile}";
      Restart = "on-failure";
      NoNewPrivileges = true;
    };
  };
}
